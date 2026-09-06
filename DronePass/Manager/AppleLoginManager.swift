//
//  AppleLoginManager.swift
//  DronePass
//
//  Created by 문주성 on 7/22/25.
//

import Foundation
import FirebaseAuth
import CryptoKit
import AuthenticationServices
import Combine

// MARK: - Apple Login Error

/// Apple 로그인 관련 에러
public enum AppleLoginError: LocalizedError {
    case invalidCredential
    case firebaseAuthFailed(underlying: Error)
    case userCancelled
    case alreadyLoggingIn
    case unknown(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "유효하지 않은 Apple 인증 정보입니다."
        case .firebaseAuthFailed(let error):
            return "Firebase 인증 실패: \(error.localizedDescription)"
        case .userCancelled:
            return "사용자가 로그인을 취소했습니다."
        case .alreadyLoggingIn:
            return "이미 로그인이 진행 중입니다."
        case .unknown(let error):
            return "알 수 없는 오류: \(error.localizedDescription)"
        }
    }
}

@MainActor
public class AppleLoginManager: NSObject, ObservableObject {
    public static let shared = AppleLoginManager()

    public override init() {
        super.init()
        // 앱 시작 시 로그인 상태 동기화
        self.isLogin = Auth.auth().currentUser != nil
        // Firebase Auth 상태 변경 리스너 등록 및 저장
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isLogin = (user != nil)
            }
        }
        // 저장된 Apple User ID 로드
        self.loadStoredAppleUserID()
    }

    deinit {
        // 리스너 해제
        if let handle = authStateListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // 로그인 상태 및 에러를 전역에서 관찰 가능하게 관리
    @Published public var isLogin: Bool = false
    @Published public var loginError: Error? = nil
    @Published public var isLoggingIn: Bool = false  // 중복 로그인 시도 방지
    public var currentNonce: String? = nil
    public var storedAppleUserID: String? = nil

    // Auth 상태 리스너 저장 (메모리 누수 방지)
    private var authStateListener: AuthStateDidChangeListenerHandle?

    // MARK: - Apple User ID 저장 및 로드

    /// 로컬에 Apple User ID 저장 (디바이스 간 일관성 추적)
    private func saveAppleUserID(_ appleUserID: String) {
        UserDefaults.standard.set(appleUserID, forKey: "storedAppleUserID")
        self.storedAppleUserID = appleUserID
        print("💾 Apple User ID 로컬 저장: \(appleUserID)")
    }

    /// 로컬에서 Apple User ID 로드
    private func loadStoredAppleUserID() {
        if let stored = UserDefaults.standard.string(forKey: "storedAppleUserID") {
            self.storedAppleUserID = stored
            print("📂 저장된 Apple User ID 로드: \(stored)")
        }
    }

    // Nonce 생성
    public func randomNonceString(length: Int = 32) -> String {
        let charset: Array<Character> = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
    
    // SHA256 해시
    public func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // Apple 로그인 인증 처리
    public func loginWithApple(idTokenString: String, nonce: String, fullName: PersonNameComponents?, appleUserID: String, authorizationCode: String?) async throws {
        // 중복 로그인 시도 방지
        guard !isLoggingIn else {
            print("⚠️ 이미 로그인이 진행 중입니다.")
            throw AppleLoginError.alreadyLoggingIn
        }

        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            // authorizationCode가 있으면 accessToken으로 함께 전달하여
            // "Invalid user token: accessToken or refreshToken is nil" 인증 실패를 방지한다.
            // (Firebase iOS SDK issue #16199: idToken만 전달 시 일부 사용자/상황에서 토큰 발급 실패)
            let credential: AuthCredential
            if let authorizationCode, !authorizationCode.isEmpty {
                credential = OAuthProvider.credential(
                    providerID: .apple,
                    idToken: idTokenString,
                    rawNonce: nonce,
                    accessToken: authorizationCode
                )
                print("🔐 Apple credential 생성: authorizationCode 포함 방식")
            } else {
                // authorizationCode가 없는 경우 기존 방식으로 폴백 (fullName 전달)
                credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: fullName)
                print("🔐 Apple credential 생성: appleCredential 폴백 방식 (authorizationCode 없음)")
            }
            let result = try await Auth.auth().signIn(with: credential)

            // Apple에서 제공하는 이메일 추출 (가린 경우 nil)
            let email = result.user.email

            // 🔍 진단: Firebase UID와 Apple User ID 매핑 로깅
            print("🔥 Firebase UID: \(result.user.uid)")
            print("🍎 Apple User ID: \(appleUserID)")
            print("📧 Email: \(email ?? "nil (Private Relay or hidden)")")

            // 저장된 Apple User ID와 비교 (디바이스 간 일관성 확인)
            if let stored = self.storedAppleUserID {
                if stored == appleUserID {
                    print("✅ Apple User ID 일치 확인: 동일한 Apple 계정")
                } else {
                    print("⚠️ Apple User ID 불일치: 기존(\(stored)) vs 현재(\(appleUserID))")
                }
            }

            // Apple User ID 저장
            self.saveAppleUserID(appleUserID)

            // AuthManager에 Apple 로그인 성공 알림 (이메일과 Apple User ID 전달)
            await AuthManager.shared.handleAppleLoginSuccess(email: email, appleUserID: appleUserID)

            print("✅ Apple login successful - UID: \(result.user.uid), Email: \(email ?? "Hidden")")

        } catch {
            print("❌ Apple login failed with error: \(error.localizedDescription)")
            self.loginError = error
            throw AppleLoginError.firebaseAuthFailed(underlying: error)
        }
    }
}
