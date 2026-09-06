//
//  PushNotificationManager.swift
//  DronePass
//
//  Created by 문주성 on 11/13/25.
//

import Foundation
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// 푸시 알림 데이터 모델
struct PushNotificationData: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

@Observable
class PushNotificationManager: NSObject {

    static let shared = PushNotificationManager()

    var fcmToken: String?
    var isRegistered: Bool = false

    /// 사용자가 탭한 푸시 알림 데이터 (팝업 표시용)
    var receivedPushNotification: PushNotificationData?

    private override init() {
        super.init()
    }

    // MARK: - FCM 토큰 요청

    /// FCM 토큰 요청 및 Firestore 저장
    func requestFCMToken() {
        Messaging.messaging().token { [weak self] token, error in
            if let error = error {
                print("❌ FCM 토큰 요청 실패: \(error.localizedDescription)")
                return
            }

            guard let token = token else {
                print("❌ FCM 토큰이 nil입니다.")
                return
            }

            print("✅ FCM 토큰 수신: \(token)")
            self?.fcmToken = token

            // Firestore에 저장
            Task {
                await self?.saveFCMTokenToFirestore(token: token)
            }
        }
    }

    // MARK: - Firestore에 FCM 토큰 저장

    /// Firestore에 디바이스 토큰 저장
    private func saveFCMTokenToFirestore(token: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ 로그인되지 않아 FCM 토큰을 저장할 수 없습니다.")
            return
        }

        // 디바이스 ID 생성 (기기별 고유 ID)
        let deviceId = getDeviceIdentifier()
        let appVersion = getAppVersion()

        let db = Firestore.firestore()
        let deviceRef = db.collection("users").document(userId).collection("devices").document(deviceId)

        let deviceData: [String: Any] = [
            "fcmToken": token,
            "platform": "ios",
            "appVersion": appVersion,
            "isActive": true,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        do {
            try await deviceRef.setData(deviceData, merge: true)
            print("✅ FCM 토큰 Firestore 저장 완료")
            print("   - User ID: \(userId)")
            print("   - Device ID: \(deviceId)")
            print("   - App Version: \(appVersion)")
            isRegistered = true
        } catch {
            print("❌ FCM 토큰 Firestore 저장 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - FCM 토큰 비활성화

    /// 로그아웃 시 FCM 토큰 비활성화
    func deactivateFCMToken() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ 로그인되지 않아 FCM 토큰을 비활성화할 수 없습니다.")
            return
        }

        let deviceId = getDeviceIdentifier()
        let db = Firestore.firestore()
        let deviceRef = db.collection("users").document(userId).collection("devices").document(deviceId)

        do {
            try await deviceRef.updateData([
                "isActive": false,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            print("✅ FCM 토큰 비활성화 완료")
            isRegistered = false
        } catch {
            print("❌ FCM 토큰 비활성화 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 디바이스 정보

    /// 디바이스 고유 ID 생성 (UUID 기반)
    private func getDeviceIdentifier() -> String {
        let key = "DeviceUUID"

        // UserDefaults에서 기존 UUID 확인
        if let existingUUID = UserDefaults.standard.string(forKey: key) {
            return existingUUID
        }

        // 새 UUID 생성 및 저장
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: key)
        return newUUID
    }

    /// 앱 버전 정보 가져오기
    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    // MARK: - 푸시 알림 권한 요청

    /// 푸시 알림 권한 요청
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ 푸시 알림 권한 요청 실패: \(error.localizedDescription)")
                return
            }

            if granted {
                print("✅ 푸시 알림 권한 허용됨")

                // 메인 스레드에서 APNs 등록
                DispatchQueue.main.async {
                    #if canImport(UIKit)
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
            } else {
                print("❌ 푸시 알림 권한 거부됨")
            }
        }
    }
}

// MARK: - MessagingDelegate

extension PushNotificationManager: MessagingDelegate {

    /// FCM 토큰 갱신 시 호출
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM 토큰 갱신: \(fcmToken ?? "nil")")

        guard let fcmToken = fcmToken else { return }

        self.fcmToken = fcmToken

        // Firestore에 업데이트
        Task {
            await saveFCMTokenToFirestore(token: fcmToken)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    /// 포그라운드에서 푸시 수신 시 호출
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content

        print("📬 포그라운드 푸시 수신:")
        print(content.userInfo)

        // 포그라운드에서도 팝업 표시
        DispatchQueue.main.async { [weak self] in
            self?.receivedPushNotification = PushNotificationData(
                title: content.title,
                body: content.body
            )
        }

        // 포그라운드에서도 시스템 알림 표시
        completionHandler([.banner, .sound, .badge])
    }

    /// 푸시 알림 탭 시 호출
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let userInfo = content.userInfo

        print("📬 푸시 알림 탭:")
        print(userInfo)

        // 푸시 알림 데이터 저장 (팝업 표시용)
        let title = content.title
        let body = content.body

        // 메인 스레드에서 UI 업데이트
        DispatchQueue.main.async { [weak self] in
            self?.receivedPushNotification = PushNotificationData(title: title, body: body)
        }

        completionHandler()
    }
}
