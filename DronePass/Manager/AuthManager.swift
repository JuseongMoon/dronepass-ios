//
//  AuthManager.swift
//  DronePass
//
//  Created by 문주성 on 7/26/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import Combine

// MARK: - Auth Error

/// 인증 관련 에러
enum AuthError: LocalizedError {
    case userNotAvailable
    case timeout
    case invalidCredential
    case firestoreError(underlying: Error)
    case dataLoadFailed
    case syncFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .userNotAvailable:
            return "인증된 사용자를 찾을 수 없습니다."
        case .timeout:
            return "인증 시간이 초과되었습니다."
        case .invalidCredential:
            return "유효하지 않은 인증 정보입니다."
        case .firestoreError(let error):
            return "Firestore 오류: \(error.localizedDescription)"
        case .dataLoadFailed:
            return "사용자 데이터를 불러오는데 실패했습니다."
        case .syncFailed(let error):
            return "동기화 실패: \(error.localizedDescription)"
        }
    }
}

@MainActor
@Observable
class AuthManager {

    static let shared = AuthManager()

    private(set) var currentAuthUser: FirebaseAuth.User?
    private(set) var currentUser: User?
    var isAuthenticated: Bool {
        return currentAuthUser != nil
    }

    /// 마지막 발생한 에러 (UI에서 표시용)
    var lastError: AuthError?

    /// 계정 전환 확인을 위한 continuation (UI 응답 대기용 async 도구).
    @ObservationIgnored
    private var accountSwitchContinuation: CheckedContinuation<Bool, Never>?

    /// 계정 전환 확인 대기 상태: nil이 아니면 UI(MainTabView)가 경고 alert를 표시(값 = 보호 대상 개수).
    var pendingAccountSwitchAtRisk: Int?

    /// currentAuthUser 설정 (외부에서 호출 가능)
    func setCurrentAuthUser(_ user: FirebaseAuth.User?) {
        self.currentAuthUser = user
    }

    /// nonisolated 접근자 (비동기 컨텍스트에서 안전하게 접근)
    nonisolated var currentAuthUserUID: String? {
        Auth.auth().currentUser?.uid
    }

    private var cancellables = Set<AnyCancellable>()
    private var isLoadingUserData = false // 중복 호출 방지 플래그

    private init() {
        currentAuthUser = Auth.auth().currentUser
        
        // AppleLoginManager의 로그인 상태 변경을 구독
        // 주의: loadCurrentUserData()는 handleAppleLoginSuccess()에서 호출하므로 여기서는 호출하지 않음
        // isLogin = true 시점에 Auth.auth().currentUser가 아직 nil일 수 있기 때문
        AppleLoginManager.shared.$isLogin
            .sink { [weak self] isLoggedIn in
                if isLoggedIn {
                    // currentAuthUser 설정만 수행, 로드는 handleAppleLoginSuccess()에서 처리
                    self?.currentAuthUser = Auth.auth().currentUser
                } else {
                    self?.currentAuthUser = nil
                    self?.currentUser = nil
                }
            }
            .store(in: &cancellables)
        
        // 앱 시작 시 현재 사용자 데이터 로드
        if currentAuthUser != nil {
            Task {
                await loadCurrentUserData()
            }
        }
    }
    
