//
//  GoogleLoginManager.swift
//  DronePass
//
//  Created by Claude on 2026-06-07.
//

import Foundation
import FirebaseAuth
import GoogleSignIn
import UIKit
import Combine

// MARK: - Google Login Error

/// Google 로그인 관련 에러
public enum GoogleLoginError: LocalizedError {
    case missingPresentingViewController
    case missingIDToken
    case userCancelled
    case firebaseAuthFailed(underlying: Error)
    case unknown(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .missingPresentingViewController:
            return "로그인 화면을 표시할 수 없습니다."
        case .missingIDToken:
            return "Google 로그인 토큰을 가져올 수 없습니다."
        case .userCancelled:
            return "사용자가 로그인을 취소했습니다."
        case .firebaseAuthFailed(let error):
            return "Firebase 인증 실패: \(error.localizedDescription)"
        case .unknown(let error):
            return "알 수 없는 오류: \(error.localizedDescription)"
        }
    }
}

@MainActor
public final class GoogleLoginManager: ObservableObject {
    public static let shared = GoogleLoginManager()

    private init() {}

    // 로그인 진행 상태 및 에러
    // ⚠️ isLogin은 보유하지 않는다. Firebase Auth 상태는 provider 무관하게
    //    AppleLoginManager.init()의 addStateDidChangeListener가 단일 진실원으로 관리하므로,
    //    Google 로그인이 Auth.auth().signIn(with:)만 호출하면 기존 로그인 상태 파이프라인이 그대로 동작한다.
    @Published public var loginError: Error? = nil
    @Published public var isLoggingIn: Bool = false

    // MARK: - Presenting View Controller

    /// 현재 foreground scene의 최상단 view controller 획득 (iOS 15+ 모던 API)
    /// 로그인 시트(LoginView) 위에서 호출되므로 presented VC까지 추적해야 한다.
    private func currentRootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Google 로그인

    /// Google Sign-In → Firebase 인증 처리
    public func loginWithGoogle() async throws {
        // 중복 로그인 시도 방지
        guard !isLoggingIn else {
            print("⚠️ 이미 Google 로그인이 진행 중입니다.")
            return
        }

        isLoggingIn = true
        defer { isLoggingIn = false }

        guard let presentingVC = currentRootViewController() else {
            let error = GoogleLoginError.missingPresentingViewController
            self.loginError = error
            throw error
        }

        do {
            // GoogleService-Info.plist의 CLIENT_ID 자동 사용 (DronePassApp에서 GIDConfiguration 설정)
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
            let user = signInResult.user

            guard let idToken = user.idToken?.tokenString else {
                throw GoogleLoginError.missingIDToken
            }
            let accessToken = user.accessToken.tokenString
            let googleUserID = user.userID          // Google 고유 식별자(sub)
            let profileEmail = user.profile?.email

            // 🔍 진단 로깅
            print("🟢 Google Login - User ID: \(googleUserID ?? "nil")")
            print("🟢 Google Login - Email: \(profileEmail ?? "nil (hidden)")")

            // Firebase credential 생성 및 로그인
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            let result = try await Auth.auth().signIn(with: credential)

            // ⚠️ isLogin은 AppleLoginManager의 Auth 상태 리스너가 자동 갱신하므로 여기서 수동 set 금지

            print("🔥 Firebase UID: \(result.user.uid)")
            print("✅ Google login successful - UID: \(result.user.uid), Email: \(result.user.email ?? "Hidden")")

            // AuthManager에 Google 로그인 성공 알림 (이메일과 Google User ID 전달)
            await AuthManager.shared.handleGoogleLoginSuccess(
                email: result.user.email ?? profileEmail,
                googleUserID: googleUserID
            )

        } catch let error as NSError {
            // 사용자 취소는 에러로 취급하지 않음 (alert 미표시)
            if error.domain == kGIDSignInErrorDomain,
               error.code == GIDSignInError.canceled.rawValue {
                print("ℹ️ 사용자가 Google 로그인을 취소했습니다.")
                throw GoogleLoginError.userCancelled
            }
            print("❌ Google login failed with error: \(error.localizedDescription)")
            self.loginError = error
            throw GoogleLoginError.firebaseAuthFailed(underlying: error)
        }
    }
}
