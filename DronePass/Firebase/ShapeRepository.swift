import Foundation
import Firebase
import FirebaseAuth
import Combine

@MainActor
final class ShapeRepository: ShapeStoreProtocol, ObservableObject {
    typealias ShapeType = ShapeModel
    static let shared = ShapeRepository()

    private var store: any ShapeStoreProtocol<ShapeModel>
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false  // @MainActor로 자동 보호됨
    private var storeUpdateWorkItem: DispatchWorkItem?

    // 중복 알림 전송 방지를 위한 디바운싱
    private var lastNotificationTime: Date = Date.distantPast
    private let notificationDebounceInterval: TimeInterval = 0.1 // 100ms

    // 동기화 상태 추적
    @Published var syncStatus: SyncStatus = .idle
    
    private init() {
        // 먼저 모든 stored property 초기화
        self.store = ShapeFileStore.shared // 임시로 기본값 설정
        
        // 그 다음 실제 저장소 결정
        self.store = determineStore()
        
        // 로그인 상태와 클라우드 백업 설정 변경을 감지하여 저장소 변경 (디바운스 적용)
        Publishers.CombineLatest(
            AppleLoginManager.shared.$isLogin,
            SettingManager.shared.$isCloudBackupEnabled
        )
        .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.updateStoreWithDebounce()
        }
        .store(in: &cancellables)
    }
    
    /// 중복 알림 전송 방지를 위한 디바운싱 알림 전송
    private func sendShapesDidChangeNotification() {
        let now = Date()
        if now.timeIntervalSince(lastNotificationTime) >= notificationDebounceInterval {
            NotificationCenter.default.post(name: .shapesDidChange, object: nil)
            lastNotificationTime = now
            print("🔄 shapesDidChange 알림 전송")
        } else {
            print("📝 알림 디바운싱: 이전 알림으로부터 \(String(format: "%.3f", now.timeIntervalSince(lastNotificationTime)))초 경과")
        }
    }
    
    /// 현재 상태에 따라 적절한 저장소를 결정
    private func determineStore() -> any ShapeStoreProtocol<ShapeModel> {
        if AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled {
            return ShapeFirebaseStore.shared
        } else {
            return ShapeFileStore.shared
        }
    }
    
    /// 디바운스를 적용한 저장소 업데이트
    private func updateStoreWithDebounce() {
        // 이전 작업이 있다면 취소
        storeUpdateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateStore()
        }
        
        storeUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
    
    /// 저장소를 업데이트하고 필요시 동기화 수행
    private func updateStore() {
        let newStore = determineStore()
        
        // 저장소 타입이 변경된 경우에만 처리
        let currentIsFirebase = store is ShapeFirebaseStore
        let newIsFirebase = newStore is ShapeFirebaseStore
        
        if currentIsFirebase != newIsFirebase {
            store = newStore
            
            // 동기화 중이 아닐 때만 새로운 동기화 시작
            guard !isSyncing else {
                print("⚠️ 동기화가 이미 진행 중입니다. 대기...")
                return
            }
            
            // 비동기적으로 동기화 수행하여 SwiftUI 상태 업데이트 문제 방지
            Task {
                // 인증 준비 보장 (로그인 전환 직후 경합 방지)
                _ = await AuthManager.shared.ensureAuthUserAvailableSafe()
                await MainActor.run {}
                // 로그인 시 로컬 -> Firebase 동기화
                if newIsFirebase {
                    await syncLocalToFirebaseSafely()
                }
                // 로그아웃 시 Firebase -> 로컬 동기화
                else if currentIsFirebase {
                    await syncFirebaseToLocalSafely()
                }
            }
        }
    }
    
    /// 안전한 로컬 -> Firebase 동기화
    private func syncLocalToFirebaseSafely() async {
        await performSafeSync(operation: .localToFirebase) {
            do {
                // 로컬의 활성 도형만 Firebase에 업로드
                let activeLocalShapes = await MainActor.run {
                    return ShapeFileStore.shared.shapes
                }
                
                if !activeLocalShapes.isEmpty {
                    try await ShapeFirebaseStore.shared.saveShapes(activeLocalShapes)
                    print("✅ 로컬 활성 도형 \(activeLocalShapes.count)개를 Firebase에 안전 동기화 완료")
                }
                
                // 동기화 성공 시점에 마지막 백업 시간 저장
                Task { @MainActor in
                    UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                }
                
            } catch {
                print("❌ 로컬 -> Firebase 동기화 실패: \(error)")
                throw error
            }
        }
    }
    
    /// 안전한 Firebase -> 로컬 동기화
    private func syncFirebaseToLocalSafely() async {
        // 미인증(로그아웃) 상태에서는 Firebase→로컬 동기화가 무의미하고, 실패 시 아래 백업 복구가
        // 도형 updatedAt을 오염시키므로 아예 시작하지 않는다(로컬 데이터는 그대로 보존).
        guard AuthManager.shared.currentAuthUserUID != nil else {
            print("⏭️ 미인증 상태 → Firebase→로컬 동기화 스킵 (로컬 데이터 보존)")
            return
        }
        await performSafeSync(operation: .firebaseToLocal) {
            // 로컬 데이터 백업
            let localBackup = try await ShapeFileStore.shared.loadShapes()

            do {
                let firebaseShapes = try await ShapeFirebaseStore.shared.loadShapes()

                // Firebase에만 있는 도형들을 로컬에 병합한다. addShape는 updatedAt을 현재 시각으로
                // 갱신하므로 사용하지 않고, 기존 + 다운로드분을 한 번에 설정한다(updatedAt 보존, didSet이 id-unique 보장).
                let localShapeIds = Set(localBackup.map { $0.id })
                let shapesToDownload = firebaseShapes.filter { !localShapeIds.contains($0.id) }

                if !shapesToDownload.isEmpty {
                    await MainActor.run {
                        ShapeFileStore.shared.shapes = ShapeFileStore.shared.shapes + shapesToDownload
                        ShapeFileStore.shared.saveShapes()
                    }
                }

                // 검증: 다운로드된 데이터 확인
                let verifyShapes = try await ShapeFileStore.shared.loadShapes()
                let downloadedIds = Set(shapesToDownload.map { $0.id })
                let verifyIds = Set(verifyShapes.map { $0.id })

                if !downloadedIds.isSubset(of: verifyIds) {
                    throw SyncError.verificationFailed
                }

                print("✅ Firebase 도형 \(shapesToDownload.count)개를 로컬에 안전 동기화 완료")

            } catch {
                print("❌ Firebase -> 로컬 동기화 실패: \(error)")

                // 실패 시 로컬 데이터 복구: addShape 루프(updatedAt 갱신·반복 저장)가 아니라
                // 백업을 그대로 복원한다(updatedAt 보존, 1회 저장 → dataCorruption 경합 방지).
                print("🔄 로컬 데이터 백업에서 복구 중...")
                await MainActor.run {
                    ShapeFileStore.shared.shapes = localBackup
                    ShapeFileStore.shared.saveShapes()
                }

                throw error
            }
        }
    }
    
    /// 안전한 동기화 작업 실행
    private func performSafeSync(operation: SyncOperation, _ syncWork: @escaping () async throws -> Void) async {
        // 이미 동기화 중이면 대기
        guard !isSyncing else {
            print("⚠️ 다른 동기화 작업이 진행 중입니다.")
            return
        }
        
        isSyncing = true
        
        Task { @MainActor in
            syncStatus = .syncing(operation)
        }
        
        do {
            try await syncWork()
            
            Task { @MainActor in
                syncStatus = .completed(operation)
            }
            
            // 완료 상태를 잠시 보여준 후 idle로 변경
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2초
            
            Task { @MainActor in
                syncStatus = .idle
            }
            
        } catch {
            Task { @MainActor in
                syncStatus = .failed(operation, error)
            }
            
            // 에러 상태를 잠시 보여준 후 idle로 변경
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5초
            
            Task { @MainActor in
                syncStatus = .idle
            }
        }
        
        isSyncing = false
    }
    
    // MARK: - ShapeStoreProtocol 구현
    
    func loadShapes() async throws -> [ShapeModel] {
        return try await performSafeOperation {
            try await self.store.loadShapes()
        }
    }
    
    func saveShapes(_ shapes: [ShapeModel]) async throws {
        try await performSafeOperation {
            try await self.store.saveShapes(shapes)
        }
    }
    
    func addShape(_ shape: ShapeModel) async throws {
        try await performSafeOperation {
            // 항상 로컬에 먼저 추가 (즉시 UI 반영)
            var newShape = shape
            newShape.updatedAt = Date()
            await MainActor.run {
                ShapeFileStore.shared.addShape(newShape)

                // UI 업데이트를 위한 알림 전송 (한 번만)
                self.sendShapesDidChangeNotification()

                // 로컬 변경 사항 추적
                UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
                print("✅ 도형 추가 및 로컬 변경 추적 기록")

                // 종료일 알림 스케줄링
                SettingManager.shared.scheduleEndDateAlarm(for: newShape)
            }

            // 로그인 상태이고 클라우드 백업이 활성화된 경우 Firebase에도 반영
            if AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled {
                do {
                    try await ShapeFirebaseStore.shared.addShape(newShape)
                    print("✅ 실시간 백업 성공: 도형 추가 (\(newShape.title))")

                    // 백업 시간 업데이트
                    await MainActor.run {
                        UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                    }
                } catch {
                    print("❌ 실시간 백업 실패: 도형 추가 (\(shape.title)) - \(error.localizedDescription)")
                    // 백업 실패 시에도 로컬 데이터는 유지 (사용자 경험 보호)
                }
            } else {
                print("📝 실시간 백업 비활성화: 로그인 상태 또는 클라우드 백업 설정")
            }
        }
    }
    
    func removeShape(id: UUID) async throws {
        try await performSafeOperation {
            // 항상 로컬에서 먼저 삭제 (즉시 UI 반영)
            await MainActor.run {
                ShapeFileStore.shared.removeShape(id: id)

                // UI 업데이트를 위한 알림 전송 (한 번만)
                self.sendShapesDidChangeNotification()

                // 로컬 변경 사항 추적
                UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
                print("✅ 도형 삭제 및 로컬 변경 추적 기록")

                // 종료일 알림 삭제
                SettingManager.shared.removeEndDateAlarm(for: id)
            }

            // 로그인 상태이고 클라우드 백업이 활성화된 경우 Firebase에도 반영
            if AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled {
                do {
                    try await ShapeFirebaseStore.shared.removeShape(id: id)
                    print("✅ 실시간 백업 성공: 도형 삭제 (\(id))")

                    // 백업 시간 업데이트
                    await MainActor.run {
                        UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                    }
                } catch {
                    print("❌ 실시간 백업 실패: 도형 삭제 (\(id)) - \(error.localizedDescription)")
                    // 백업 실패 시에도 로컬 데이터는 유지 (사용자 경험 보호)
                }
            } else {
                print("📝 실시간 백업 비활성화: 로그인 상태 또는 클라우드 백업 설정")
            }
        }
    }
    
    func updateShape(_ shape: ShapeModel) async throws {
        try await performSafeOperation {
            // 항상 로컬에 먼저 업데이트 (즉시 UI 반영)
            var updatedShape = shape
            updatedShape.updatedAt = Date()
            await MainActor.run {
                ShapeFileStore.shared.updateShape(updatedShape)

                // UI 업데이트를 위한 알림 전송 (한 번만)
                self.sendShapesDidChangeNotification()

                // 로컬 변경 사항 추적
                UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
                print("✅ 도형 수정 및 로컬 변경 추적 기록")

                // 종료일 알림 재설정 (기존 알림 삭제 후 새로 생성)
                SettingManager.shared.removeEndDateAlarm(for: updatedShape.id)
                SettingManager.shared.scheduleEndDateAlarm(for: updatedShape)
            }

            // 로그인 상태이고 클라우드 백업이 활성화된 경우 Firebase에도 반영
            if AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled {
                do {
                    try await ShapeFirebaseStore.shared.updateShape(updatedShape)
                    print("✅ 실시간 백업 성공: 도형 수정 (\(updatedShape.title))")

                    // 백업 시간 업데이트
                    await MainActor.run {
                        UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                    }
                } catch {
                    print("❌ 실시간 백업 실패: 도형 수정 (\(updatedShape.title)) - \(error.localizedDescription)")
                    // 백업 실패 시에도 로컬 데이터는 유지 (사용자 경험 보호)
                }
            } else {
                print("📝 실시간 백업 비활성화: 로그인 상태 또는 클라우드 백업 설정")
            }
        }
    }
    
    func deleteExpiredShapes() async throws {
        try await performSafeOperation {
            // 로컬에서 먼저 만료된 도형 삭제 (soft delete)
            await MainActor.run {
                ShapeFileStore.shared.deleteExpiredShapes()

                // UI 업데이트를 위한 알림 전송 (한 번만)
                self.sendShapesDidChangeNotification()
            }
            
            // 로그인 상태이고 클라우드 백업이 활성화된 경우 Firebase에도 반영
            if AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled {
                do {
                    try await ShapeFirebaseStore.shared.deleteExpiredShapes()
                    print("✅ 실시간 백업 성공: 만료된 도형 삭제")
                    
                    // 백업 시간 업데이트
                    await MainActor.run {
                        UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                    }
                } catch {
                    print("❌ 실시간 백업 실패: 만료된 도형 삭제 - \(error.localizedDescription)")
                }
            } else {
                print("📝 실시간 백업 비활성화: 로그인 상태 또는 클라우드 백업 설정")
            }
        }
    }
    
    func clearAllData() async throws {
        try await performSafeOperation {
            // 로컬에서 먼저 모든 데이터 삭제
            await MainActor.run {
                ShapeFileStore.shared.clearAllData()

                // UI 업데이트를 위한 알림 전송 (한 번만)
                self.sendShapesDidChangeNotification()
            }

            // 로그인 상태이고 클라우드 백업이 활성화된 경우 Firebase에도 반영
            if AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled {
                do {
                    try await ShapeFirebaseStore.shared.saveShapes([])
                    print("✅ 실시간 백업 성공: 모든 데이터 삭제")

                    // 백업 시간 업데이트
                    await MainActor.run {
                        UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                    }
                } catch {
                    print("❌ 실시간 백업 실패: 모든 데이터 삭제 - \(error.localizedDescription)")
                }
            } else {
                print("📝 실시간 백업 비활성화: 로그인 상태 또는 클라우드 백업 설정")
            }
        }
    }

    // MARK: - Force Load Methods

    /// Firebase에서 도형 데이터를 강제로 로드하여 로컬에 저장
    /// 로그인 직후 도형이 로드되지 않는 문제 해결을 위해 사용
    func forceLoadFromFirebase() async {
        print("🔄 Firebase에서 도형 강제 로드 시작...")

        // 로그인 상태 및 클라우드 백업 확인
        guard AppleLoginManager.shared.isLogin,
              SettingManager.shared.isCloudBackupEnabled else {
            print("⚠️ 강제 로드 조건 미충족: 로그인 또는 클라우드 백업 비활성화")
            return
        }

        // 인증 사용자 확인
        _ = await AuthManager.shared.ensureAuthUserAvailableSafe()

        guard Auth.auth().currentUser != nil else {
            print("⚠️ 강제 로드 실패: 인증된 사용자 없음")
            return
        }

        do {
            // Firebase에서 도형 로드
            let firebaseShapes = try await ShapeFirebaseStore.shared.loadShapes()

            if firebaseShapes.isEmpty {
                print("📝 Firebase에 도형 데이터 없음")
                return
            }

            // 로컬에 저장: 현재 활성 도형 + Firebase 도형을 합쳐 한 번에 설정한다.
            // ShapeFileStore.shapes의 didSet이 id-unique(LWW)를 보장하므로, 로컬에 이미 있는
            // 도형을 다시 받아도 중복이 누적되지 않는다(기존 addShape 루프의 중복 버그 제거).
            await MainActor.run {
                ShapeFileStore.shared.shapes = ShapeFileStore.shared.shapes + firebaseShapes
                ShapeFileStore.shared.saveShapes()

                // UI 업데이트 알림
                self.sendShapesDidChangeNotification()

                // 지도 오버레이 리로드 알림
                NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
            }

            print("✅ Firebase에서 \(firebaseShapes.count)개 도형 강제 로드 완료")

        } catch {
            print("❌ Firebase 강제 로드 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Safe Operation Handler
    
    /// 동기화 중이 아닐 때만 작업 수행
    private func performSafeOperation<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        // 동기화 중이면 잠시 대기
        while isSyncing {
            print("⚠️ 동기화 진행 중... 작업 대기")
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1초 대기
        }
        
        // 동기화 상태 설정
        await MainActor.run {
            isSyncing = true
        }
        
        defer {
            Task { @MainActor in
                isSyncing = false
            }
        }
        
        return try await operation()
    }
    
    // MARK: - Data Integrity Methods
    
    /// 강제 데이터 무결성 검증 (외부에서 호출 가능)
    func verifyDataIntegrity() async -> DataIntegrityResult {
        do {
            let shapes = try await loadShapes()
            
            // 1. 기본 검증
            guard !shapes.isEmpty else {
                return .valid(message: "데이터 없음 (정상)")
            }
            
            // 2. 중복 ID 검증
            let uniqueIds = Set(shapes.map { $0.id })
            if uniqueIds.count != shapes.count {
                return .invalid(reason: "중복된 ID가 발견되었습니다.")
            }
            
            // 3. 필수 필드 검증
            for (index, shape) in shapes.enumerated() {
                if shape.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .invalid(reason: "\(index + 1)번째 도형의 제목이 비어있습니다.")
                }
                
                if !isValidCoordinate(shape.baseCoordinate) {
                    return .invalid(reason: "\(index + 1)번째 도형의 좌표가 유효하지 않습니다.")
                }
            }
            
            return .valid(message: "\(shapes.count)개 도형 데이터 검증 완료")
            
        } catch {
            return .invalid(reason: "데이터 검증 중 오류 발생: \(error.localizedDescription)")
        }
    }
    
    /// 긴급 복구 모드 (모든 백업에서 데이터 복구 시도)
    func emergencyRestore() async -> Bool {
        print("🚨 긴급 복구 모드 시작...")
        
        do {
            // 1. 로컬 백업에서 복구 시도
            if let restoredShapes = await restoreFromLocalBackup() {
                print("✅ 로컬 백업에서 복구 성공: \(restoredShapes.count)개")
                return true
            }
            
            // 2. Firebase에서 복구 시도 (로그인 상태인 경우)
            if AppleLoginManager.shared.isLogin {
                if let firebaseShapes = await restoreFromFirebase() {
                    print("✅ Firebase에서 복구 성공: \(firebaseShapes.count)개")
                    return true
                }
            }
            
            print("❌ 모든 복구 시도 실패")
            return false
            
        } catch {
            print("❌ 긴급 복구 중 오류: \(error)")
            return false
        }
    }
    
    /// 로컬 백업에서 복구
    private func restoreFromLocalBackup() async -> [ShapeModel]? {
        do {
            // ShapeFileStore의 백업 파일에서 복구
            let backupURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("shapes_backup.json")
            
            if FileManager.default.fileExists(atPath: backupURL.path) {
                let data = try Data(contentsOf: backupURL)
                let shapes = try JSONDecoder().decode([ShapeModel].self, from: data)
                
                // 검증 후 메인 파일로 복구
                if validateShapes(shapes) {
                    try await ShapeFileStore.shared.saveShapes(shapes)
                    return shapes
                }
            }
            return nil
        } catch {
            print("❌ 로컬 백업 복구 실패: \(error)")
            return nil
        }
    }
    
    /// Firebase에서 복구
    private func restoreFromFirebase() async -> [ShapeModel]? {
        do {
            let firebaseShapes = try await ShapeFirebaseStore.shared.loadShapes()
            
            if !firebaseShapes.isEmpty {
                // 로컬에 복구
                for shape in firebaseShapes {
                    try await ShapeFileStore.shared.addShape(shape)
                }
                return firebaseShapes
            }
            return nil
        } catch {
            print("❌ Firebase 복구 실패: \(error)")
            return nil
        }
    }
    
    /// 도형 데이터 유효성 검증
    private func validateShapes(_ shapes: [ShapeModel]) -> Bool {
        guard !shapes.isEmpty else { return true }
        
        // 중복 ID 검증
        let uniqueIds = Set(shapes.map { $0.id })
        if uniqueIds.count != shapes.count { return false }
        
        // 각 도형 검증
        return shapes.allSatisfy { shape in
            !shape.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            isValidCoordinate(shape.baseCoordinate)
        }
    }
    
    /// 좌표 유효성 검증
    private func isValidCoordinate(_ coordinate: CoordinateManager) -> Bool {
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 &&
               !lat.isNaN && !lng.isNaN && lat.isFinite && lng.isFinite
    }
}