    /// Firebase Auth의 현재 사용자 객체가 준비될 때까지 대기하고 `currentAuthUser`를 설정합니다.
    /// 로그인 직후 즉시 접근 시점 경합을 방지하기 위한 안전장치입니다.
    /// - Parameter timeout: 최대 대기 시간(초)
    /// - Returns: 인증 사용자 객체가 준비되었는지 여부
    /// - Throws: `AuthError.timeout` 타임아웃 발생 시
    @discardableResult
    func ensureAuthUserAvailable(timeout: TimeInterval = 3.0) async throws -> Bool {
        // 이미 설정되어 있으면 즉시 성공
        if let user = self.currentAuthUser ?? Auth.auth().currentUser {
            self.currentAuthUser = user
            return true
        }
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let user = Auth.auth().currentUser {
                self.currentAuthUser = user
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // 타임아웃 발생
        if self.currentAuthUser == nil {
            self.lastError = .timeout
            print("❌ 인증 사용자 대기 타임아웃 (\(timeout)초)")
            throw AuthError.timeout
        }
        return true
    }

    /// 에러를 throw하지 않는 버전 (기존 호환성 유지)
    @discardableResult
    func ensureAuthUserAvailableSafe(timeout: TimeInterval = 3.0) async -> Bool {
        do {
            return try await ensureAuthUserAvailable(timeout: timeout)
        } catch {
            return false
        }
    }

    // MARK: - Provider

    /// 로그인 provider 구분 (Apple/Google 공통 후처리에서 분기용)
    private enum LoginProvider {
        case apple
        case google
    }

    // Apple 로그인 완료 후 사용자 데이터 생성 또는 업데이트
    func handleAppleLoginSuccess(email: String?, appleUserID: String) async {
        await handleLoginSuccess(email: email, provider: .apple, providerUserID: appleUserID)
    }

    // Google 로그인 완료 후 사용자 데이터 생성 또는 업데이트
    func handleGoogleLoginSuccess(email: String?, googleUserID: String?) async {
        await handleLoginSuccess(email: email, provider: .google, providerUserID: googleUserID)
    }

    /// provider 무관 공통 로그인 후처리 (Apple/Google이 동일 로직 공유)
    /// - Note: 기존 Apple 전용 로직을 그대로 옮기고 provider 분기(복구 식별자, Keychain 저장, uploadUserData)만 추가했다.
    private func handleLoginSuccess(email: String?, provider: LoginProvider, providerUserID: String?) async {
        // 로그인 직후 Auth.user가 nil일 수 있어 보장 루틴 수행
        do {
            _ = try await ensureAuthUserAvailable()
        } catch {
            self.lastError = .userNotAvailable
            print("❌ No current auth user found: \(error.localizedDescription)")
            return
        }

        guard let currentUID = (self.currentAuthUser ?? Auth.auth().currentUser)?.uid else {
            self.lastError = .userNotAvailable
            print("❌ No current auth user found")
            return
        }

        print("🔍 DEBUG: Firebase Auth UID (현재): \(currentUID)")
        print("🔍 DEBUG: Provider: \(provider)")
        print("🔍 DEBUG: Provider User ID: \(providerUserID ?? "nil")")
        print("🔍 DEBUG: Email: \(email ?? "Hidden")")

        // 🔐 Keychain 기반 계정 복구 시도 (계정 전환 여부 판별)
        let recoveryOutcome = await handleAccountRecovery(currentUID: currentUID, provider: provider, providerUserID: providerUserID, email: email)

        // 계정 전환(다른 계정으로 로그인) 처리: 미동기화 로컬 변경이 있으면 사용자 확인 후 진행
        if recoveryOutcome == .switchedAccount {
            let unsynced = hasUnsyncedLocalChangesForAccountSwitch()
            if unsynced.warn {
                print("⚠️ 계정 전환 전 미동기화 로컬 변경 감지: 보호 대상 \(unsynced.atRisk)개")
                let proceed = await requestAccountSwitchConfirmation(atRisk: unsynced.atRisk)
                if !proceed {
                    await rollbackJustAuthenticatedAccount()
                    print("🛑 계정 전환 취소됨 → 로컬 데이터 보존, 로그인 처리 중단")
                    return
                }
            }
            // 계속: 이전 계정 로컬 데이터를 비우고 새 계정 데이터로 교체
            await resetLocalDataForAccountSwitch()
        }

        // Keychain에 현재 인증 정보 저장
        KeychainHelper.shared.saveFirebaseUID(currentUID)
        if let providerUserID = providerUserID {
            switch provider {
            case .apple:
                KeychainHelper.shared.saveAppleUserID(providerUserID)
            case .google:
                KeychainHelper.shared.saveGoogleUserID(providerUserID)
            }
        }

        // 기존 사용자 데이터가 있는지 확인
        if await loadUserData(userId: currentUID) == nil {
            // 새 사용자인 경우 데이터 생성 (provider User ID 포함)
            switch provider {
            case .apple:
                await uploadUserData(userId: currentUID, email: email, appleUserID: providerUserID)
            case .google:
                await uploadUserData(userId: currentUID, email: email, googleUserID: providerUserID)
            }
        } else {
            // 기존 사용자인 경우 현재 데이터 로드
            await loadCurrentUserData()
        }

        // 로그인 성공 시 클라우드 백업 자동 활성화
        await MainActor.run {
            if !SettingManager.shared.isCloudBackupEnabled {
                SettingManager.shared.isCloudBackupEnabled = true
                print("✅ 로그인 시 클라우드 백업 자동 활성화")
            }
        }
        
        // 로그인 성공 후 실시간 백업이 활성화된 경우 자동 동기화
        await performAutoSyncIfEnabled()

        // 실시간 동기화 리스너도 즉시 재가동하여 재시작 없이 동작 보장
        await MainActor.run {
            RealtimeSyncManager.shared.resetAndRestartRealtimeSync()
        }

        // 로그인 성공 시 FCM 토큰 요청
        PushNotificationManager.shared.requestFCMToken()
        print("✅ 로그인 후 FCM 토큰 요청 완료")

        // 도형 데이터 강제 로드 보장 (로컬에 데이터가 없는 경우)
        await MainActor.run {
            if ShapeFileStore.shared.shapes.isEmpty {
                print("📦 로컬에 도형 없음 → Firebase에서 강제 로드 시작")
                Task {
                    await ShapeRepository.shared.forceLoadFromFirebase()
                }
            } else {
                print("📦 로컬에 이미 \(ShapeFileStore.shared.shapes.count)개 도형 존재")
            }
        }

        // 드론 데이터 동기화 및 모든 드론 선택 (체크박스)
        do {
            try await DroneRepository.shared.syncWithFirebase()
        } catch {
            print("⚠️ 드론 동기화 실패: \(error.localizedDescription)")
        }
        await MainActor.run {
            DroneManager.shared.selectAllDrones()
            print("🚁 로그인 후 모든 드론 자동 선택 완료: \(DroneManager.shared.selectedDroneIds.count)개")
        }

        // 계정 전환 시 새 계정의 스케치를 Firebase에서 로드 (클라우드 백업 활성화 이후 시점)
        if recoveryOutcome == .switchedAccount {
            await MainActor.run {
                SketchRepository.shared.loadSketches()
                print("✏️ 계정 전환 후 새 계정 스케치 로드 트리거")
            }
        }

        // 로그인 직후 서버 데이터로 강제 동기화 (수동 백업과 동일한 핵심 경로 = performRealtimeSync).
        // performAutoSyncIfEnabled만으로는 새 계정 도형이 로컬/저장목록에 반영되지 않는 케이스
        // (특히 계정 전환)를 확실히 해소한다: Firebase에서 도형을 받아 로컬에 병합하고 UI 갱신 알림까지 발송.
        await RealtimeSyncManager.shared.forceSyncNow()
        print("🔄 로그인 후 강제 동기화 완료 (수동 백업과 동일 경로)")

        // 동기화 완료 후 baseline 갱신 (현재 활성 도형 = 클라우드 상태) → 이후 미동기화 변경분 계산 기준
        saveSyncedShapeBaseline()
    }

    /// 계정 전환 시 이전 계정의 로컬 데이터를 비우고, 새 계정 데이터로 교체할 준비를 한다.
    /// Firebase 데이터는 건드리지 않으며, 이후 자동 동기화/로드가 새 계정 데이터를 채운다.
    private func resetLocalDataForAccountSwitch() async {
        print("🔄 계정 전환 감지 → 이전 계정 로컬 데이터 초기화 시작")

        await MainActor.run {
            // 도형 로컬 비우기 (Firebase는 그대로 둔다)
            ShapeFileStore.shared.shapes = []
            ShapeFileStore.shared.saveShapes()

            // 스케치 로컬 비우기 + 변경 추적 초기화 (이전 계정 스케치가 새 계정에 업로드되지 않도록)
            SketchFileStore.shared.clearAllSketches()
            SketchRepository.shared.resetModifiedTracking()

            // 동기화 추적 UserDefaults 초기화 (이전 계정 타임스탬프 제거)
            UserDefaults.standard.removeObject(forKey: "lastSyncTime")
            UserDefaults.standard.removeObject(forKey: "lastLocalModificationTime")
            UserDefaults.standard.removeObject(forKey: "lastBackupTime")
            UserDefaults.standard.removeObject(forKey: "lastSketchSyncTime")
            UserDefaults.standard.removeObject(forKey: "lastLocalSketchModificationTime")

            print("🔄 도형/스케치 로컬 데이터 및 동기화 추적 초기화 완료")
        }

        // 드론 로컬 비우기 + 새 계정 Firebase 드론 로드
        await DroneManager.shared.reloadForAccountSwitch()

        print("🔄 계정 전환 로컬 데이터 초기화 완료 → 새 계정 데이터 로드 예정")
    }

    // MARK: - 미동기화 변경분 baseline

    private static let syncedShapeBaselineKey = "syncedShapeBaseline"

    /// 마지막으로 클라우드와 일치했던 활성 도형 baseline(id → updatedAt)을 저장한다.
    /// 로그아웃·로그인 후 동기화 완료 시점에 호출하면, 이후의 추가/삭제/수정 변경분을 정확히 셀 수 있다.
    private func saveSyncedShapeBaseline() {
        let active = ShapeFileStore.shared.shapes.filter { $0.deletedAt == nil }
        let map = Dictionary(active.map { ($0.id.uuidString, $0.updatedAt.timeIntervalSince1970) }, uniquingKeysWith: { max($0, $1) })
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.syncedShapeBaselineKey)
        }
    }

    private func loadSyncedShapeBaseline() -> [String: TimeInterval]? {
        guard let data = UserDefaults.standard.data(forKey: Self.syncedShapeBaselineKey),
              let map = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return nil
        }
        return map
    }

    /// 계정 전환 직전, 마지막 클라우드 동기화(baseline) 이후의 **미동기화 변경분 개수**(추가+삭제+수정)를 센다.
    /// 현재 전체 도형 수가 아니라 "변경된 개수"만 카운트한다.
    /// 예) 로그아웃 시 200개였고 현재 203개(6개 추가, 3개 삭제)면 → 9개.
    private func hasUnsyncedLocalChangesForAccountSwitch() -> (warn: Bool, atRisk: Int) {
        let active = ShapeFileStore.shared.shapes.filter { $0.deletedAt == nil }
        let currentMap = Dictionary(active.map { ($0.id.uuidString, $0.updatedAt.timeIntervalSince1970) }, uniquingKeysWith: { max($0, $1) })

        guard let baseline = loadSyncedShapeBaseline() else {
            // 마지막 클라우드 상태 기록이 없으면 보수적으로 현재 활성 도형 전체를 미동기화로 간주
            let count = active.count
            print("⚠️ [baseline] 로드 결과 nil → 전체 \(count)개를 미동기화로 간주 (저장된 baseline 없음)")
            return (warn: count > 0, atRisk: count)
        }

        let baselineIds = Set(baseline.keys)
        let currentIds = Set(currentMap.keys)

        let added = currentIds.subtracting(baselineIds).count       // 추가된 도형
        let removed = baselineIds.subtracting(currentIds).count     // 삭제된 도형
        let modified = currentIds.intersection(baselineIds).reduce(0) { acc, id in
            // updatedAt이 baseline과 다르면 수정으로 카운트 (저장/복원 오차 무시용 1초 임계)
            if let b = baseline[id], let c = currentMap[id], abs(c - b) > 1.0 {
                return acc + 1
            }
            return acc
        }

        let changeCount = added + removed + modified
        print("🔍 [baseline] 미동기화 계산: current=\(currentMap.count), baseline=\(baseline.count), added=\(added), removed=\(removed), modified=\(modified) → 변경 \(changeCount)개")
        return (warn: changeCount > 0, atRisk: changeCount)
    }

    /// 계정 전환 취소 시: 방금 인증된 계정을 로그아웃하되 로컬 데이터/Keychain은 보존한다.
    /// (이 세션은 아무 것도 동기화하지 않았으므로 `signout()`의 부수작업(중복정리/FCM 비활성화)은 생략.)
    private func rollbackJustAuthenticatedAccount() async {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut() // Apple 사용자에겐 no-op, 안전
        } catch {
            print("❌ 계정 전환 취소 중 로그아웃 실패: \(error.localizedDescription)")
        }
        currentAuthUser = nil
        currentUser = nil
        // ⚠️ Keychain·로컬 도형/스케치/드론·동기화 타임스탬프 모두 유지(보존 목적).
        //    isLogin은 Auth 상태 리스너가 자동으로 false 전환한다.
    }

    /// 계정 전환 직전 사용자 확인을 요청한다. UI(MainTabView)가 `pendingAccountSwitchAtRisk`를 관찰해
    /// 경고 alert를 띄우고, 사용자의 선택을 `resolveAccountSwitch(_:)`로 전달할 때까지 suspend된다.
    private func requestAccountSwitchConfirmation(atRisk: Int) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            accountSwitchContinuation = cont
            pendingAccountSwitchAtRisk = atRisk
        }
    }

    /// UI가 사용자 선택을 전달한다. true=계속(전환 진행), false=취소(롤백).
    func resolveAccountSwitch(_ proceed: Bool) {
        pendingAccountSwitchAtRisk = nil
        accountSwitchContinuation?.resume(returning: proceed)
        accountSwitchContinuation = nil
    }

    /// 로컬 데이터 백업 생성
    private func createLocalDataBackup() async {
        await MainActor.run {
            let localShapes = ShapeFileStore.shared.shapes
            if !localShapes.isEmpty {
                // 백업 파일 생성
                let backupURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("shapes_backup_\(Date().timeIntervalSince1970).json")
                
                do {
                    let data = try JSONEncoder().encode(localShapes)
                    try data.write(to: backupURL)
                    print("💾 로컬 데이터 백업 생성: \(backupURL.lastPathComponent)")
                } catch {
                    print("❌ 로컬 데이터 백업 생성 실패: \(error)")
                }
            }
        }
    }
    
    /// 로컬 데이터 백업에서 복구
    private func restoreFromLocalBackup() async -> Bool {
        await MainActor.run {
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            do {
                let backupFiles = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("shapes_backup_") }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent } // 최신 파일 우선
                
                if let latestBackup = backupFiles.first {
                    let data = try Data(contentsOf: latestBackup)
                    let shapes = try JSONDecoder().decode([ShapeModel].self, from: data)
                    
                    ShapeFileStore.shared.shapes = shapes
                    ShapeFileStore.shared.saveShapes()
                    
                    print("✅ 로컬 백업에서 복구 완료: \(shapes.count)개 도형")
                    return true
                }
            } catch {
                print("❌ 로컬 백업 복구 실패: \(error)")
            }
            
            return false
        }
    }
    
    // 로그인용 사용자 데이터 업로드 (provider User ID 포함)
    private func uploadUserData(userId: String, email: String?, appleUserID: String? = nil, googleUserID: String? = nil) async {
        let user = User(id: userId, email: email)
        self.currentUser = user

        do {
            // User 구조체를 딕셔너리로 변환 (provider User ID 포함)
            var userData: [String: Any] = [
                "id": user.id,
                "email": user.email as Any,
                "createdAt": Timestamp(date: user.createdAt ?? Date()),
                "lastLogin": Timestamp(date: Date())
            ]

            // provider User ID가 있으면 추가 (식별 강화)
            if let appleUserID = appleUserID {
                userData["appleUserID"] = appleUserID
            }
            if let googleUserID = googleUserID {
                userData["googleUserID"] = googleUserID
            }

            try await Firestore.firestore().collection("users").document(user.id).setData(userData)
            print("✅ Successfully uploaded user data - UID: \(userId), Email: \(email ?? "Hidden"), Apple ID: \(appleUserID ?? "nil"), Google ID: \(googleUserID ?? "nil")")
            Task { await UserActivityTracker.shared.recordIfNeeded() }
        } catch {
            print("❌ Failed to upload user data with error \(error.localizedDescription)")
        }
    }
    
    // 현재 사용자 데이터 로드
    func loadCurrentUserData() async {
        // 중복 호출 방지
        if isLoadingUserData {
            print("DEBUG: 사용자 데이터 로딩 중... 중복 호출 방지")
            return
        }
        
        guard let userId = self.currentAuthUser?.uid else { 
            print("DEBUG: No auth user available to load data")
            return 
        }
        
        isLoadingUserData = true
        defer { isLoadingUserData = false }
        
        do {
            let document = try await Firestore.firestore().collection("users").document(userId).getDocument()
            
            if document.exists, let data = document.data() {
                self.currentUser = parseUserFromData(data)
                print("DEBUG: Successfully loaded current user data - UID: \(userId)")
            } else {
                print("DEBUG: User document does not exist, creating new user data")
                // 문서가 없으면 현재 Firebase Auth 정보로 새로 생성
                let email = currentAuthUser?.email
                await uploadUserData(userId: userId, email: email)
            }
        } catch {
            print("DEBUG: Failed to load user data with error \(error.localizedDescription)")
            // 에러 발생 시 기본 사용자 데이터 생성
            let email = currentAuthUser?.email
            await uploadUserData(userId: userId, email: email)
        }

        Task { await UserActivityTracker.shared.recordIfNeeded() }
    }
    
    // 특정 사용자 데이터 로드
    func loadUserData(userId: String) async -> User? {
        do {
            let document = try await Firestore.firestore().collection("users").document(userId).getDocument()
            
            if document.exists, let data = document.data() {
                return parseUserFromData(data)
            } else {
                return nil
            }
        } catch {
            print("DEBUG: Failed to load user data with error \(error.localizedDescription)")
            return nil
        }
    }
    
    // Firestore 데이터를 User 객체로 변환
    private func parseUserFromData(_ data: [String: Any]) -> User? {
        guard let id = data["id"] as? String else {
            print("DEBUG: Failed to parse user ID from Firestore data")
            return nil
        }

        let email = data["email"] as? String

        // createdAt 파싱 (Firestore Timestamp → Date)
        // createdAt 필드가 없는 초기 계정은 nil → UI에서 '가입일 미상'으로 표기
        let createdAt: Date?
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            createdAt = createdAtTimestamp.dateValue()
        } else {
            createdAt = nil
        }

        return User(id: id, email: email, createdAt: createdAt)
    }
    
    // 로그아웃
    func signout() {
        // 로그아웃 시점의 활성 도형을 baseline으로 저장 (로그인 중 자동 동기화로 현재=클라우드 상태).
        // 이후 로그아웃 상태에서 생긴 추가/삭제/수정이 계정 전환 경고의 "미동기화 개수" 기준이 된다.
        saveSyncedShapeBaseline()
        do {
            try Auth.auth().signOut()
            // Google 로컬 세션도 정리 (Apple 로그인 사용자에게는 no-op, 안전)
            GIDSignIn.sharedInstance.signOut()
            currentAuthUser = nil
            currentUser = nil

            // ⚠️ 로그아웃 시 Keychain은 유지 (재로그인 시 복구 가능)
            print("🔐 로그아웃: Keychain 데이터 유지 (복구 가능)")

            // 로그아웃 시 도형 데이터 정리
            Task { @MainActor in
                // ShapeFileStore에서 중복 제거
                let currentShapes = ShapeFileStore.shared.shapes
                let uniqueShapes = Array(Set(currentShapes.map { $0.id })).compactMap { id in
                    currentShapes.first { $0.id == id }
                }

                if uniqueShapes.count != currentShapes.count {
                    print("🧹 로그아웃 시 중복 도형 제거: \(currentShapes.count)개 → \(uniqueShapes.count)개")
                    ShapeFileStore.shared.shapes = uniqueShapes
                    ShapeFileStore.shared.saveShapes()
                }

                // 로그아웃 시 FCM 토큰 비활성화
                await PushNotificationManager.shared.deactivateFCMToken()
                print("✅ 로그아웃 후 FCM 토큰 비활성화 완료")
            }

            print("✅ 로그아웃 완료")
        } catch {
            print("❌ 로그아웃 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 회원 탈퇴

    /// 회원 탈퇴 (익명화 데이터 저장 + 사용자 데이터 삭제 + Auth 계정 삭제)
    func deleteAccount() async throws {
        guard let userId = currentAuthUser?.uid else {
            throw AccountDeletionError.notAuthenticated
        }

        print("🚨 회원 탈퇴 시작: \(userId)")

        // Step 1: 익명화 데이터 생성 및 저장
        await saveAnonymousData(userId: userId)

        // Step 2: 실제 사용자 데이터 삭제
        try await deleteUserDataFromFirestore(userId: userId)

        // Step 3: Firebase Auth 계정 삭제
        try await deleteAuthAccount()

        print("✅ 회원 탈퇴 완료")
    }

    /// Step 1: 익명화 데이터 저장
    private func saveAnonymousData(userId: String) async {
        do {
            let anonymousId = UUID().uuidString
            print("🔑 익명 ID 생성: \(anonymousId)")

            let generator = AnalyticsDataGenerator.shared

            // 사용자 통계 생성 (email 제외)
            let userData = generator.generateAnonymizedUserData(user: currentUser)

            // 도형 데이터 수집
            let shapes = await MainActor.run { ShapeFileStore.shared.shapes }
            let shapeDataArray = generator.generateShapeData(shapes)

            // 드론 데이터 수집
            let drones = await MainActor.run { DroneManager.shared.drones }
            let droneDataArray = generator.generateDroneData(drones)

            // Firestore에 저장
            let db = Firestore.firestore()
            let anonymousUserRef = db.collection("analytics").document("deleted_users").collection("users").document(anonymousId)

            // 사용자 통계 저장
            try await anonymousUserRef.setData(userData)
            print("✅ 사용자 통계 저장 완료")

            // 도형 데이터 저장 (배치 처리)
            if !shapeDataArray.isEmpty {
                let shapeBatches = shapeDataArray.chunked(into: 500)
                for (index, batch) in shapeBatches.enumerated() {
                    let batchWrite = db.batch()
                    for shapeData in batch {
                        if let shapeId = shapeData["id"] as? String {
                            let shapeRef = anonymousUserRef.collection("shapes").document(shapeId)
                            batchWrite.setData(shapeData, forDocument: shapeRef)
                        }
                    }
                    try await batchWrite.commit()
                    print("✅ 도형 데이터 배치 \(index + 1)/\(shapeBatches.count) 저장 완료")
                }
                print("✅ 총 \(shapeDataArray.count)개 도형 저장 완료")
            }

            // 드론 데이터 저장
            if !droneDataArray.isEmpty {
                let droneBatch = db.batch()
                for droneData in droneDataArray {
                    if let droneId = droneData["id"] as? String {
                        let droneRef = anonymousUserRef.collection("drones").document(droneId)
                        droneBatch.setData(droneData, forDocument: droneRef)
                    }
                }
                try await droneBatch.commit()
                print("✅ 총 \(droneDataArray.count)개 드론 저장 완료")
            }

            print("✅ 익명화 데이터 저장 완료: \(shapeDataArray.count)개 도형, \(droneDataArray.count)개 드론")

        } catch {
            print("⚠️ 익명 데이터 저장 실패 (계속 진행): \(error)")
            // 실패해도 계속 진행
        }
    }

    /// Step 2: Firestore 사용자 데이터 삭제
    private func deleteUserDataFromFirestore(userId: String) async throws {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)

        var deleteAttempts = 0
        var lastError: Error?

        while deleteAttempts < 3 {
            do {
                // shapes 컬렉션 삭제
                let shapesSnapshot = try await userRef.collection("shapes").getDocuments()
                if !shapesSnapshot.documents.isEmpty {
                    let shapeBatches = shapesSnapshot.documents.chunked(into: 500)
                    for batch in shapeBatches {
                        let batchWrite = db.batch()
                        for doc in batch {
                            batchWrite.deleteDocument(doc.reference)
                        }
                        try await batchWrite.commit()
                    }
                    print("✅ shapes 컬렉션 삭제 완료: \(shapesSnapshot.documents.count)개")
                }

                // drones 컬렉션 삭제
                let dronesSnapshot = try await userRef.collection("drones").getDocuments()
                if !dronesSnapshot.documents.isEmpty {
                    let droneBatch = db.batch()
                    for doc in dronesSnapshot.documents {
                        droneBatch.deleteDocument(doc.reference)
                    }
                    try await droneBatch.commit()
                    print("✅ drones 컬렉션 삭제 완료: \(dronesSnapshot.documents.count)개")
                }

                // metadata 컬렉션 삭제
                let metadataSnapshot = try await userRef.collection("metadata").getDocuments()
                if !metadataSnapshot.documents.isEmpty {
                    let metadataBatch = db.batch()
                    for doc in metadataSnapshot.documents {
                        metadataBatch.deleteDocument(doc.reference)
                    }
                    try await metadataBatch.commit()
                    print("✅ metadata 컬렉션 삭제 완료")
                }

                // 사용자 문서 삭제
                try await userRef.delete()
                print("✅ 사용자 문서 삭제 완료")

                // 클라우드 연결만 해제, 로컬 데이터는 유지
                await MainActor.run {
                    // ✅ ShapeFileStore.shared.shapes는 그대로 유지
                    // ✅ DroneManager.shared.drones는 그대로 유지

                    // 클라우드 관련 UserDefaults만 제거
                    UserDefaults.standard.removeObject(forKey: "lastSyncTime")
                    UserDefaults.standard.removeObject(forKey: "lastBackupTime")
                    UserDefaults.standard.set(false, forKey: "isCloudBackupEnabled")

                    // ✅ 로컬 드론/도형 설정은 유지 (사용자 데이터 보존)
                    // selectedDroneId, selectedDroneIds는 유지
                    // localDrones는 유지
                    // hasLegacyShapesMigrated는 유지

                    print("✅ 클라우드 연결 해제 완료, 로컬 데이터 유지됨")
                    print("📊 보존된 데이터: 도형 \(ShapeFileStore.shared.shapes.count)개, 드론 \(DroneManager.shared.activeDrones.count)개")
                }

                // 실시간 동기화 중지
                await MainActor.run {
                    RealtimeSyncManager.shared.stopRealtimeSync()
                    print("✅ 실시간 동기화 중지 완료")
                }

                print("✅ Firestore 데이터 삭제 완료")
                return

            } catch {
                lastError = error
                deleteAttempts += 1
                if deleteAttempts < 3 {
                    print("⚠️ Firestore 삭제 실패 (재시도 \(deleteAttempts)/3): \(error)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초 대기
                }
            }
        }

        // 3회 재시도 후에도 실패하면 경고만 하고 계속 진행
        if let error = lastError {
            print("❌ Firestore 데이터 삭제 실패 (계속 진행): \(error)")
        }
    }

    /// Step 3: Firebase Auth 계정 삭제
    private func deleteAuthAccount() async throws {
        do {
            try await Auth.auth().currentUser?.delete()

            // Google 로컬 세션도 정리 (Apple 로그인 사용자에게는 no-op, 안전)
            GIDSignIn.sharedInstance.signOut()

            // 로그아웃 처리
            currentAuthUser = nil
            currentUser = nil

            // 🔐 회원 탈퇴 시 Keychain 완전 삭제 (복구 불가)
            KeychainHelper.shared.deleteAllAuthData()
            print("🔐 회원 탈퇴: Keychain 데이터 완전 삭제")

            await MainActor.run {
                AppleLoginManager.shared.isLogin = false

                // 지도 오버레이 정리
                NotificationCenter.default.post(
                    name: Notification.Name("ClearMapOverlays"),
                    object: nil
                )
            }

            print("✅ Firebase Auth 계정 삭제 완료")

        } catch let error as NSError {
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw AccountDeletionError.requiresRecentLogin
            }
            throw AccountDeletionError.authDeletionFailed
        }
    }
    
    /// 드론 로딩이 완료될 때까지 대기
    private func waitForDroneLoadingIfNeeded() async {
        let maxWaitTime: TimeInterval = 3.0
        let startTime = Date()

        while !DroneManager.shared.hasCompletedInitialLoad {
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                print("⚠️ 드론 로딩 대기 타임아웃")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        if DroneManager.shared.hasCompletedInitialLoad {
            print("✅ 드론 로딩 완료 확인 - 도형 동기화 시작")
        }
    }

    /// 로그인 성공 후 실시간 백업이 활성화된 경우 자동 동기화
    private func performAutoSyncIfEnabled() async {
        if SettingManager.shared.isCloudBackupEnabled {
            print("🔄 로그인 후 자동 동기화 시작...")

            // 드론 정보 먼저 로딩 대기
            await waitForDroneLoadingIfNeeded()

            // 동기화 전 로컬 데이터 백업 생성
            await createLocalDataBackup()
            
            do {
                // 인증 준비 보장 (로그인 직후 경합 방지)
                _ = try await ensureAuthUserAvailable()
                // 1. 로컬 데이터 상태 확인
                let localShapes = await MainActor.run {
                    return ShapeFileStore.shared.shapes
                }
                let hasLocalData = !localShapes.isEmpty
                
                // 2. 마지막 동기화 시간 확인
                let lastSyncTime = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date ?? Date.distantPast
                let isFirstSync = lastSyncTime == Date.distantPast
                
                // 3. 로컬 변경사항 확인
                let hasLocalChanges = await MainActor.run {
                    return UserDefaults.standard.object(forKey: "lastLocalModificationTime") != nil
                }
                
                print("🔍 동기화 상태 분석:")
                print("   - 로컬 데이터: \(localShapes.count)개")
                print("   - 첫 동기화: \(isFirstSync ? "예" : "아니오")")
                print("   - 로컬 변경사항: \(hasLocalChanges ? "있음" : "없음")")
                
                // 4. 동기화 전략 결정
                if hasLocalData && (isFirstSync || hasLocalChanges) {
                    // 로컬 데이터가 있고 첫 동기화이거나 변경사항이 있는 경우
                    print("📤 로컬 데이터를 Firebase에 우선 업로드합니다...")
                    
                    let activeLocalShapes = await MainActor.run {
                        return ShapeFileStore.shared.shapes
                    }
                    
                    if !activeLocalShapes.isEmpty {
                        try await ShapeFirebaseStore.shared.saveShapes(activeLocalShapes)
                        print("✅ 로컬 데이터 Firebase 업로드 완료: \(activeLocalShapes.count)개 활성 도형")
                        
                        // 변경 추적 초기화
                        await MainActor.run {
                            UserDefaults.standard.removeObject(forKey: "lastLocalModificationTime")
                        }
                    }
                    
                    // 로컬 데이터를 유지하면서 Firebase의 추가 데이터 병합 + 색상 동기화
                    print("🔄 로컬 데이터를 유지하면서 Firebase의 추가 데이터 병합...")
                    let firebaseShapes = try await ShapeFirebaseStore.shared.loadShapes()
                    
                    await MainActor.run {
                        let currentLocalShapes = ShapeFileStore.shared.shapes
                        let localShapeIds = Set(currentLocalShapes.map { $0.id })
                        
                        // Firebase에만 있는 도형들을 로컬에 추가 (로컬 데이터는 보존)
                        let shapesToAdd = firebaseShapes.filter { !localShapeIds.contains($0.id) }
                        
                        var mutatedLocal = currentLocalShapes
                        if !shapesToAdd.isEmpty {
                            mutatedLocal.append(contentsOf: shapesToAdd)
                            print("✅ Firebase의 추가 도형 \(shapesToAdd.count)개를 로컬에 병합 완료")
                        } else {
                            print("✅ Firebase에 추가 데이터가 없어 로컬 데이터 유지")
                        }
                        
                        // 서버 기준으로 활성 도형 색상 통일 (만료된 도형 제외)
                        if let unifiedColor = firebaseShapes.first(where: { $0.deletedAt == nil })?.color {
                            var changedCount = 0
                            for i in 0..<mutatedLocal.count {
                                if mutatedLocal[i].deletedAt == nil && mutatedLocal[i].color != unifiedColor {
                                    mutatedLocal[i].color = unifiedColor
                                    changedCount += 1
                                }
                            }
                            if changedCount > 0 {
                                print("🎨 로컬 활성 도형 색상 통일: \(changedCount)개 → \(unifiedColor)")
                            }
                        }
                        
                        // 동일 ID 도형은 서버 updatedAt이 더 최신인 경우에만 서버로 덮어쓰기 (LWW)
                        let serverById = Dictionary(firebaseShapes.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
                        var overwriteCount = 0
                        for i in 0..<mutatedLocal.count {
                            if let serverShape = serverById[mutatedLocal[i].id], serverShape.updatedAt >= mutatedLocal[i].updatedAt {
                                if mutatedLocal[i] != serverShape {
                                    mutatedLocal[i] = serverShape
                                    overwriteCount += 1
                                }
                            }
                        }
                        if overwriteCount > 0 {
                            print("🔁 서버 값으로 덮어쓰기(LWW): \(overwriteCount)개")
                        }
                        
                        ShapeFileStore.shared.shapes = mutatedLocal
                        ShapeFileStore.shared.saveShapes()
                    }
                    
                } else if !hasLocalData {
                    // 로컬 데이터가 없는 경우 Firebase에서 다운로드
                    print("📝 로컬 데이터가 없어 Firebase에서 데이터를 다운로드합니다...")
                    
                    print("📥 Firebase에서 도형 데이터 다운로드 시작...")
                    let firebaseShapes = try await ShapeFirebaseStore.shared.loadShapes()
                    
                    print("📥 Firebase 데이터로 로컬 업데이트합니다...")
                    await MainActor.run {
                        ShapeFileStore.shared.shapes = firebaseShapes
                        ShapeFileStore.shared.saveShapes()
                    }
                    print("✅ Firebase 데이터로 로컬 업데이트 완료: \(firebaseShapes.count)개")
                    
                } else {
                    // 로컬 데이터가 있고 변경사항이 없는 경우 변경사항만 확인
                    print("📝 로컬 데이터가 있고 변경사항이 없어 변경사항만 확인합니다...")
                    
                    // Firebase에서 변경사항 확인
                    let hasChanges = try await ShapeFirebaseStore.shared.hasChanges()
                    
                    if hasChanges {
                        print("🔄 Firebase에 변경사항이 감지되어 병합합니다...")
                        let firebaseShapes = try await ShapeFirebaseStore.shared.loadShapes()
                        
                        await MainActor.run {
                            let currentLocalShapes = ShapeFileStore.shared.shapes
                            let localShapeIds = Set(currentLocalShapes.map { $0.id })
                            
                            // Firebase에만 있는 도형들을 로컬에 추가
                            let shapesToAdd = firebaseShapes.filter { !localShapeIds.contains($0.id) }
                            
                            var mutatedLocal = currentLocalShapes
                            if !shapesToAdd.isEmpty {
                                mutatedLocal.append(contentsOf: shapesToAdd)
                                print("✅ Firebase의 추가 도형 \(shapesToAdd.count)개를 로컬에 병합 완료")
                            } else {
                                print("✅ Firebase에 추가 데이터가 없음")
                            }
                            
                            // 서버 기준으로 활성 도형 색상 통일 (만료된 도형 제외)
                            if let unifiedColor = firebaseShapes.first(where: { $0.deletedAt == nil })?.color {
                                var changedCount = 0
                                for i in 0..<mutatedLocal.count {
                                    if mutatedLocal[i].deletedAt == nil && mutatedLocal[i].color != unifiedColor {
                                        mutatedLocal[i].color = unifiedColor
                                        changedCount += 1
                                    }
                                }
                                if changedCount > 0 {
                                    print("🎨 로컬 활성 도형 색상 통일: \(changedCount)개 → \(unifiedColor)")
                                }
                            }
                            
                            // 동일 ID 도형은 서버 updatedAt이 더 최신인 경우에만 서버로 덮어쓰기 (LWW)
                            let serverById = Dictionary(firebaseShapes.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
                            var overwriteCount = 0
                            for i in 0..<mutatedLocal.count {
                                if let serverShape = serverById[mutatedLocal[i].id], serverShape.updatedAt >= mutatedLocal[i].updatedAt {
                                    if mutatedLocal[i] != serverShape {
                                        mutatedLocal[i] = serverShape
                                        overwriteCount += 1
                                    }
                                }
                            }
                            if overwriteCount > 0 {
                                print("🔁 서버 값으로 덮어쓰기(LWW): \(overwriteCount)개")
                            }
                            
                            ShapeFileStore.shared.shapes = mutatedLocal
                            ShapeFileStore.shared.saveShapes()
                        }
                    } else {
                        print("✅ 변경사항이 없어 동기화를 건너뜁니다.")
                    }
                }
                
                // 동기화 시간 업데이트
                UserDefaults.standard.set(Date(), forKey: "lastSyncTime")
                UserDefaults.standard.set(Date(), forKey: "lastBackupTime")

                // 동기화 후 UI 갱신 알림 — 다운로드/병합 분기 모두에서 저장목록 등이 즉시 갱신되도록 보장.
                // (계정 전환 시 다운로드한 새 계정 도형이 수동 백업 없이 바로 표시됨)
                NotificationCenter.default.post(name: .shapesDidChange, object: nil)

            } catch {
                print("❌ 로그인 후 자동 동기화 실패: \(error)")
                
                // 동기화 실패 시 백업에서 복구 시도
                print("🔄 동기화 실패로 인한 백업 복구 시도...")
                let restored = await restoreFromLocalBackup()
                if restored {
                    print("✅ 백업에서 복구 성공")
                } else {
                    print("❌ 백업 복구 실패")
                }
            }
        } else {
            print("📝 실시간 백업이 비활성화되어 있어 자동 동기화를 건너뜁니다.")
        }
    }
    
    // MARK: - Keychain 기반 계정 복구

    /// 계정 복구/전환 판별 결과
    private enum AccountRecoveryOutcome {
        case keepLocalData    // 첫 로그인 / 같은 계정 재로그인 / 동일 사용자 마이그레이션 → 로컬 데이터 유지
        case switchedAccount  // 다른 계정으로 전환 → 이전 계정 로컬 데이터를 새 계정 것으로 교체
    }

    /// Keychain에 저장된 이전 UID를 확인하고 필요 시 데이터 마이그레이션. 계정 전환 여부를 반환한다.
    @discardableResult
    private func handleAccountRecovery(currentUID: String, provider: LoginProvider, providerUserID: String?, email: String?) async -> AccountRecoveryOutcome {
        print("🔐 === 계정 복구 프로세스 시작 ===")

        // 1. Keychain에서 이전 Firebase UID 확인
        guard let savedUID = KeychainHelper.shared.loadFirebaseUID() else {
            print("🔐 Keychain에 저장된 UID 없음 → 신규 사용자 또는 첫 로그인")
            return .keepLocalData
        }

        // provider별 Keychain에 저장된 식별자 로드
        let savedProviderUserID: String?
        switch provider {
        case .apple:
            savedProviderUserID = KeychainHelper.shared.loadAppleUserID()
        case .google:
            savedProviderUserID = KeychainHelper.shared.loadGoogleUserID()
        }

        print("🔐 Keychain에서 로드된 정보:")
        print("   - 저장된 Firebase UID: \(savedUID)")
        print("   - 저장된 Provider User ID: \(savedProviderUserID ?? "nil")")
        print("   - 현재 Firebase UID: \(currentUID)")
        print("   - 현재 Provider User ID: \(providerUserID ?? "nil")")

        // 2. UID가 동일하면 복구 불필요
        if savedUID == currentUID {
            print("✅ UID 일치 → 복구 불필요, 정상 로그인")
            // 현재 계정의 provider User ID 업데이트 (변경될 수 있음)
            await updateUserMetadata(userId: currentUID, provider: provider, providerUserID: providerUserID)
            return .keepLocalData
        }

        print("⚠️ UID 불일치 감지!")
        print("   → 앱 재설치 또는 계정 권한 재설정으로 인한 새 UID 발급")

        // 3. Firestore에서 이전 계정 확인
        let oldAccountExists = await checkUserExists(userId: savedUID)

        if !oldAccountExists {
            print("📝 이전 계정(\(savedUID))이 Firestore에 없음 → 복구 불가, 계정 전환으로 처리")
            return .switchedAccount
        }

        // 4. 이전 계정의 provider User ID 확인
        let oldProviderUserID = await getProviderUserID(userId: savedUID, provider: provider)

        print("🔍 이전 계정 분석:")
        print("   - 이전 계정의 Provider User ID: \(oldProviderUserID ?? "nil")")

        // 5. 같은 사용자 판별:
        //    "직전 UID(savedUID) 계정의 Firestore 식별자(oldProviderUserID)"가 "현재 로그인 식별자(providerUserID)"와
        //    일치할 때만 동일 사용자로 보고 마이그레이션한다. 마이그레이션은 fromUID=savedUID로 복사하므로,
        //    savedUID 계정이 곧 현재 사용자임을 보장하는 이 신호만 신뢰한다.
        //    Keychain의 savedProviderUserID는 provider별로 누적 저장돼 직전 firebaseUID와 시점이 어긋날 수 있어
        //    (예: Apple A → Google G → Apple A 교차 전환) 판별 기준에서 제외한다. 식별 불가 시 안전하게 계정 전환 처리.
        let isSameUser: Bool
        if let providerUserID, let oldProviderUserID {
            isSameUser = (oldProviderUserID == providerUserID)
        } else {
            isSameUser = false
        }

        if isSameUser {
            print("✅ 동일 사용자 확인됨 → 데이터 마이그레이션 시작")
            await migrateUserData(fromUID: savedUID, toUID: currentUID, provider: provider, providerUserID: providerUserID)
            print("🔐 === 계정 복구 프로세스 완료 ===")
            return .keepLocalData
        } else {
            print("⚠️ 다른 사용자로 판단됨 → 계정 전환 처리 (로컬 데이터 교체)")
            print("🔐 === 계정 복구 프로세스 완료 ===")
            return .switchedAccount
        }
    }

    /// 사용자 메타데이터 업데이트 (provider User ID, lastLogin)
    private func updateUserMetadata(userId: String, provider: LoginProvider, providerUserID: String?) async {
        do {
            let userRef = Firestore.firestore().collection("users").document(userId)
            var updateData: [String: Any] = [
                "lastLogin": Timestamp(date: Date())
            ]
            if let providerUserID = providerUserID {
                switch provider {
                case .apple: updateData["appleUserID"] = providerUserID
                case .google: updateData["googleUserID"] = providerUserID
                }
            }
            try await userRef.setData(updateData, merge: true)
            print("📝 사용자 메타데이터 업데이트 완료: \(userId)")
        } catch {
            print("❌ 사용자 메타데이터 업데이트 실패: \(error.localizedDescription)")
        }
    }

    /// Firestore에서 사용자 존재 여부 확인
    private func checkUserExists(userId: String) async -> Bool {
        do {
            let document = try await Firestore.firestore().collection("users").document(userId).getDocument()
            return document.exists
        } catch {
            print("❌ 사용자 존재 확인 실패: \(error.localizedDescription)")
            return false
        }
    }

    /// Firestore에서 provider User ID 가져오기
    private func getProviderUserID(userId: String, provider: LoginProvider) async -> String? {
        let fieldName: String
        switch provider {
        case .apple: fieldName = "appleUserID"
        case .google: fieldName = "googleUserID"
        }
        do {
            let document = try await Firestore.firestore().collection("users").document(userId).getDocument()
            return document.data()?[fieldName] as? String
        } catch {
            print("❌ Provider User ID 조회 실패: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 데이터 마이그레이션

    /// 이전 UID의 모든 데이터를 새 UID로 마이그레이션
    private func migrateUserData(fromUID: String, toUID: String, provider: LoginProvider, providerUserID: String?) async {
        print("📦 === 데이터 마이그레이션 시작 ===")
        print("   FROM: \(fromUID)")
        print("   TO: \(toUID)")

        let db = Firestore.firestore()

        do {
            // 1. 사용자 기본 정보 복사
            let oldUserRef = db.collection("users").document(fromUID)
            let oldUserDoc = try await oldUserRef.getDocument()

            if let oldUserData = oldUserDoc.data() {
                let newUserRef = db.collection("users").document(toUID)

                // 기존 데이터를 복사하되 provider User ID와 lastLogin은 최신 정보로 업데이트
                var newUserData = oldUserData
                newUserData["id"] = toUID
                if let providerUserID = providerUserID {
                    switch provider {
                    case .apple: newUserData["appleUserID"] = providerUserID
                    case .google: newUserData["googleUserID"] = providerUserID
                    }
                }
                newUserData["lastLogin"] = Timestamp(date: Date())
                newUserData["migratedFrom"] = fromUID
                newUserData["migratedAt"] = Timestamp(date: Date())

                try await newUserRef.setData(newUserData)
                print("✅ 사용자 기본 정보 복사 완료")
            }

            // 2. shapes 컬렉션 마이그레이션
            let shapesCount = await migrateCollection(
                fromUserID: fromUID,
                toUserID: toUID,
                collectionName: "shapes"
            )
            print("✅ Shapes 마이그레이션 완료: \(shapesCount)개")

            // 3. drones 컬렉션 마이그레이션
            let dronesCount = await migrateCollection(
                fromUserID: fromUID,
                toUserID: toUID,
                collectionName: "drones"
            )
            print("✅ Drones 마이그레이션 완료: \(dronesCount)개")

            // 4. metadata 컬렉션 마이그레이션
            let metadataCount = await migrateCollection(
                fromUserID: fromUID,
                toUserID: toUID,
                collectionName: "metadata"
            )
            print("✅ Metadata 마이그레이션 완료: \(metadataCount)개")

            // 5. 이전 계정에 마이그레이션 완료 플래그 설정 (삭제하지 않음 - 백업 용도)
            try await oldUserRef.setData([
                "migrated": true,
                "migratedTo": toUID,
                "migratedAt": Timestamp(date: Date())
            ], merge: true)
            print("✅ 이전 계정에 마이그레이션 플래그 설정 완료")

            print("📦 === 데이터 마이그레이션 완료 ===")
            print("   총 복사된 데이터: Shapes \(shapesCount)개, Drones \(dronesCount)개, Metadata \(metadataCount)개")

        } catch {
            print("❌ 데이터 마이그레이션 실패: \(error.localizedDescription)")
        }
    }

    /// 특정 컬렉션의 모든 문서를 다른 사용자로 복사
    private func migrateCollection(fromUserID: String, toUserID: String, collectionName: String) async -> Int {
        let db = Firestore.firestore()

        do {
            // 이전 사용자의 컬렉션 문서들 가져오기
            let oldCollectionRef = db.collection("users").document(fromUserID).collection(collectionName)
            let snapshot = try await oldCollectionRef.getDocuments()

            guard !snapshot.documents.isEmpty else {
                print("📭 \(collectionName) 컬렉션이 비어있음")
                return 0
            }

            // 새 사용자의 컬렉션에 배치 복사
            let newCollectionRef = db.collection("users").document(toUserID).collection(collectionName)

            // Firestore 배치 제한 (500개)
            let batches = snapshot.documents.chunked(into: 500)

            for (index, batch) in batches.enumerated() {
                let batchWrite = db.batch()

                for doc in batch {
                    let newDocRef = newCollectionRef.document(doc.documentID)
                    batchWrite.setData(doc.data(), forDocument: newDocRef)
                }

                try await batchWrite.commit()
                print("📦 \(collectionName) 배치 \(index + 1)/\(batches.count) 복사 완료")
            }

            return snapshot.documents.count

        } catch {
            print("❌ \(collectionName) 마이그레이션 실패: \(error.localizedDescription)")
            return 0
        }
    }

}

// MARK: - Account Deletion Error

/// 회원 탈퇴 시 발생할 수 있는 에러
enum AccountDeletionError: LocalizedError {
    case requiresRecentLogin
    case anonymousDataSaveFailed
    case userDataDeletionFailed
    case authDeletionFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .requiresRecentLogin:
            return "보안을 위해 다시 로그인한 후 탈퇴해주세요."
        case .anonymousDataSaveFailed:
            return "익명 데이터 저장 중 오류가 발생했습니다."
        case .userDataDeletionFailed:
            return "사용자 데이터 삭제 중 오류가 발생했습니다."
        case .authDeletionFailed:
            return "계정 삭제 중 오류가 발생했습니다."
        case .notAuthenticated:
            return "로그인된 사용자가 없습니다."
        }
    }
}
