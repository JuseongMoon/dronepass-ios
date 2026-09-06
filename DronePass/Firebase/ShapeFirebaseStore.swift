import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

final class ShapeFirebaseStore: ShapeStoreProtocol {
    typealias ShapeType = ShapeModel
    
    static let shared = ShapeFirebaseStore()
    
    private let db = Firestore.firestore()
    private let collectionName = "shapes"
    private let maxRetryCount = 3
    private let retryDelay: TimeInterval = 1.0
    
    private init() {
        // Firestore 설정은 앱 시작 시에만 수행 (DronePassApp.swift에서 처리)
        // 중복 설정을 방지하기 위해 여기서는 설정하지 않음
    }
    
    // 현재 사용자의 컬렉션 참조를 가져옵니다
    private var userCollection: CollectionReference? {
        // FirebaseAuth에서 직접 가져옴 (AuthManager는 MainActor이므로 직접 접근 회피)
        if let authUser = Auth.auth().currentUser {
            return db.collection("users").document(authUser.uid).collection(collectionName)
        }
        print("❌ Firebase: 인증된 사용자가 없습니다")
        return nil
    }
    
    func loadShapes() async throws -> [ShapeModel] {
        return try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }

            // Android and older iOS clients omit deletedAt for active shapes.
            // A Firestore null query excludes documents where the field is missing,
            // so fetch the collection and apply the active filter after parsing.
            let snapshot = try await collection.getDocuments()

            let allShapes = snapshot.documents.compactMap { document in
                do {
                    return try self.parseShapeFromDocument(document.data(), id: document.documentID)
                } catch {
                    print("⚠️ 도형 파싱 실패 (ID: \(document.documentID)): \(error)")
                    return nil
                }
            }

            // 이중 방어: 메모리 필터링 (deletedAt이 nil인 도형들만)
            let activeShapes = allShapes.filter { shape in
                return shape.deletedAt == nil
            }

            // 데이터 검증
            if !self.validateFirebaseShapes(activeShapes) {
                throw ShapeFirebaseError.invalidData
            }

            // 로컬 색상과 파이어스토어 색상 동기화 (서버 기준으로 활성 도형 색상 통일)
            let synchronizedShapes = await self.synchronizeColorsWithLocal(activeShapes)