// MARK: - Sync Status & Operations
enum SyncStatus: Equatable {
    case idle
    case syncing(SyncOperation)
    case completed(SyncOperation)
    case failed(SyncOperation, Error)
    
    static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.syncing(let lhsOp), .syncing(let rhsOp)):
            return lhsOp == rhsOp
        case (.completed(let lhsOp), .completed(let rhsOp)):
            return lhsOp == rhsOp
        case (.failed(let lhsOp, _), .failed(let rhsOp, _)):
            return lhsOp == rhsOp
        default:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .idle:
            return "대기 중"
        case .syncing(let operation):
            return "\(operation.description) 동기화 중..."
        case .completed(let operation):
            return "\(operation.description) 동기화 완료"
        case .failed(let operation, let error):
            return "\(operation.description) 동기화 실패: \(error.localizedDescription)"
        }
    }
}

enum SyncOperation: Equatable {
    case localToFirebase
    case firebaseToLocal
    
    var description: String {
        switch self {
        case .localToFirebase:
            return "클라우드 업로드"
        case .firebaseToLocal:
            return "클라우드 다운로드"
        }
    }
}

enum SyncError: LocalizedError {
    case verificationFailed
    case backupFailed
    case concurrentAccess
    
    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "동기화 후 데이터 검증에 실패했습니다."
        case .backupFailed:
            return "백업 생성에 실패했습니다."
        case .concurrentAccess:
            return "동시 접근으로 인한 충돌이 발생했습니다."
        }
    }
}

// MARK: - Data Integrity Result
enum DataIntegrityResult {
    case valid(message: String)
    case invalid(reason: String)
    
    var isValid: Bool {
        switch self {
        case .valid:
            return true
        case .invalid:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .valid(let message):
            return "✅ \(message)"
        case .invalid(let reason):
            return "❌ \(reason)"
        }
    }
} 


