//
//  ProfileView.swift
//  DronePass
//
//  Created by 문주성 on 7/22/25.
//

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutAlert = false
    @State private var isLoggingOut = false
    @State private var showTerms: Bool = false
    @State private var showPrivacy: Bool = false
    @StateObject private var settingManager = SettingManager.shared
    @ObservedObject private var realtimeSyncManager = RealtimeSyncManager.shared
    @ObservedObject private var shapeStore = ShapeFileStore.shared
    @ObservedObject private var sketchStore = SketchFileStore.shared
    @ObservedObject private var droneManager = DroneManager.shared

    // 동기화 상태 관련 State 변수들
    @State private var isSyncing = false
    @State private var showSyncResult = false
    @State private var syncResultMessage = ""
    @State private var syncResultIsSuccess = false

    // 회원 탈퇴 관련 State 변수들
    @State private var showDeleteAccountAlert = false
    @State private var showFinalConfirmAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showDeleteAccountErrorAlert = false

    /// 가입일 표시용 포매터 (날짜만, 로케일 자동)
    private static let joinDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    // MARK: - 내 정보 표시용 값
    private var emailText: String {
        AuthManager.shared.currentUser?.email ?? NSLocalizedString("profile.info.emailHidden", comment: "Email hidden")
    }
    private var providerText: String {
        let ids = Auth.auth().currentUser?.providerData.map { $0.providerID } ?? []
        if ids.contains("apple.com") { return "Apple" }
        if ids.contains("google.com") { return "Google" }
        return "—"
    }
    private var joinText: String {
        guard let createdAt = AuthManager.shared.currentUser?.createdAt else {
            return NSLocalizedString("profile.info.joinUnknown", comment: "join date unknown")
        }
        return Self.joinDateFormatter.string(from: createdAt)
    }
    private var statsText: String {
        String(format: NSLocalizedString("profile.info.stats", comment: "shape/sketch/drone counts"),
               shapeStore.shapes.count, sketchStore.activeSketchCount, droneManager.activeDrones.count)
    }
    private var expiredShapeCount: Int {
        shapeStore.shapes.filter { $0.isExpired }.count
    }
    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    var body: some View {
        List {
            // 내 정보 섹션 (컴팩트 커스텀 카드)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(NSLocalizedString("profile.info.email", comment: "Email"), emailText)
                    infoRow(NSLocalizedString("profile.info.loginMethod", comment: "Login method"), providerText)
                    infoRow(NSLocalizedString("profile.info.joinDate", comment: "Joined"), joinText)
                    Divider()
                        .padding(.vertical, 2)
                    infoRow(NSLocalizedString("profile.info.shapes", comment: "Shapes"),
                            String(format: NSLocalizedString("profile.info.countUnit", comment: "count unit"), shapeStore.shapes.count))
                    infoRow(NSLocalizedString("profile.info.sketches", comment: "Sketches"),
                            String(format: NSLocalizedString("profile.info.countUnit", comment: "cou  nt unit"), sketchStore.activeSketchCount))
                    infoRow(NSLocalizedString("profile.info.drones", comment: "Drones"),
                            String(format: NSLocalizedString("profile.info.countUnit", comment: "count unit"), droneManager.activeDrones.count))
                    infoRow(NSLocalizedString("profile.info.expiredShapes", comment: "Expired shapes"),
                            String(format: NSLocalizedString("profile.info.countUnit", comment: "count unit"), expiredShapeCount))
                }
                .padding(.vertical, 12)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            } header: {
                Text(NSLocalizedString("profile.section.myInfo", comment: "My Info"))
            }
            .listSectionSpacing(10)

            // 로그아웃 (내 정보 카드 아래 별도 행)
            Section {
                Button(role: .destructive) {
                    showLogoutAlert = true
                } label: {
                    Text(NSLocalizedString("profile.account.logout", comment: "Sign Out"))
                }
                .disabled(isLoggingOut)
            }

            // 실시간 클라우드 동기화 섹션
            Section {
                // 실시간 클라우드 동기화 활성화 토글
                Toggle(isOn: $settingManager.isCloudBackupEnabled) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("profile.sync.cloud", comment: "Real-time cloud sync"))
                                .font(.headline)
                            Text(realtimeCloudSyncStatusText)
                                .font(.caption)
                                .foregroundColor(realtimeCloudSyncStatusColor)
                        }
                        if isSyncing || realtimeSyncManager.syncInProgress {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isSyncing || realtimeSyncManager.syncInProgress)
                .onChange(of: settingManager.isCloudBackupEnabled) { oldValue, newValue in
                    if newValue && AppleLoginManager.shared.isLogin {
                        // 실시간 클라우드 동기화 활성화 시 즉시 백업 및 동기화
                        Task {
                            // 인증 준비 보장 후 업로드 수행
                            _ = await AuthManager.shared.ensureAuthUserAvailableSafe()
                            await syncToCloud()
                        }
                        
                        // 실시간 동기화 상태 강제 리셋 및 재시작
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            RealtimeSyncManager.shared.resetAndRestartRealtimeSync()
                        }
                    }
                }
                
                // 마지막 동기화/백업 시간 표시
                Text(lastSyncTimeText)
                    .font(.caption)
                    .foregroundStyle(.gray)
                
                // 수동 백업 버튼 (실시간 클라우드 동기화가 활성화된 경우에만)
                if settingManager.isCloudBackupEnabled && AppleLoginManager.shared.isLogin {
                    Button {
                        Task {
                            await syncToCloud()
                        }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("profile.backup.manual", comment: "Manual backup"))
                            if isSyncing || realtimeSyncManager.syncInProgress {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isSyncing || realtimeSyncManager.syncInProgress)
                }
                
                // 백업 복구 버튼 (데이터 손실 시 사용)
                // Button {
                //     Task {
                //         await restoreFromBackup()
                //     }
                // } label: {
                //     HStack {
                //         Text("백업에서 복구")
                //             .foregroundColor(.orange)
                //         if isSyncing {
                //             Spacer()
                //             ProgressView()
                //                 .scaleEffect(0.8)
                //         }
                //     }
                // }
                // .disabled(isSyncing)
                
            } header: {
                Text(NSLocalizedString("profile.section.sync", comment: "Synchronization"))
            } footer: {
                Text(realtimeCloudSyncFooterText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section {
                Button {
                    showTerms = true
                } label: {
                    HStack {
                        Text(NSLocalizedString("profile.terms.service", comment: "Terms of Service"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                Button {
                    showPrivacy = true
                } label: {
                    HStack {
                        Text(NSLocalizedString("profile.terms.privacy", comment: "Privacy Policy"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
            } header: {
                Text(NSLocalizedString("profile.section.terms", comment: "Terms & Policies"))
            }

            // 계정 관리 섹션 (회원 탈퇴만)
            Section {
                Button(role: .destructive) {
                    showDeleteAccountAlert = true
                } label: {
                    Text(NSLocalizedString("profile.account.delete", comment: "Delete Account"))
                }
                .disabled(isDeletingAccount || isLoggingOut)
            } header: {
                Text(NSLocalizedString("profile.section.account", comment: "Account Management"))
            } footer: {
                Text(NSLocalizedString("profile.account.delete.desc", comment: "Only the account will be deleted. Local data will remain available."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("profile.title", comment: "My Profile"))
        .sheet(isPresented: $showTerms) {
            NavigationView {
                TermsOfServiceView()
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationView {
                PrivacyPolicyView()
            }
        }
        .alert(NSLocalizedString("profile.logout.title", comment: "Sign Out"), isPresented: $showLogoutAlert) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("profile.logout.button", comment: "Sign Out"), role: .destructive) {
                logout()
            }
        } message: {
            Text(NSLocalizedString("profile.logout.message", comment: "Are you sure you want to sign out?"))
        }
        .alert(NSLocalizedString("profile.sync.alert.title", comment: "Real-time Cloud Sync"), isPresented: $showSyncResult) {
            Button(NSLocalizedString("common.confirm", comment: "OK"), role: .cancel) { }
        } message: {
            Text(syncResultMessage)
        }
        .alert(NSLocalizedString("profile.deleteAccount.title", comment: "Delete Account"), isPresented: $showDeleteAccountAlert) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("profile.deleteAccount.button", comment: "Delete"), role: .destructive) {
                showFinalConfirmAlert = true
            }
        } message: {
            Text(NSLocalizedString("profile.deleteAccount.message", comment: "Your account will be deleted and cloud sync will stop.\n\nShapes and drones saved on this device will remain available.\n\nAre you sure you want to delete your account?"))
        }
        .alert(NSLocalizedString("profile.deleteAccount.finalConfirm.title", comment: "Final Confirmation"), isPresented: $showFinalConfirmAlert) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("profile.deleteAccount.finalConfirm.button", comment: "Permanently Delete"), role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text(NSLocalizedString("profile.deleteAccount.finalConfirm.message", comment: "This action cannot be undone."))
        }
        .alert(NSLocalizedString("profile.deleteAccount.error.title", comment: "Deletion Failed"), isPresented: $showDeleteAccountErrorAlert) {
            Button(NSLocalizedString("common.confirm", comment: "OK"), role: .cancel) { }
        } message: {
            Text(deleteAccountError ?? NSLocalizedString("common.error.unknown", comment: "An unknown error occurred."))
        }
    }
    
    // MARK: - Computed Properties
    
    // 실시간 클라우드 동기화 관련 computed properties
    private var realtimeCloudSyncStatusText: String {
        if isSyncing || realtimeSyncManager.syncInProgress {
            return NSLocalizedString("profile.sync.inProgress", comment: "Syncing...")
        } else if !AppleLoginManager.shared.isLogin {
            return NSLocalizedString("profile.sync.loginRequired", comment: "Login required")
        } else if !settingManager.isCloudBackupEnabled {
            return NSLocalizedString("profile.sync.disabled", comment: "Disabled")
        } else if realtimeSyncManager.isRealtimeSyncEnabled {
            return NSLocalizedString("profile.sync.active", comment: "Active - Real-time syncing")
        } else {
            return NSLocalizedString("profile.sync.waiting", comment: "Active - Waiting for sync")
        }
    }
    
    private var realtimeCloudSyncStatusColor: Color {
        if isSyncing || realtimeSyncManager.syncInProgress {
            return .blue
        } else if !AppleLoginManager.shared.isLogin {
            return .orange
        } else if !settingManager.isCloudBackupEnabled {
            return .gray
        } else if realtimeSyncManager.isRealtimeSyncEnabled {
            return .green
        } else {
            return .orange // 활성화되어 있지만 대기 중인 상태
        }
    }
    
    private var lastSyncTimeText: String {
        if let realtimeSync = realtimeSyncManager.lastSyncTime {
            return String(format: NSLocalizedString("profile.sync.lastSync", comment: "Last sync: %@"), DateFormatter.localizedDateTime.string(from: realtimeSync))
        } else if let lastBackupTime = UserDefaults.standard.object(forKey: "lastBackupTime") as? Date {
            return String(format: NSLocalizedString("profile.backup.lastBackup", comment: "Last backup: %@"), DateFormatter.localizedDateTime.string(from: lastBackupTime))
        } else {
            return NSLocalizedString("profile.sync.noHistory", comment: "No sync history")
        }
    }
    
    private var realtimeCloudSyncFooterText: String {
        if !AppleLoginManager.shared.isLogin {
            return NSLocalizedString("profile.sync.footer.loginRequired", comment: "Please log in to use real-time cloud sync.")
        } else if !settingManager.isCloudBackupEnabled {
            return NSLocalizedString("profile.sync.footer.enableInfo", comment: "When enabled, shape data will be synced and backed up in real-time across all devices with the same account.")
        } else {
            return ""
        }
    }
    
    // MARK: - Methods
    
    private func syncToCloud() async {
        await MainActor.run {
            isSyncing = true
        }
        
        do {
            // 로그인 직후 경합 방지를 위해 인증 준비를 한 번 더 보장
            _ = try await AuthManager.shared.ensureAuthUserAvailable()
            // 로컬에서 활성 도형만 로드 (삭제된 도형 제외)
            let activeLocalShapes = await MainActor.run {
                return ShapeFileStore.shared.shapes
            }
            
            print("📤 로컬에서 백업할 활성 도형: \(activeLocalShapes.count)개")
            
            // Firebase에 활성 도형만 저장
            try await ShapeFirebaseStore.shared.saveShapes(activeLocalShapes)

            // 저장 직후 서버 상태를 다시 받아 로컬 정합성 확보 (삭제 전파 포함)
            await RealtimeSyncManager.shared.forceSyncNow()
            
            // 동기화/백업 시간 저장
            await MainActor.run {
                UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                isSyncing = false
                syncResultMessage = String(format: NSLocalizedString("profile.sync.success", comment: "Sync completed for %d shapes."), activeLocalShapes.count)
                syncResultIsSuccess = true
                showSyncResult = true
            }

            print("✅ 실시간 클라우드 동기화 완료: \(activeLocalShapes.count)개 활성 도형")

        } catch {
            await MainActor.run {
                isSyncing = false
                syncResultMessage = String(format: NSLocalizedString("profile.sync.failed", comment: "Sync failed: %@"), error.localizedDescription)
                syncResultIsSuccess = false
                showSyncResult = true
            }
            
            print("❌ 실시간 클라우드 동기화 실패: \(error)")
        }
    }
    
    private func restoreFromBackup() async {
        await MainActor.run {
            isSyncing = true
        }
        
        do {
            // Firebase에서 모든 도형을 가져와서 로컬에 저장
            let shapesFromFirebase = try await ShapeFirebaseStore.shared.loadShapes()
            
            print("📥 백업에서 복구할 도형: \(shapesFromFirebase.count)개")
            
            await MainActor.run {
                ShapeFileStore.shared.shapes = shapesFromFirebase
                UserDefaults.standard.set(Date(), forKey: "lastBackupTime") // 복구 시간 업데이트
                isSyncing = false
                syncResultMessage = String(format: NSLocalizedString("profile.restore.success", comment: "Restored %d shapes."), shapesFromFirebase.count)
                syncResultIsSuccess = true
                showSyncResult = true
            }

            print("✅ 백업에서 복구 완료: \(shapesFromFirebase.count)개 도형")

        } catch {
            await MainActor.run {
                isSyncing = false
                syncResultMessage = String(format: NSLocalizedString("profile.restore.failed", comment: "Restore failed: %@"), error.localizedDescription)
                syncResultIsSuccess = false
                showSyncResult = true
            }
            
            print("❌ 백업에서 복구 실패: \(error)")
        }
    }
    
    private func logout() {
        isLoggingOut = true

        Task {
            // 로그아웃 전 로컬 데이터를 Firebase에 동기화
            if AppleLoginManager.shared.isLogin {
                do {
                    // 로컬에서 활성 도형만 가져와서 Firebase에 백업
                    let activeLocalShapes = await MainActor.run {
                        return ShapeFileStore.shared.shapes
                    }

                    print("📤 로그아웃 전 동기화할 활성 로컬 도형: \(activeLocalShapes.count)개")

                    // 활성 도형만 Firebase에 저장
                    if !activeLocalShapes.isEmpty {
                        try await ShapeFirebaseStore.shared.saveShapes(activeLocalShapes)
                        print("✅ 로그아웃 전 실시간 클라우드 동기화 완료: \(activeLocalShapes.count)개 활성 도형")
                    }
                } catch {
                    print("❌ 로그아웃 전 실시간 클라우드 동기화 실패: \(error)")
                }
            }

            // AuthManager를 통해 로그아웃
            await MainActor.run {
                // 맵 오버레이 정리
                NotificationCenter.default.post(name: Notification.Name("ClearMapOverlays"), object: nil)

                AuthManager.shared.signout()
                AppleLoginManager.shared.isLogin = false
                isLoggingOut = false
                dismiss()
            }
        }
    }

    private func deleteAccount() async {
        await MainActor.run {
            isDeletingAccount = true
        }

        do {
            try await AuthManager.shared.deleteAccount()

            // 성공: 로그인 화면으로 이동
            await MainActor.run {
                isDeletingAccount = false
                dismiss()
            }

            print("✅ 회원 탈퇴 완료")

        } catch {
            // 실패: 에러 메시지 표시
            await MainActor.run {
                isDeletingAccount = false
                deleteAccountError = error.localizedDescription
                showDeleteAccountErrorAlert = true
            }

            print("❌ 회원 탈퇴 실패: \(error)")
        }
    }
}

#Preview {
    ProfileView()
}
