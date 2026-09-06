//
//  DronePassApp.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//


import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import UserNotifications

func shouldRecordUserActivity(
  lastRecordedAt: Date?,
  now: Date,
  minimumInterval: TimeInterval = 15 * 60
) -> Bool {
  guard let lastRecordedAt else { return true }
  return now.timeIntervalSince(lastRecordedAt) >= minimumInterval
}

#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
@MainActor
final class UserActivityTracker {
  static let shared = UserActivityTracker()

  private let minimumInterval: TimeInterval = 15 * 60
  private var writeInProgress = false

  private init() {}

  func recordIfNeeded(now: Date = Date()) async {
    guard !writeInProgress, let userID = Auth.auth().currentUser?.uid else { return }
    let defaultsKey = "lastActiveAtWrite.\(userID)"
    let lastRecordedAt = UserDefaults.standard.object(forKey: defaultsKey) as? Date
    guard shouldRecordUserActivity(
      lastRecordedAt: lastRecordedAt,
      now: now,
      minimumInterval: minimumInterval
    ) else { return }

    writeInProgress = true
    defer { writeInProgress = false }

    let appVersion = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "unknown"

    do {
      try await Firestore.firestore()
        .collection("users")
        .document(userID)
        .updateData([
          "lastActiveAt": FieldValue.serverTimestamp(),
          "lastActivePlatform": "ios",
          "lastActiveAppVersion": appVersion
        ])
      UserDefaults.standard.set(now, forKey: defaultsKey)
    } catch {
      print("⚠️ 사용자 활동 시각 기록 실패: \(error.localizedDescription)")
    }
  }
}
#endif


#if canImport(UIKit)
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    #if canImport(FirebaseCore)
    FirebaseApp.configure()
    #endif

    // Google Sign-In 설정 (GoogleService-Info.plist의 CLIENT_ID 사용)
    #if canImport(GoogleSignIn)
    if let clientID = FirebaseApp.app()?.options.clientID {
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }
    #endif

    // 최초 설치 시 기본 설정 등록: 일단위 입력 기본 ON
    UserDefaults.standard.register(defaults: [
      "isDateOnlyMode": true
    ])
    
    // Firestore 설정을 앱 시작 시 한 번만 수행
    #if canImport(FirebaseFirestore)
    let settings = FirestoreSettings()
    settings.cacheSettings = PersistentCacheSettings(
      sizeBytes: FirestoreCacheSizeUnlimited as NSNumber
    )
    Firestore.firestore().settings = settings
    #endif
    
    // 앱 시작 시 마이그레이션 한 번만 실행
    MigrationManager.shared.performAllMigrationsIfNeeded()
    print("✅ 앱 시작 시 마이그레이션 체크 완료")

    // 드론 매니저 사전 초기화 (기본 드론 즉시 생성) - 도형보다 먼저 로딩
    _ = DroneManager.shared
    print("✅ 드론 매니저 사전 초기화 완료 - 기본 드론 사용 가능")

    // 실시간 동기화 매니저 초기화 (로그인 상태에 따라 자동으로 시작/중지됨)
    _ = RealtimeSyncManager.shared
    print("✅ 실시간 동기화 매니저 초기화 완료")

    // 🔧 알림 초기화는 ShapeFileStore.loadShapes()에서 자동으로 처리됨 (중복 방지)
    // DispatchQueue.main.asyncAfter 제거 - loadShapes()에서 이미 scheduleEndDateAlarms() 호출

    // 푸시 알림 설정
    #if canImport(FirebaseMessaging)
    setupPushNotifications()
    #endif

    return true
  }

  // MARK: - Push Notification Setup

  /// 푸시 알림 초기 설정
  func setupPushNotifications() {
    // UNUserNotificationCenter delegate 설정
    UNUserNotificationCenter.current().delegate = PushNotificationManager.shared

    // Firebase Messaging delegate 설정
    #if canImport(FirebaseMessaging)
    Messaging.messaging().delegate = PushNotificationManager.shared
    #endif

    // 푸시 알림 권한 요청
    PushNotificationManager.shared.requestNotificationPermission()

    print("✅ 푸시 알림 설정 완료")
  }

  // MARK: - Remote Notifications

  /// APNs 토큰 등록 성공 시 호출
  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("✅ APNs 토큰 등록 성공")

    // Firebase Messaging에 APNs 토큰 전달
    #if canImport(FirebaseMessaging)
    Messaging.messaging().apnsToken = deviceToken
    #endif
  }

  /// APNs 토큰 등록 실패 시 호출
  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ APNs 토큰 등록 실패: \(error.localizedDescription)")
  }
  
  func applicationDidBecomeActive(_ application: UIApplication) {
    #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
    Task { await UserActivityTracker.shared.recordIfNeeded() }
    #endif

    // 실시간 동기화가 비활성화된 경우에만 변경사항 체크
    if !RealtimeSyncManager.shared.isRealtimeSyncEnabled {
      ChangeDetectionManager.shared.checkForChangesIfNeeded()
    } else {
      print("📝 실시간 동기화가 활성화되어 있어 수동 변경사항 체크를 건너뜁니다.")
    }
  }
  
  func applicationWillResignActive(_ application: UIApplication) {
    // 앱이 백그라운드로 갈 때 변경사항 체크 상태 리셋
    ChangeDetectionManager.shared.resetCheckStatus()
  }
}
#endif


@main
struct DronePassApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView() // MainTabView로 변경!
                .onOpenURL { url in
                    // Google Sign-In 외부 인증 콜백 처리
                    #if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // 앱이 백그라운드로 가거나 비활성화될 때 드론 상태 저장
            if newPhase == .background || newPhase == .inactive {
                DroneManager.shared.saveAllStates()
            }
        }
    }
}

