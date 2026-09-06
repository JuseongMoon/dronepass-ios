//
//  ChangeDetectionManager.swift
//  DronePass
//
//  Created by 문주성 on 7/27/25.
//

import Foundation
import UIKit

/**
 # ChangeDetectionManager

 다중 기기 환경에서 변경사항을 감지하고 동기화를 관리하는 매니저입니다.

 ## 주요 기능
 - 서버 변경사항 감지
 - 사용자 알림 및 동기화 실행
 - 중복 체크 방지
 - 네트워크 상태 고려
 */
@MainActor
final class ChangeDetectionManager {
    
    // MARK: - Singleton
    
    static let shared = ChangeDetectionManager()
    private init() {}
    
    // MARK: - Properties
    
    /// 앱 세션 중 변경사항 체크 여부
    private var hasCheckedForChanges = false
    
    /// 마지막 체크 시간 (중복 체크 방지)
    private var lastCheckTime: Date?
    
    /// 동기화 진행 중 여부
    private var isSyncing = false
    
    // MARK: - Public Methods
    
    /**
     앱 실행 시 변경사항을 확인하고 필요한 경우 사용자에게 알림합니다.
     
     앱이 포그라운드로 올 때마다 호출하는 것을 권장합니다.
     중복 체크를 방지합니다.
     */
    func checkForChangesIfNeeded() {
        // 이미 체크했거나 동기화 중이면 건너뛰기
        guard !hasCheckedForChanges && !isSyncing else {
            return
        }
        
        // 짧은 시간 내 중복 체크 방지 (30초)
        if let lastCheck = lastCheckTime,
           Date().timeIntervalSince(lastCheck) < 30 {
            return
        }
        
        lastCheckTime = Date()
        
        Task {
            await checkForChanges()
        }
    }
    
    /**
     강제로 변경사항을 확인합니다.
     
     사용자가 수동으로 동기화를 요청할 때 사용합니다.
     */
    func forceCheckForChanges() {
        Task {
            await checkForChanges()
        }
    }
    
    // MARK: - Private Methods
    
    /**
     실제 변경사항 확인 및 처리
     */
    private func checkForChanges() async {
        // 로그인 상태가 아니거나 클라우드 백업이 비활성화된 경우 건너뛰기
        guard AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled else {
            print("📝 변경사항 체크 건너뜀: 로그인 상태 또는 클라우드 백업 비활성화")
            return
        }
        
        do {
            let hasChanges = try await ShapeFirebaseStore.shared.hasChanges()
            
            if hasChanges {
                print("🔄 변경사항 감지됨")
                await MainActor.run {
                    showChangeDetectionAlert()
                }
            } else {
                print("📝 변경사항 없음")
            }
            
            // 체크 완료 표시
            await MainActor.run {
                hasCheckedForChanges = true
            }
            
        } catch {
            print("❌ 변경사항 확인 실패: \(error)")
        }
    }
    
    /**
     변경사항 감지 알림 표시
     */
    private func showChangeDetectionAlert() {
        guard let topViewController = getTopViewController() else {
            print("❌ 최상위 뷰 컨트롤러를 찾을 수 없음")
            return
        }
        
        let alert = UIAlertController(
            title: String(localized: "sync.alert.detected.title"),
            message: String(localized: "sync.alert.detected.message"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: String(localized: "common.confirm"), style: .default) { _ in
            Task {
                await self.performSync()
            }
        })

        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        
        topViewController.present(alert, animated: true)
    }
    
    /**
     동기화 실행
     */
    private func performSync() async {
        guard !isSyncing else { return }
        
        await MainActor.run {
            isSyncing = true
        }
        
        do {
            // 로딩 표시
            await showLoadingIndicator()
            
            // Firebase에서 최신 데이터 가져오기
            let latestShapes = try await ShapeFirebaseStore.shared.loadShapes()
            
            // 로컬 데이터 업데이트
            await MainActor.run {
                // 서버 값으로 동기화하되 LWW(서버 updatedAt 기준) 반영
                ShapeFileStore.shared.shapes = latestShapes
                ShapeFileStore.shared.saveShapes()
                
                // 마지막 동기화 시간 업데이트
                UserDefaults.standard.set(Date(), forKey: "lastSyncTime")
                
                hideLoadingIndicator()
                showSyncCompleteMessage()
            }
            
            print("✅ 동기화 완료: \(latestShapes.count)개 도형")
            
        } catch {
            await MainActor.run {
                hideLoadingIndicator()
                showErrorAlert(error: error)
            }
            print("❌ 동기화 실패: \(error)")
        }
        
        await MainActor.run {
            isSyncing = false
        }
    }
    
    /**
     로딩 인디케이터 표시
     */
    private func showLoadingIndicator() async {
        await MainActor.run {
            guard let topViewController = getTopViewController() else { return }
            
            let loadingAlert = UIAlertController(
                title: String(localized: "sync.loading.title"),
                message: String(localized: "sync.loading.message"),
                preferredStyle: .alert
            )
            
            let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
            loadingIndicator.hidesWhenStopped = true
            loadingIndicator.style = .medium
            loadingIndicator.startAnimating()
            
            loadingAlert.view.addSubview(loadingIndicator)
            topViewController.present(loadingAlert, animated: true)
        }
    }
    
    /**
     로딩 인디케이터 숨기기
     */
    private func hideLoadingIndicator() {
        guard let topViewController = getTopViewController() else { return }

        if let presentedViewController = topViewController.presentedViewController,
           presentedViewController.title == String(localized: "sync.loading.title") {
            presentedViewController.dismiss(animated: true)
        }
    }
    
    /**
     동기화 완료 메시지 표시
     */
    private func showSyncCompleteMessage() {
        guard let topViewController = getTopViewController() else { return }

        let alert = UIAlertController(
            title: String(localized: "sync.complete.title"),
            message: String(localized: "sync.complete.message"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: String(localized: "common.confirm"), style: .default))

        topViewController.present(alert, animated: true)
    }
    
    /**
     오류 알림 표시
     */
    private func showErrorAlert(error: Error) {
        guard let topViewController = getTopViewController() else { return }

        let alert = UIAlertController(
            title: String(localized: "sync.error.title"),
            message: String(format: String(localized: "sync.error.message"), error.localizedDescription),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: String(localized: "common.confirm"), style: .default))

        topViewController.present(alert, animated: true)
    }
    
    /**
     최상위 뷰 컨트롤러 가져오기
     */
    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        
        var topViewController = window.rootViewController
        
        while let presentedViewController = topViewController?.presentedViewController {
            topViewController = presentedViewController
        }
        
        return topViewController
    }
}

// MARK: - ChangeDetectionManager Extensions

extension ChangeDetectionManager {
    
    /**
     변경사항 체크 상태를 리셋합니다.
     
     앱이 백그라운드에서 포그라운드로 돌아올 때 호출하여 다시 체크할 수 있도록 합니다.
     */
    func resetCheckStatus() {
        hasCheckedForChanges = false
        lastCheckTime = nil
    }
    
    /**
     동기화 상태를 확인합니다.
     */
    var isCurrentlySyncing: Bool {
        return isSyncing
    }
} 