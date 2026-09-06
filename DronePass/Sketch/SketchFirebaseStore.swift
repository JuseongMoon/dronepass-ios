//
//  SketchFirebaseStore.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 Firebase Firestore 저장소
// 연관기능: 스케치 CRUD, 멀티 디바이스 동기화

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// 스케치 Firebase 에러
enum SketchFirebaseError: LocalizedError {
    case notAuthenticated
    case invalidData
    case unknownError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "sketch.error.notAuthenticated")
        case .invalidData:
            return String(localized: "sketch.error.invalidData")
        case .unknownError:
            return String(localized: "sketch.error.unknownError")
        }
    }
}

/// 스케치 Firebase 저장소
final class SketchFirebaseStore {
    static let shared = SketchFirebaseStore()

    private let db = Firestore.firestore()
    private let collectionName = "sketches"
    private let maxRetryCount = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 10.0

    private init() {}

    // 현재 사용자의 스케치 컬렉션 참조
    private var userCollection: CollectionReference? {
        guard let authUser = Auth.auth().currentUser else {
            print("❌ SketchFirebase: 인증된 사용자가 없습니다")
            return nil
        }
        return db.collection("users").document(authUser.uid).collection(collectionName)
    }

    // MARK: - Metadata Operations

    /// 서버 메타데이터 업데이트 (스케치 변경 시 호출)
    func updateServerMetadata() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw SketchFirebaseError.notAuthenticated
        }

        let metadataRef = db.collection("users").document(userId).collection("metadata").document("sketchServer")

        let data: [String: Any] = [
            "lastModified": FieldValue.serverTimestamp()
        ]

        try await metadataRef.setData(data, merge: true)
        print("✅ 스케치 서버 메타데이터 업데이트 완료")
    }

    /// 서버의 마지막 수정 시간 조회
    func getServerLastModifiedTime() async throws -> Date? {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw SketchFirebaseError.notAuthenticated
        }

        let metadataRef = db.collection("users").document(userId).collection("metadata").document("sketchServer")

        let document = try await metadataRef.getDocument()

        if let timestamp = document.data()?["lastModified"] as? Timestamp {
            return timestamp.dateValue()
        }

        return nil
    }

    // MARK: - CRUD Operations

    /// 스케치 로드 (활성 스케치만)
    func loadSketches() async throws -> [SketchModel] {
        return try await performWithRetry {
            guard let collection = self.userCollection else {
                throw SketchFirebaseError.notAuthenticated
            }

            // deletedAt이 null인 문서만 쿼리
            let snapshot = try await collection
                .whereField("deletedAt", isEqualTo: NSNull())
                .getDocuments()

            let allSketches = snapshot.documents.compactMap { document in
                do {
                    return try self.parseSketchFromDocument(document.data(), id: document.documentID)
                } catch {
                    print("⚠️ 스케치 파싱 실패 (ID: \(document.documentID)): \(error)")
                    return nil
                }
            }

            // 이중 방어: deletedAt이 nil인 스케치만
            let activeSketches = allSketches.filter { $0.deletedAt == nil }

            print("✅ Firebase에서 스케치 로드 성공: \(activeSketches.count)개")
            return activeSketches
        }
    }

    /// 삭제된 스케치 포함 전체 로드 (실시간 동기화용)
    func loadAllSketchesIncludingDeleted() async throws -> [SketchModel] {
        return try await performWithRetry {
            guard let collection = self.userCollection else {
                throw SketchFirebaseError.notAuthenticated
            }

            // 모든 문서 가져오기 (삭제된 스케치 포함)
            let snapshot = try await collection.getDocuments()

            let allSketches = snapshot.documents.compactMap { document in
                do {
                    return try self.parseSketchFromDocument(document.data(), id: document.documentID)
                } catch {
                    print("⚠️ 스케치 파싱 실패 (ID: \(document.documentID)): \(error)")
                    return nil
                }
            }

            print("✅ Firebase에서 전체 스케치 로드 성공: \(allSketches.count)개 (삭제된 것 포함)")
            return allSketches
        }
    }

    /// 스케치 추가
    func addSketch(_ sketch: SketchModel) async throws {
        guard validateSketch(sketch) else {
            throw SketchFirebaseError.invalidData
        }

        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw SketchFirebaseError.notAuthenticated
            }

            let data = self.sketchToFirestoreData(sketch)
            try await collection.document(sketch.id.uuidString).setData(data)

            print("✅ Firebase에 스케치 추가 성공: \(sketch.id)")
        }
    }

    /// 스케치 업데이트
    func updateSketch(_ sketch: SketchModel) async throws {
        guard validateSketch(sketch) else {
            throw SketchFirebaseError.invalidData
        }

        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw SketchFirebaseError.notAuthenticated
            }

            let data = self.sketchToFirestoreData(sketch)
            try await collection.document(sketch.id.uuidString).setData(data, merge: true)

            print("✅ Firebase에서 스케치 수정 성공: \(sketch.id)")
        }
    }

    /// 스케치 삭제 (soft delete)
    func removeSketch(id: UUID) async throws {
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw SketchFirebaseError.notAuthenticated
            }

            let now = Date()
            let data: [String: Any] = [
                "deletedAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now)
            ]

            try await collection.document(id.uuidString).setData(data, merge: true)

            print("✅ Firebase에서 스케치 soft delete 성공: \(id)")
        }
    }

    /// 모든 스케치 저장 (배치)
    func saveSketches(_ sketches: [SketchModel]) async throws {
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw SketchFirebaseError.notAuthenticated
            }

            // 배치 크기 제한 (Firestore 배치 제한 500개)
            let batchSize = 500
            let sketchBatches = sketches.chunked(into: batchSize)

            for sketchBatch in sketchBatches {
                let batch = self.db.batch()

                for sketch in sketchBatch {
                    let docRef = collection.document(sketch.id.uuidString)
                    let data = self.sketchToFirestoreData(sketch)
                    batch.setData(data, forDocument: docRef, merge: true)
                }

                try await batch.commit()
            }

            print("✅ Firebase에 스케치 배치 저장 성공: \(sketches.count)개")
        }
    }

    // MARK: - Helper Methods

    /// SketchModel을 Firestore 데이터로 변환
    private func sketchToFirestoreData(_ sketch: SketchModel) -> [String: Any] {
        var data: [String: Any] = [
            "id": sketch.id.uuidString,
            "color": sketch.color,
            "strokeWidth": sketch.strokeWidth,
            "opacity": (sketch.opacity * 100).rounded() / 100,
            "createdAt": Timestamp(date: sketch.createdAt),
            "updatedAt": Timestamp(date: sketch.updatedAt)
        ]

        // points 배열 변환 (소수점 6자리로 반올림)
        data["points"] = sketch.points.map { coord in
            [
                "latitude": (coord.latitude * 1_000_000).rounded() / 1_000_000,
                "longitude": (coord.longitude * 1_000_000).rounded() / 1_000_000
            ]
        }

        // deletedAt이 있는 경우에만 추가
        if let deletedAt = sketch.deletedAt {
            data["deletedAt"] = Timestamp(date: deletedAt)
        }

        return data
    }

    /// Firestore 데이터를 SketchModel로 변환
    private func parseSketchFromDocument(_ data: [String: Any], id: String) throws -> SketchModel {
        guard let idString = data["id"] as? String,
              let uuid = UUID(uuidString: idString) else {
            throw SketchFirebaseError.invalidData
        }

        let color = data["color"] as? String ?? "#FF0000"
        let strokeWidth = data["strokeWidth"] as? Double ?? 3.0
        let opacity = data["opacity"] as? Double ?? 1.0

        // points 배열 파싱
        var points: [CoordinateManager] = []
        if let pointsData = data["points"] as? [[String: Any]] {
            points = pointsData.compactMap { pointData in
                guard let lat = pointData["latitude"] as? Double,
                      let lng = pointData["longitude"] as? Double else { return nil }
                return CoordinateManager(latitude: lat, longitude: lng)
            }
        }

        // 날짜 필드
        let createdAt: Date
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            createdAt = createdAtTimestamp.dateValue()
        } else {
            createdAt = Date()
        }

        let updatedAt: Date
        if let updatedAtTimestamp = data["updatedAt"] as? Timestamp {
            updatedAt = updatedAtTimestamp.dateValue()
        } else {
            updatedAt = createdAt
        }

        let deletedAt: Date? = (data["deletedAt"] as? Timestamp)?.dateValue()

        return SketchModel(
            id: uuid,
            points: points,
            color: color,
            strokeWidth: strokeWidth,
            opacity: opacity,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    // MARK: - Validation

    /// 스케치 데이터 검증
    private func validateSketch(_ sketch: SketchModel) -> Bool {
        // ID 검증
        if sketch.id.uuidString.isEmpty {
            return false
        }

        // 좌표 검증
        for point in sketch.points {
            if !isValidCoordinate(point) {
                return false
            }
        }

        // strokeWidth 검증
        if sketch.strokeWidth <= 0 || sketch.strokeWidth > 50 {
            return false
        }

        return true
    }

    /// 좌표 유효성 검증
    private func isValidCoordinate(_ coordinate: CoordinateManager) -> Bool {
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 &&
               !lat.isNaN && !lng.isNaN && lat.isFinite && lng.isFinite
    }

    // MARK: - Retry Mechanism

    /// 지수 백오프 대기 시간 계산 (지터 포함)
    private func calculateBackoffDelay(attempt: Int) -> TimeInterval {
        // 지수 백오프: 1초, 2초, 4초...
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(attempt - 1))
        // 지터: 0~0.5초 랜덤 추가 (동시 재시도 분산)
        let jitter = Double.random(in: 0...0.5)
        return min(exponentialDelay + jitter, maxRetryDelay)
    }

    /// 재시도 메커니즘 (지수 백오프 적용)
    private func performWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxRetryCount {
            do {
                return try await operation()
            } catch {
                lastError = error

                // 재시도 불가능한 오류
                if let firebaseError = error as? SketchFirebaseError {
                    switch firebaseError {
                    case .notAuthenticated, .invalidData:
                        throw error
                    case .unknownError:
                        break
                    }
                }

                // 마지막 시도가 아니면 지수 백오프 대기 후 재시도
                if attempt < maxRetryCount {
                    let delay = calculateBackoffDelay(attempt: attempt)
                    print("⚠️ 스케치 Firebase 작업 실패 (시도 \(attempt)/\(maxRetryCount), \(String(format: "%.1f", delay))초 후 재시도): \(error)")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? SketchFirebaseError.unknownError
    }
}
