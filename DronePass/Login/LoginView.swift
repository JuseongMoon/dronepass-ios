//
//  LoginView.swift
//  DronePass
//
//  Created by 문주성 on 7/8/25.
//

import SwiftUI
import AuthenticationServices
import FirebaseAuth

struct LoginView: View {
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showLocationTerms = false
    @StateObject private var loginManager = AppleLoginManager.shared
    @StateObject private var googleManager = GoogleLoginManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // 기기 유형에 따른 동적 여백 값
    private var topSpacer: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 72 : 40
    }
    private var verticalPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 32 : 24
    }
    private var bottomExtraPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 40 : 24
    }

    
    var body: some View {
        NavigationView {
            VStack {
                // 상단/하단 여백을 기기 유형에 맞춰 확보
                Spacer(minLength: topSpacer)
                
                // 앱 아이콘
                
                Image("LaunchLogo")
                    .resizable()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.bottom, 32)
                
                // 타이틀
                Text(NSLocalizedString("login.title", comment: "Login/Signup title"))
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.bottom, 24)
                
                Divider()
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                
                // SwiftUI용 Apple 로그인 버튼
                SignInWithAppleButtonView(isLogin: $loginManager.isLogin, loginError: $loginManager.loginError)
                    .frame(height: 50)
                    .frame(maxWidth: 350) // 최대 너비 제한 추가
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                // SwiftUI용 Google 로그인 버튼 (Apple 버튼과 톤앤매너 통일: 흰 배경 + 동일 크기/모양/그림자, 내용 중앙정렬)
                // 에러는 기존 loginManager.loginError 바인딩 + 하단 .alert로 Apple/Google 공통 처리
                Button {
                    Task {
                        do {
                            try await googleManager.loginWithGoogle()
                            // 로그인 성공 시 isLogin은 Auth 리스너가 자동 갱신 → onChange에서 dismiss
                        } catch GoogleLoginError.userCancelled {
                            // 사용자 취소는 무시 (에러 alert 미표시)
                        } catch {
                            loginManager.loginError = error
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image("GoogleLogo") // 공식 컬러 G 로고 에셋
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text(NSLocalizedString("login.google.button", comment: "Sign in with Google"))
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)   // 가로를 채워 로고+텍스트를 중앙정렬
                    .frame(height: 50)            // Apple 버튼과 동일한 셀 높이
                    .background(
                        RoundedRectangle(cornerRadius: 12) // Apple 버튼과 동일한 모서리
                            .fill(Color.white)             // 흰색 배경
                            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1) // 배경 그림자 유지
                    )
                }
                .frame(maxWidth: 350)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .disabled(googleManager.isLoggingIn)

                // 약관 안내 (Apple 버튼 바로 아래로 이동)
                VStack(spacing: 0) {
                    Text(NSLocalizedString("login.terms.intro", comment: "Terms intro"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack(spacing: 0) {
                        Button(action: { showTerms = true }) {
                            Text(NSLocalizedString("login.terms.service", comment: "Terms of service"))
                                .underline()
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)
                        Text(", ")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button(action: { showPrivacy = true }) {
                            Text(NSLocalizedString("login.terms.privacy", comment: "Privacy policy"))
                                .underline()
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)

                        /// 위치기반서비스 미활용으로 인한 비활성화
//                        Text(", ")
//                            .font(.footnote)
//                            .foregroundColor(.secondary)
//                        Button(action: { showLocationTerms = true }) {
//                            Text(NSLocalizedString("login.terms.location", comment: "Location terms"))
//                                .underline()
//                        }
//                        .font(.footnote)
//                        .foregroundColor(.blue)
                        Text(NSLocalizedString("login.terms.middle", comment: "Terms middle part"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    HStack {
                        Text(NSLocalizedString("login.terms.agree", comment: "Terms agreement"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, bottomExtraPadding)
                
                Spacer(minLength: topSpacer)
            }
            .padding(.vertical, verticalPadding)
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
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
            /// 위치기반서비스 미활용으로 인한 비활성화
//            .sheet(isPresented: $showLocationTerms) {
//                NavigationView {
//                    LocationTermsView()
//                }
//            }
            .alert(isPresented: Binding<Bool>(get: { loginManager.loginError != nil }, set: { _ in loginManager.loginError = nil })) {
                Alert(title: Text(NSLocalizedString("login.error.title", comment: "Login error title")), message: Text(loginManager.loginError?.localizedDescription ?? NSLocalizedString("login.error.unknown", comment: "Unknown error")), dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "OK"))))
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            loginManager.isLogin = Auth.auth().currentUser != nil
        }
        .onChange(of: loginManager.isLogin) { oldValue, newValue in
            if newValue {
                dismiss()
            }
        }
    }
}

// SwiftUI용 Apple 로그인 버튼 구현
struct SignInWithAppleButtonView: View {
    @Binding var isLogin: Bool
    @Binding var loginError: Error?
    @State private var currentNonce: String?
    
    var body: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { request in
                let nonce = AppleLoginManager.shared.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleLoginManager.shared.sha256(nonce)
            },
            onCompletion: { result in
                switch result {
                case .success(let authResults):
                    if let appleIDCredential = authResults.credential as? ASAuthorizationAppleIDCredential,
                       let nonce = currentNonce,
                       let appleIDToken = appleIDCredential.identityToken,
                       let idTokenString = String(data: appleIDToken, encoding: .utf8) {

                        // 🔍 진단: Apple User Identifier 로깅
                        let appleUserID = appleIDCredential.user
                        let userEmail = appleIDCredential.email
                        // authorizationCode 추출 (Data? → String?). Firebase에 accessToken으로 전달하여
                        // "accessToken or refreshToken is nil" 인증 실패를 방지한다. (issue #16199)
                        let authCodeString = appleIDCredential.authorizationCode
                            .flatMap { String(data: $0, encoding: .utf8) }
                        print("🍎 Apple Login - User ID: \(appleUserID)")
                        print("🍎 Apple Login - Email: \(userEmail ?? "nil (Private Relay or hidden)")")
                        print("🍎 Apple Login - Full Name: \(appleIDCredential.fullName?.givenName ?? "nil") \(appleIDCredential.fullName?.familyName ?? "nil")")
                        print("🍎 Apple Login - authorizationCode: \(authCodeString != nil ? "있음" : "없음")")

                        Task {
                            do {
                                try await AppleLoginManager.shared.loginWithApple(
                                    idTokenString: idTokenString,
                                    nonce: nonce,
                                    fullName: appleIDCredential.fullName,
                                    appleUserID: appleUserID,
                                    authorizationCode: authCodeString
                                )
                                // AuthManager와 AppleLoginManager의 자동 동기화로 인해
                                // 수동으로 isLogin을 설정할 필요 없음
                            } catch {
                                await MainActor.run {
                                    self.loginError = error
                                }
                            }
                        }
                    } else {
                        self.loginError = NSError(
                            domain: "AppleLogin",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("login.error.appleToken", comment: "Apple token error")]
                        )
                    }
                case .failure(let error):
                    // 사용자가 로그인 시트를 닫거나 취소한 경우(ASAuthorizationError.canceled, 코드 1001)는
                    // 실제 오류가 아니므로 Alert을 표시하지 않는다. (Google 로그인의 취소 처리와 동일한 정책)
                    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                        print("ℹ️ 사용자가 Apple 로그인을 취소했습니다.")
                    } else {
                        self.loginError = error
                    }
                }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .cornerRadius(12)
        .accessibilityLabel(NSLocalizedString("login.apple.accessibility", comment: "Continue with Apple"))
    }
}
