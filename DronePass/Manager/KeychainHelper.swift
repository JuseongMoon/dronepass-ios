//
//  KeychainHelper.swift
//  DronePass
//
//  Created by Claude on 2025-10-02.
//

import Foundation
import Security

/// Keychain을 이용한 안전한 데이터 저장 (앱 삭제 후에도 유지)
final class KeychainHelper {

    static let shared = KeychainHelper()

    private init() {}

    // MARK: - Keychain Keys

    private enum KeychainKey {
        static let firebaseUID = "com.dronepass.firebase.uid"
        static let appleUserID = "com.dronepass.apple.userid"
        static let googleUserID = "com.dronepass.google.userid"
    }

    // MARK: - Public Methods

    /// Firebase UID를 Keychain에 저장
    func saveFirebaseUID(_ uid: String) {
        save(key: KeychainKey.firebaseUID, value: uid)
        print("🔐 Keychain: Firebase UID 저장 완료")
    }

    /// Keychain에서 Firebase UID 로드
    func loadFirebaseUID() -> String? {
        let uid = load(key: KeychainKey.firebaseUID)
        if let uid = uid {
            print("🔐 Keychain: Firebase UID 로드 성공 - \(uid)")
        } else {
            print("🔐 Keychain: Firebase UID 없음")
        }
        return uid
    }

    /// Apple User ID를 Keychain에 저장
    func saveAppleUserID(_ appleUserID: String) {
        save(key: KeychainKey.appleUserID, value: appleUserID)
        print("🔐 Keychain: Apple User ID 저장 완료")
    }

    /// Keychain에서 Apple User ID 로드
    func loadAppleUserID() -> String? {
        let appleUserID = load(key: KeychainKey.appleUserID)
        if let appleUserID = appleUserID {
            print("🔐 Keychain: Apple User ID 로드 성공 - \(appleUserID)")
        } else {
            print("🔐 Keychain: Apple User ID 없음")
        }
        return appleUserID
    }

    /// Google User ID를 Keychain에 저장
    func saveGoogleUserID(_ googleUserID: String) {
        save(key: KeychainKey.googleUserID, value: googleUserID)
        print("🔐 Keychain: Google User ID 저장 완료")
    }

    /// Keychain에서 Google User ID 로드
    func loadGoogleUserID() -> String? {
        let googleUserID = load(key: KeychainKey.googleUserID)
        if let googleUserID = googleUserID {
            print("🔐 Keychain: Google User ID 로드 성공 - \(googleUserID)")
        } else {
            print("🔐 Keychain: Google User ID 없음")
        }
        return googleUserID
    }

    /// Keychain에서 Google User ID 삭제 (회원 탈퇴 시)
    func deleteGoogleUserID() {
        delete(key: KeychainKey.googleUserID)
        print("🔐 Keychain: Google User ID 삭제 완료")
    }

    /// Keychain에서 Firebase UID 삭제 (회원 탈퇴 시)
    func deleteFirebaseUID() {
        delete(key: KeychainKey.firebaseUID)
        print("🔐 Keychain: Firebase UID 삭제 완료")
    }

    /// Keychain에서 Apple User ID 삭제 (회원 탈퇴 시)
    func deleteAppleUserID() {
        delete(key: KeychainKey.appleUserID)
        print("🔐 Keychain: Apple User ID 삭제 완료")
    }

    /// 모든 인증 정보 삭제 (회원 탈퇴 시)
    func deleteAllAuthData() {
        deleteFirebaseUID()
        deleteAppleUserID()
        deleteGoogleUserID()
        print("🔐 Keychain: 모든 인증 정보 삭제 완료")
    }

    // MARK: - Private Keychain Operations

    /// Keychain에 데이터 저장
    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else {
            print("❌ Keychain: 데이터 인코딩 실패 - \(key)")
            return
        }

        // 기존 항목이 있으면 먼저 삭제
        delete(key: key)

        // 새 항목 추가
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock // 재부팅 후 첫 잠금 해제 이후 접근 가능
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            print("✅ Keychain: 저장 성공 - \(key)")
        } else {
            print("❌ Keychain: 저장 실패 - \(key), 상태 코드: \(status)")
        }
    }

    /// Keychain에서 데이터 로드
    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            if let data = result as? Data,
               let value = String(data: data, encoding: .utf8) {
                return value
            }
        } else if status == errSecItemNotFound {
            // 항목이 없는 경우 (정상)
            return nil
        } else {
            print("❌ Keychain: 로드 실패 - \(key), 상태 코드: \(status)")
        }

        return nil
    }

    /// Keychain에서 데이터 삭제
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            // 삭제 성공 또는 항목이 없는 경우 모두 정상
        } else {
            print("❌ Keychain: 삭제 실패 - \(key), 상태 코드: \(status)")
        }
    }
}