            print("✅ Firebase에서 도형 데이터 로드 성공: \(synchronizedShapes.count)개 (deletedAt 누락 호환)")
            return synchronizedShapes
        }
    }

    /// 삭제된 도형을 포함하여 모든 도형을 로드 (동기화/검증용)
    func loadAllShapesIncludingDeleted() async throws -> [ShapeModel] {
        return try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }
            let snapshot = try await collection.getDocuments()
            let allShapes = snapshot.documents.compactMap { document in
                do {
                    return try self.parseShapeFromDocument(document.data(), id: document.documentID)
                } catch {
                    print("⚠️ 도형 파싱 실패 (ID: \(document.documentID)): \(error)")
                    return nil
                }
            }
            print("✅ Firebase에서 모든 도형 로드 (삭제 포함): \(allShapes.count)개")
            return allShapes
        }
    }
    
    func saveShapes(_ shapes: [ShapeModel]) async throws {
        // 저장 전 데이터 검증
        guard validateFirebaseShapes(shapes) else {
            throw ShapeFirebaseError.invalidData
        }
        
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            // 배치 크기 제한 (Firestore 배치 제한 500개)
            let batchSize = 500
            let shapeBatches = shapes.chunked(into: batchSize)
            
            for shapeBatch in shapeBatches {
                let batch = self.db.batch()
                
                for shape in shapeBatch {
                    let docRef = collection.document(shape.id.uuidString)
                    let data = try self.shapeToFirestoreData(shape)
                    // merge:true로 설정하여 존재하는 필드만 업데이트하고 누락된 필드(예: deletedAt)를 보존
                    batch.setData(data, forDocument: docRef, merge: true)
                }
                
                try await batch.commit()
            }
            
            // 서버 메타데이터 업데이트 (마지막 수정 시간)
            try await self.updateServerMetadata()
            
            print("✅ Firebase에 도형 데이터 저장 및 메타데이터 업데이트 성공: \(shapes.count)개")
        }
    }
    
    func addShape(_ shape: ShapeModel) async throws {
        // 데이터 검증
        guard validateSingleShape(shape) else {
            throw ShapeFirebaseError.invalidData
        }
        
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            let data = try self.shapeToFirestoreData(shape)
            try await collection.document(shape.id.uuidString).setData(data)
            
            // 서버 메타데이터 업데이트
            try await self.updateServerMetadata()
            
            print("✅ Firebase에 도형 추가 및 메타데이터 업데이트 성공: \(shape.title)")
        }
    }
    
    func removeShape(id: UUID) async throws {
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            // soft delete: 문서를 완전히 삭제하지 않고 deletedAt 필드만 설정
            let now = Date()
            let data: [String: Any] = [
                "deletedAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now)
            ]
            
            try await collection.document(id.uuidString).setData(data, merge: true)
            
            // 서버 메타데이터 업데이트
            try await self.updateServerMetadata()
            
            print("✅ Firebase에서 도형 soft delete 및 메타데이터 업데이트 성공: \(id)")
        }
    }

    /// 여러 개의 도형을 일괄 soft delete 처리
    func markDeleted(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }
            let batch = self.db.batch()
            let now = Date()
            for id in ids {
                let docRef = collection.document(id.uuidString)
                let data: [String: Any] = [
                    "deletedAt": Timestamp(date: now),
                    "updatedAt": Timestamp(date: now)
                ]
                batch.setData(data, forDocument: docRef, merge: true)
            }
            try await batch.commit()
            try await self.updateServerMetadata()
            print("✅ Firebase 일괄 soft delete 완료: \(ids.count)개")
        }
    }
    
    func updateShape(_ shape: ShapeModel) async throws {
        // 데이터 검증
        guard validateSingleShape(shape) else {
            throw ShapeFirebaseError.invalidData
        }
        
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            let data = try self.shapeToFirestoreData(shape)
            try await collection.document(shape.id.uuidString).setData(data, merge: true)
            
            // 서버 메타데이터 업데이트
            try await self.updateServerMetadata()
            
            print("✅ Firebase에서 도형 수정 및 메타데이터 업데이트 성공: \(shape.title)")
        }
    }
    
    func deleteExpiredShapes() async throws {
        try await performWithRetry {
            guard let collection = self.userCollection else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            let now = Date()
            let snapshot = try await collection.getDocuments()
            let batch = self.db.batch()
            
            var deletedCount = 0
            for document in snapshot.documents {
                if let shape = try? self.parseShapeFromDocument(document.data(), id: document.documentID),
                   let expireDate = shape.flightEndDate,
                   expireDate < now {
                    // Soft delete: deletedAt 필드에 현재 시간 설정
                    let deleteData: [String: Any] = ["deletedAt": Timestamp(date: now)]
                    batch.updateData(deleteData, forDocument: document.reference)
                    deletedCount += 1
                }
            }
            
            if deletedCount > 0 {
                try await batch.commit()
                
                // 서버 메타데이터 업데이트
                try await self.updateServerMetadata()
                
                print("✅ Firebase에서 만료된 도형 soft delete 성공: \(deletedCount)개")
            }
        }
    }
    
    // MARK: - Server Metadata Methods
    
    /// 서버 메타데이터 업데이트 (마지막 수정 시간 및 색상 변경 시점)
    private func updateServerMetadata() async throws {
        try await performWithRetry {
            guard let userId = Auth.auth().currentUser?.uid else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            let metadataRef = self.db.collection("users").document(userId).collection("metadata").document("server")
            var metadata: [String: Any] = [
                "lastModified": Timestamp(date: Date())
            ]

            // 색상 변경 시점이 있으면 포함 (MainActor 접근)
            let colorChangeTime = await MainActor.run { ColorManager.shared.lastColorChangeTime }
            if let colorChangeTime = colorChangeTime {
                metadata["lastColorChange"] = Timestamp(date: colorChangeTime)
            }

            try await metadataRef.setData(metadata)
        }
    }
    
    /// 서버의 마지막 수정 시간 가져오기
    func getServerLastModifiedTime() async throws -> Date {
        try await performWithRetry {
            guard let userId = Auth.auth().currentUser?.uid else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            let metadataRef = self.db.collection("users").document(userId).collection("metadata").document("server")
            let document = try await metadataRef.getDocument()
            
            if let timestamp = document.data()?["lastModified"] as? Timestamp {
                return timestamp.dateValue()
            } else {
                // 메타데이터가 없으면 과거 시간 반환 (변경사항 없음으로 처리)
                return Date.distantPast
            }
        }
    }
    
    /// 서버의 마지막 색상 변경 시점 가져오기
    func getServerLastColorChangeTime() async throws -> Date? {
        try await performWithRetry {
            guard let userId = Auth.auth().currentUser?.uid else {
                throw ShapeFirebaseError.notAuthenticated
            }
            
            let metadataRef = self.db.collection("users").document(userId).collection("metadata").document("server")
            let document = try await metadataRef.getDocument()
            
            if let timestamp = document.data()?["lastColorChange"] as? Timestamp {
                return timestamp.dateValue()
            } else {
                return nil
            }
        }
    }
    
    /// 변경사항이 있는지 확인
    func hasChanges() async throws -> Bool {
        let serverLastModified = try await getServerLastModifiedTime()
        let localLastSync = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date ?? Date.distantPast
        
        return serverLastModified > localLastSync
    }
    
    // MARK: - Helper Methods
    
    /// ShapeModel을 Firestore 데이터로 변환
    func shapeToFirestoreData(_ shape: ShapeModel) throws -> [String: Any] {
        var data: [String: Any] = [
            "id": shape.id.uuidString,
            "title": shape.title,
            "shapeType": shape.shapeType.rawValue,
            "baseCoordinate": [
                "latitude": (shape.baseCoordinate.latitude * 1_000_000).rounded() / 1_000_000,
                "longitude": (shape.baseCoordinate.longitude * 1_000_000).rounded() / 1_000_000
            ],
            "memo": shape.memo ?? "",
            "address": shape.address ?? "",
            "createdAt": Timestamp(date: shape.createdAt),
            "flightStartDate": Timestamp(date: shape.flightStartDate),
            "color": shape.color,
            "updatedAt": Timestamp(date: shape.updatedAt)
        ]
        
        // flightEndDate가 있는 경우에만 추가
        if let flightEndDate = shape.flightEndDate {
            data["flightEndDate"] = Timestamp(date: flightEndDate)
        }
        
        // deletedAt이 있는 경우에만 추가
        if let deletedAt = shape.deletedAt {
            data["deletedAt"] = Timestamp(date: deletedAt)
        }

        // droneId 추가 (하이브리드 호환성 - 있는 경우에만)
        if let droneId = shape.droneId {
            data["droneId"] = droneId
        }

        // 추가 도형 데이터
        if let radius = shape.radius {
            data["radius"] = radius
        }
        
        if let secondCoordinate = shape.secondCoordinate {
            data["secondCoordinate"] = [
                "latitude": (secondCoordinate.latitude * 1_000_000).rounded() / 1_000_000,
                "longitude": (secondCoordinate.longitude * 1_000_000).rounded() / 1_000_000
            ]
        }
        
        if let polygonCoordinates = shape.polygonCoordinates {
            data["polygonCoordinates"] = polygonCoordinates.map { coord in
                [
                    "latitude": (coord.latitude * 1_000_000).rounded() / 1_000_000,
                    "longitude": (coord.longitude * 1_000_000).rounded() / 1_000_000
                ]
            }
        }
        
        if let polylineCoordinates = shape.polylineCoordinates {
            data["polylineCoordinates"] = polylineCoordinates.map { coord in
                [
                    "latitude": (coord.latitude * 1_000_000).rounded() / 1_000_000,
                    "longitude": (coord.longitude * 1_000_000).rounded() / 1_000_000
                ]
            }
        }

        // height 추가 (드론 비행 고도)
        if let height = shape.height {
            data["height"] = height
        }

        return data
    }
    
    /// Firestore 데이터를 ShapeModel로 변환
    func parseShapeFromDocument(_ data: [String: Any], id: String) throws -> ShapeModel {
        guard let idString = data["id"] as? String,
              let uuid = UUID(uuidString: idString),
              let title = data["title"] as? String,
              let shapeTypeString = data["shapeType"] as? String,
              let shapeType = DronePass.ShapeType(rawValue: shapeTypeString.lowercased()),
              let baseCoordData = data["baseCoordinate"] as? [String: Any],
              let baseLat = baseCoordData["latitude"] as? Double,
              let baseLng = baseCoordData["longitude"] as? Double,
              let color = data["color"] as? String else {
            throw ShapeFirebaseError.invalidData
        }
        
        let baseCoordinate = CoordinateManager(latitude: baseLat, longitude: baseLng)
        let memo = data["memo"] as? String
        let address = data["address"] as? String
        
        // 날짜 필드들 읽기 (새로운 필드명 우선, 기존 필드명은 방어 코드로 사용)
        let flightStartDate: Date
        if let flightStartTimestamp = data["flightStartDate"] as? Timestamp {
            flightStartDate = flightStartTimestamp.dateValue()
        } else if let startedAtTimestamp = data["startedAt"] as? Timestamp {
            // 기존 데이터 방어 코드: startedAt 필드 사용
            flightStartDate = startedAtTimestamp.dateValue()
        } else {
            throw ShapeFirebaseError.invalidData
        }
        
        let flightEndDate: Date?
        if let flightEndTimestamp = data["flightEndDate"] as? Timestamp {
            flightEndDate = flightEndTimestamp.dateValue()
        } else {
            // 기존 데이터 방어 코드: expireDate 필드 사용
            flightEndDate = (data["expireDate"] as? Timestamp)?.dateValue()
        }
        
        // createdAt 처리 (새로운 필드 우선, 없으면 기존 로직 사용)
        let createdAt: Date
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            createdAt = createdAtTimestamp.dateValue()
        } else {
            // 기존 데이터 방어 코드: startedAt을 createdAt으로 사용
            createdAt = flightStartDate
            
            // 백그라운드에서 createdAt 필드 추가 (마이그레이션)
            Task {
                await self.migrateDocumentCreatedAt(documentId: idString, createdAt: createdAt)
            }
        }
        
        // deletedAt 처리
        let deletedAt: Date? = (data["deletedAt"] as? Timestamp)?.dateValue()
        
        // 도형 타입별 데이터 파싱
        var radius: Double?
        var secondCoordinate: CoordinateManager?
        var polygonCoordinates: [CoordinateManager]?
        var polylineCoordinates: [CoordinateManager]?
        
        switch shapeType {
        case .circle:
            radius = data["radius"] as? Double
        case .rectangle:
            if let secondCoordData = data["secondCoordinate"] as? [String: Any],
               let secondLat = secondCoordData["latitude"] as? Double,
               let secondLng = secondCoordData["longitude"] as? Double {
                secondCoordinate = CoordinateManager(latitude: secondLat, longitude: secondLng)
            }
        case .polygon:
            if let polygonData = data["polygonCoordinates"] as? [[String: Any]] {
                polygonCoordinates = polygonData.compactMap { coordData in
                    guard let lat = coordData["latitude"] as? Double,
                          let lng = coordData["longitude"] as? Double else { return nil }
                    return CoordinateManager(latitude: lat, longitude: lng)
                }
            }
        case .polyline:
            if let polylineData = data["polylineCoordinates"] as? [[String: Any]] {
                polylineCoordinates = polylineData.compactMap { coordData in
                    guard let lat = coordData["latitude"] as? Double,
                          let lng = coordData["longitude"] as? Double else { return nil }
                    return CoordinateManager(latitude: lat, longitude: lng)
                }
            }
        }
        
        // updatedAt 처리
        let updatedAt: Date
        if let updatedAtTimestamp = data["updatedAt"] as? Timestamp {
            updatedAt = updatedAtTimestamp.dateValue()
        } else {
            updatedAt = createdAt
        }

        // droneId 처리 (하이브리드 호환성 - 없을 수도 있음)
        let droneId = data["droneId"] as? String

        // height 처리 (드론 비행 고도 - 없을 수도 있음)
        let height = data["height"] as? Double

        return ShapeModel(
            id: uuid,
            title: title,
            shapeType: shapeType,
            baseCoordinate: baseCoordinate,
            radius: radius,
            secondCoordinate: secondCoordinate,
            polygonCoordinates: polygonCoordinates,
            polylineCoordinates: polylineCoordinates,
            height: height,
            memo: memo,
            address: address,
            createdAt: createdAt,
            deletedAt: deletedAt,
            flightStartDate: flightStartDate,
            flightEndDate: flightEndDate,
            color: color,
            droneId: droneId,
            updatedAt: updatedAt
        )
    }
    
    /// Firebase 문서에 createdAt 필드를 추가 (마이그레이션)
    private func migrateDocumentCreatedAt(documentId: String, createdAt: Date) async {
        do {
            guard let collection = userCollection else { return }
            
            let data: [String: Any] = [
                "createdAt": Timestamp(date: createdAt)
            ]
            
            try await collection.document(documentId).setData(data, merge: true)
            print("📅 Firebase 문서 '\(documentId)' createdAt 마이그레이션 완료: \(createdAt)")
        } catch {
            print("⚠️ Firebase 문서 createdAt 마이그레이션 실패: \(error)")
        }
    }
    
    // MARK: - Safety & Retry Methods
    
    /// 재시도 메커니즘이 있는 비동기 작업 수행
    private func performWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetryCount {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // 재시도 불가능한 오류들
                if let firebaseError = error as? ShapeFirebaseError {
                    switch firebaseError {
                    case .notAuthenticated, .invalidData:
                        throw error
                    case .unknownError:
                        // unknownError는 재시도 가능
                        break
                    }
                }
                
                // 마지막 시도가 아니면 잠시 대기 후 재시도
                if attempt < maxRetryCount {
                    print("⚠️ Firebase 작업 실패 (시도 \(attempt)/\(maxRetryCount)): \(error)")
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? ShapeFirebaseError.unknownError
    }
    
    /// Firebase 도형 데이터 검증 (배열)
    private func validateFirebaseShapes(_ shapes: [ShapeModel]) -> Bool {
        // 빈 배열은 유효함
        if shapes.isEmpty { return true }
        
        // 각 도형 검증
        for shape in shapes {
            if !validateSingleShape(shape) {
                return false
            }
        }
        
        // 중복 ID 검증
        let uniqueIds = Set(shapes.map { $0.id })
        return uniqueIds.count == shapes.count
    }
    
    /// 단일 도형 데이터 검증
    private func validateSingleShape(_ shape: ShapeModel) -> Bool {
        // ID 검증
        if shape.id.uuidString.isEmpty {
            return false
        }
        
        // 제목 검증
        if shape.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        
        // 좌표 검증
        if !isValidCoordinate(shape.baseCoordinate) {
            return false
        }
        
        // 도형 타입별 검증
        switch shape.shapeType {
        case .circle:
            if let radius = shape.radius, radius <= 0 || radius > 50000 { // 50km 제한
                return false
            }
        case .rectangle:
            if let secondCoord = shape.secondCoordinate,
               !isValidCoordinate(secondCoord) {
                return false
            }
        case .polygon:
            if let coords = shape.polygonCoordinates {
                if coords.count < 3 || coords.count > 1000 || !coords.allSatisfy(isValidCoordinate) {
                    return false
                }
            }
        case .polyline:
            if let coords = shape.polylineCoordinates {
                if coords.count < 2 || coords.count > 1000 || !coords.allSatisfy(isValidCoordinate) {
                    return false
                }
            }
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
    
    /// 로컬 색상과 파이어스토어 색상을 동기화 (서버 색상으로 통일)
    private func synchronizeColorsWithLocal(_ firebaseShapes: [ShapeModel]) async -> [ShapeModel] {
        // 색상은 서버 기준으로 항상 통일하여 다른 디바이스에도 동일하게 반영
        let activeShapes = firebaseShapes.filter { $0.deletedAt == nil }
        guard let firstActiveShape = activeShapes.first else {
            print("📝 활성 도형이 없음: 색상 통일 불필요")
            return firebaseShapes
        }
        let unifiedColor = firstActiveShape.color
        print("🎨 서버 활성 도형 색상(소스 오브 트루스): \(unifiedColor)")

        var updatedShapes = firebaseShapes
        for i in 0..<updatedShapes.count {
            if updatedShapes[i].deletedAt == nil {
                updatedShapes[i].color = unifiedColor
            }
        }

        if let serverColor = PaletteColor.allCases.first(where: { $0.hex.lowercased() == unifiedColor.lowercased() }) {
            await MainActor.run {
                ColorManager.shared.defaultColor = serverColor
                print("🔄 로컬 기본 색상을 서버 색상으로 업데이트: \(serverColor.rawValue)")
            }
        }

        return updatedShapes
    }
    

    
    /// 파이어스토어의 도형 색상을 일괄 업데이트
    private func updateFirebaseShapesColors(_ shapes: [ShapeModel]) async {
        do {
            guard let collection = self.userCollection else {
                print("❌ 사용자 컬렉션에 접근할 수 없습니다.")
                return
            }
            
            let batch = self.db.batch()
            var updateCount = 0
            
            for shape in shapes {
                let docRef = collection.document(shape.id.uuidString)
                let colorData: [String: Any] = ["color": shape.color]
                batch.updateData(colorData, forDocument: docRef)
                updateCount += 1
            }
            
            try await batch.commit()
            print("✅ 파이어스토어 색상 업데이트 완료: \(updateCount)개 도형")
            
        } catch {
            print("❌ 파이어스토어 색상 업데이트 실패: \(error)")
        }
    }
}

// MARK: - Shape Firebase Error
enum ShapeFirebaseError: LocalizedError {
    case notAuthenticated
    case invalidData
    case unknownError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "사용자가 인증되지 않았습니다."
        case .invalidData:
            return "잘못된 데이터 형식입니다."
        case .unknownError:
            return "알 수 없는 오류가 발생했습니다."
        }
    }
}

// MARK: - Array Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
} 


 
