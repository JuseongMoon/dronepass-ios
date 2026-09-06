//
//  DroneFirebaseStore.swift
//  DronePass
//
//  Created by Claude on 2025-09-30.
//

// 역할: 드론 데이터 Firebase 저장소
// 연관기능: 드론 CRUD, 실시간 동기화, 사용자별 드론 관리

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

protocol DroneStoreProtocol {
    associatedtype DroneType: Codable, Identifiable

    func save(_ drone: DroneType) async throws
    func saveAll(_ drones: [DroneType]) async throws
    func load() async throws -> [DroneType]
    func delete(id: String) async throws
    func observeChanges(onChange: @escaping ([DroneType]) -> Void) -> ListenerRegistration?
}

final class DroneFirebaseStore: DroneStoreProtocol {
    typealias DroneType = DroneModel

    static let shared = DroneFirebaseStore()

    private let db = Firestore.firestore()
    private let collectionName = "drones"
    private let maxRetryCount = 3
    private let retryDelay: TimeInterval = 1.0

    private init() {
        // Firestore 설정은 앱 시작 시에만 수행 (DronePassApp.swift에서 처리)
        // 중복 설정을 방지하기 위해 여기서는 설정하지 않음
    }

    // 현재 사용자의 컬렉션 참조를 가져옵니다
    private var userCollection: CollectionReference? {
        guard let authUser = Auth.auth().currentUser else {
            return nil
        }
        return db.collection("users").document(authUser.uid).collection(collectionName)
    }

    // MARK: - CRUD Operations

    func save(_ drone: DroneModel) async throws {
        guard let collection = userCollection else {
            throw FirebaseError.notAuthenticated
        }

        var retryCount = 0
        while retryCount < maxRetryCount {
            do {
                try await collection.document(drone.id).setData(from: drone)
                print("🚁 드론 Firebase 저장 성공: \(drone.name)")
                return
            } catch {
                retryCount += 1
                if retryCount >= maxRetryCount {
                    print("❌ 드론 Firebase 저장 실패: \(error)")
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
    }

    func saveAll(_ drones: [DroneModel]) async throws {
        try await saveBatch(drones)
    }

    func load() async throws -> [DroneModel] {
        guard let collection = userCollection else {
            throw FirebaseError.notAuthenticated
        }

        var retryCount = 0
        while retryCount < maxRetryCount {
            do {
                // 모든 드론을 가져온 후 클라이언트에서 필터링
                let snapshot = try await collection.getDocuments()
                let drones = snapshot.documents.compactMap { document -> DroneModel? in
                    do {
                        let drone = try document.data(as: DroneModel.self)
                        // deletedAt이 nil인 활성 드론만 반환
                        return drone.deletedAt == nil ? drone : nil
                    } catch {
                        print("⚠️ 드론 디코딩 실패: \(document.documentID), \(error)")
                        return nil
                    }
                }
                print("🚁 드론 Firebase 로드 성공: \(drones.count)개 (활성)")
                return drones
            } catch {
                retryCount += 1
                if retryCount >= maxRetryCount {
                    print("❌ 드론 Firebase 로드 실패: \(error)")
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        return []
    }

    func delete(id: String) async throws {
        guard let collection = userCollection else {
            throw FirebaseError.notAuthenticated
        }

        var retryCount = 0
        while retryCount < maxRetryCount {
            do {
                try await collection.document(id).delete()
                print("🚁 드론 Firebase 삭제 성공: \(id)")
                return
            } catch {
                retryCount += 1
                if retryCount >= maxRetryCount {
                    print("❌ 드론 Firebase 삭제 실패: \(error)")
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
    }

    // MARK: - 실시간 관찰

    func observeChanges(onChange: @escaping ([DroneModel]) -> Void) -> ListenerRegistration? {
        guard let collection = userCollection else {
            print("❌ 드론 실시간 관찰 실패: 사용자 인증 안됨")
            return nil
        }

        // 모든 드론을 실시간 관찰하고 클라이언트에서 필터링
        return collection
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ 드론 실시간 관찰 에러: \(error)")
                    return
                }

                guard let snapshot = snapshot else {
                    print("⚠️ 드론 스냅샷이 nil")
                    return
                }

                let drones = snapshot.documents.compactMap { document -> DroneModel? in
                    do {
                        let drone = try document.data(as: DroneModel.self)
                        // deletedAt이 nil인 활성 드론만 반환
                        return drone.deletedAt == nil ? drone : nil
                    } catch {
                        print("⚠️ 드론 디코딩 실패: \(document.documentID), \(error)")
                        return nil
                    }
                }

                print("🚁 드론 실시간 업데이트: \(drones.count)개 (활성)")
                onChange(drones)
            }
    }

    // MARK: - 배치 작업

    func saveBatch(_ drones: [DroneModel]) async throws {
        guard let collection = userCollection else {
            throw FirebaseError.notAuthenticated
        }

        let batch = db.batch()

        for drone in drones {
            let ref = collection.document(drone.id)
            try batch.setData(from: drone, forDocument: ref)
        }

        var retryCount = 0
        while retryCount < maxRetryCount {
            do {
                try await batch.commit()
                print("🚁 드론 배치 저장 성공: \(drones.count)개")
                return
            } catch {
                retryCount += 1
                if retryCount >= maxRetryCount {
                    print("❌ 드론 배치 저장 실패: \(error)")
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
    }

    // MARK: - 헬퍼 메서드

    /// 특정 드론 하나만 가져오기
    func loadDrone(id: String) async throws -> DroneModel? {
        guard let collection = userCollection else {
            throw FirebaseError.notAuthenticated
        }

        do {
            let document = try await collection.document(id).getDocument()
            guard document.exists else {
                return nil
            }
            return try document.data(as: DroneModel.self)
        } catch {
            print("❌ 드론 단일 로드 실패 (\(id)): \(error)")
            throw error
        }
    }

    /// 사용자의 모든 드론 삭제 (계정 삭제 시 사용)
    func deleteAllDrones() async throws {
        guard let collection = userCollection else {
            throw FirebaseError.notAuthenticated
        }

        let snapshot = try await collection.getDocuments()
        let batch = db.batch()

        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }

        try await batch.commit()
        print("🚁 모든 드론 삭제 완료")
    }
}

// MARK: - Firebase 에러

enum FirebaseError: Error, LocalizedError {
    case notAuthenticated
    case documentNotFound
    case decodingFailed
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "사용자가 인증되지 않았습니다."
        case .documentNotFound:
            return "요청한 문서를 찾을 수 없습니다."
        case .decodingFailed:
            return "데이터 디코딩에 실패했습니다."
        case .networkError:
            return "네트워크 오류가 발생했습니다."
        }
    }
}