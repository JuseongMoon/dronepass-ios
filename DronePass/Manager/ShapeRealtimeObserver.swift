//
//  ShapeRealtimeObserver.swift
//  DronePass
//
//  Created by 문주성 on 1/29/25.
//

import Foundation
import FirebaseFirestore
import Combine

/// 개별 도형에 대한 실시간 변경 감지 및 충돌 해결을 관리하는 클래스
@MainActor
final class ShapeRealtimeObserver: ObservableObject {
    
    @Published var shape: ShapeModel
    @Published var isEditing: Bool = false
    @Published var hasRemoteChanges: Bool = false
    
    private let db = Firestore.firestore()
    private var shapeListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    
    // 편집 중인 필드 추적 (충돌 해결용)
    private var editingFields: Set<String> = []
    private var lastEditTimes: [String: Date] = [:]
    
    init(shape: ShapeModel) {
        self.shape = shape
        setupRealtimeListener()
    }
    
    deinit {
        // deinit은 nonisolated이므로 리스너를 직접 제거
        shapeListener?.remove()
        shapeListener = nil
    }
    
    /// 실시간 리스너 설정
    private func setupRealtimeListener() {
        guard AppleLoginManager.shared.isLogin,
              SettingManager.shared.isCloudBackupEnabled,
              let userId = AuthManager.shared.currentAuthUser?.uid else {
            print("📝 도형 실시간 감지 조건 미충족")
            return
        }
        
        let shapeRef = db.collection("users").document(userId).collection("shapes").document(shape.id.uuidString)
        
        shapeListener = shapeRef.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ 도형 실시간 감지 오류: \(error.localizedDescription)")
                return
            }
            
            guard let document = documentSnapshot, document.exists,
                  let data = document.data() else {
                print("📝 도형 문서가 존재하지 않습니다: \(self.shape.id)")
                return
            }
            
            do {
                        let updatedShape = try self.parseShapeFromDocument(data, id: document.documentID)
                
                // 현재 편집 중이 아닌 경우에만 실시간 업데이트
                if !self.isEditing {
                    DispatchQueue.main.async {
                        let oldShape = self.shape
                        self.shape = updatedShape
                        self.hasRemoteChanges = false
                        print("✅ 도형 실시간 업데이트: \(updatedShape.title)")
                        
                        // 색상이 변경된 경우 지도 오버레이 즉시 업데이트
                        if oldShape.color != updatedShape.color {
                            print("🎨 실시간 색상 변경 감지: \(oldShape.color) → \(updatedShape.color)")
                            
                            // 지도 오버레이 리로드 알림
                            NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
                            
                            // 도형 변경 알림도 함께 전송하여 모든 뷰 업데이트 보장
                            NotificationCenter.default.post(name: .shapesDidChange, object: nil)
                            
                            // 추가 지연 없이 즉시 처리하기 위한 추가 알림들
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
                            }
                        }
                        
                        // FlightEndDate가 변경된 경우 저장 목록 즉시 업데이트
                        if oldShape.flightEndDate != updatedShape.flightEndDate {
                            print("📅 실시간 만료일 변경 감지: \(oldShape.flightEndDate?.description ?? "nil") → \(updatedShape.flightEndDate?.description ?? "nil")")
                            NotificationCenter.default.post(name: .shapesDidChange, object: nil)
                        }
                        
                        // 만료 상태가 변경된 경우에도 저장 목록 업데이트
                        let oldIsExpired = oldShape.isExpired
                        let newIsExpired = updatedShape.isExpired
                        if oldIsExpired != newIsExpired {
                            print("📅 실시간 만료 상태 변경 감지: \(oldIsExpired) → \(newIsExpired)")
                            NotificationCenter.default.post(name: .shapesDidChange, object: nil)
                        }
                        
                        // updatedAt이 더 최신인 경우 서버 값 우선 반영 (LWW)
                        if updatedShape.updatedAt > oldShape.updatedAt {
                            print("🕒 실시간 업데이트: 서버 updatedAt이 더 최신 → 서버 값 유지")
                        }
                    }
                } else {
                    // 편집 중인 경우 변경사항이 있음을 표시만 하고 실제 업데이트는 하지 않음
                    if self.hasShapeChanged(from: self.shape, to: updatedShape) {
                        DispatchQueue.main.async {
                            self.hasRemoteChanges = true
                            print("📝 편집 중 원격 변경사항 감지: \(updatedShape.title)")
                        }
                    }
                }
                
            } catch {
                print("❌ 도형 파싱 실패: \(error)")
            }
        }
        
        print("🔍 도형 실시간 감지 시작: \(shape.title)")
    }
    
    /// 실시간 감지 중지
    func stopObserving() {
        shapeListener?.remove()
        shapeListener = nil
        print("🛑 도형 실시간 감지 중지: \(shape.title)")
    }
    
    /// 편집 모드 시작
    func startEditing() {
        isEditing = true
        editingFields.removeAll()
        lastEditTimes.removeAll()
        print("✏️ 편집 모드 시작: \(shape.title)")
    }
    
    /// 편집 모드 종료
    func stopEditing() {
        isEditing = false
        editingFields.removeAll()
        lastEditTimes.removeAll()
        hasRemoteChanges = false
        print("📝 편집 모드 종료: \(shape.title)")
    }
    
    /// 특정 필드 편집 시작 (충돌 해결용)
    func startEditingField(_ fieldName: String) {
        editingFields.insert(fieldName)
        lastEditTimes[fieldName] = Date()
        print("🖊️ 필드 편집 시작: \(fieldName)")
    }
    
    /// 특정 필드 편집 완료 (충돌 해결용)
    func finishEditingField(_ fieldName: String) {
        editingFields.remove(fieldName)
        lastEditTimes[fieldName] = Date()
        print("✅ 필드 편집 완료: \(fieldName)")
    }
    
    /// 편집된 도형과 원격 변경사항을 병합하여 충돌 해결
    func resolveConflictsAndSave(editedShape: ShapeModel) async throws -> ShapeModel {
        guard hasRemoteChanges else {
            // 원격 변경사항이 없으면 그대로 저장
            return editedShape
        }
        
        print("🔀 충돌 해결 시작...")
        
        // 최신 원격 데이터 가져오기
        guard let userId = AuthManager.shared.currentAuthUser?.uid else {
            throw ConflictResolutionError.authenticationRequired
        }
        
        let shapeRef = db.collection("users").document(userId).collection("shapes").document(shape.id.uuidString)
        let document = try await shapeRef.getDocument()
        
        guard document.exists, let data = document.data() else {
            throw ConflictResolutionError.shapeNotFound
        }
        
        let remoteShape = try parseShapeFromDocument(data, id: document.documentID)
        
        // 필드별 충돌 해결
        let resolvedShape = resolveFieldConflicts(
            editedShape: editedShape,
            remoteShape: remoteShape,
            originalShape: self.shape
        )
        
        print("✅ 충돌 해결 완료")
        return resolvedShape
    }
    
    /// 필드별 충돌 해결 로직
    private func resolveFieldConflicts(
        editedShape: ShapeModel,
        remoteShape: ShapeModel,
        originalShape: ShapeModel
    ) -> ShapeModel {
        
        var resolvedShape = editedShape
        
        // 각 필드별로 충돌 해결
        resolvedShape.title = resolveFieldConflict(
            fieldName: "title",
            editedValue: editedShape.title,
            remoteValue: remoteShape.title,
            originalValue: originalShape.title
        )
        
        resolvedShape.memo = resolveFieldConflict(
            fieldName: "memo",
            editedValue: editedShape.memo,
            remoteValue: remoteShape.memo,
            originalValue: originalShape.memo
        )
        
        resolvedShape.address = resolveFieldConflict(
            fieldName: "address",
            editedValue: editedShape.address,
            remoteValue: remoteShape.address,
            originalValue: originalShape.address
        )
        
        // 날짜 필드들
        resolvedShape.flightStartDate = resolveFieldConflict(
            fieldName: "flightStartDate",
            editedValue: editedShape.flightStartDate,
            remoteValue: remoteShape.flightStartDate,
            originalValue: originalShape.flightStartDate
        )
        
        resolvedShape.flightEndDate = resolveFieldConflict(
            fieldName: "flightEndDate",
            editedValue: editedShape.flightEndDate,
            remoteValue: remoteShape.flightEndDate,
            originalValue: originalShape.flightEndDate
        )
        
        // 좌표와 도형 관련 필드들 (기하학적 데이터는 더 신중하게 처리)
        if hasEditedGeometry(editedShape: editedShape, originalShape: originalShape) {
            // 편집한 기기의 기하학적 데이터 우선
            print("🗺️ 기하학적 데이터 충돌: 편집한 기기 우선")
        } else {
            // 편집하지 않았다면 원격 데이터 적용
            resolvedShape.baseCoordinate = remoteShape.baseCoordinate
            resolvedShape.radius = remoteShape.radius
            resolvedShape.secondCoordinate = remoteShape.secondCoordinate
            resolvedShape.polygonCoordinates = remoteShape.polygonCoordinates
            resolvedShape.polylineCoordinates = remoteShape.polylineCoordinates
        }

        // 드론 ID 충돌 해결
        resolvedShape.droneId = resolveFieldConflict(
            fieldName: "droneId",
            editedValue: editedShape.droneId,
            remoteValue: remoteShape.droneId,
            originalValue: originalShape.droneId
        )

        // 드론 변경 시 색상도 업데이트
        if let droneId = resolvedShape.droneId,
           let drone = DroneManager.shared.getDrone(by: droneId) {
            resolvedShape.color = drone.color
            print("🎨 드론 변경에 따른 색상 업데이트: \(drone.name) (\(drone.color))")
        }

        // height 충돌 해결 (드론 비행 고도)
        resolvedShape.height = resolveFieldConflict(
            fieldName: "height",
            editedValue: editedShape.height,
            remoteValue: remoteShape.height,
            originalValue: originalShape.height
        )

        return resolvedShape
    }
    
    /// 개별 필드 충돌 해결
    private func resolveFieldConflict<T: Equatable>(
        fieldName: String,
        editedValue: T,
        remoteValue: T,
        originalValue: T
    ) -> T {
        
        // 현재 편집 중인 필드인지 확인
        if editingFields.contains(fieldName) {
            print("🖊️ 필드 '\(fieldName)' 편집 중 - 편집한 값 우선")
            return editedValue
        }
        
        // 편집한 값이 원본과 다르다면 편집한 값 우선
        if editedValue != originalValue {
            print("✏️ 필드 '\(fieldName)' 편집됨 - 편집한 값 우선")
            return editedValue
        }
        
        // 편집하지 않았다면 원격 값 적용
        if remoteValue != originalValue {
            print("🌐 필드 '\(fieldName)' 원격 변경 - 원격 값 적용")
            return remoteValue
        }
        
        // 둘 다 변경되지 않았다면 편집한 값 반환
        return editedValue
    }
    
    /// 기하학적 데이터가 편집되었는지 확인
    private func hasEditedGeometry(editedShape: ShapeModel, originalShape: ShapeModel) -> Bool {
        return editedShape.baseCoordinate.latitude != originalShape.baseCoordinate.latitude ||
               editedShape.baseCoordinate.longitude != originalShape.baseCoordinate.longitude ||
               editedShape.radius != originalShape.radius ||
               editedShape.secondCoordinate != originalShape.secondCoordinate ||
               editedShape.polygonCoordinates != originalShape.polygonCoordinates ||
               editedShape.polylineCoordinates != originalShape.polylineCoordinates
    }
    
    /// 도형이 변경되었는지 확인
    private func hasShapeChanged(from original: ShapeModel, to updated: ShapeModel) -> Bool {
        return original.title != updated.title ||
               original.memo != updated.memo ||
               original.address != updated.address ||
               original.flightStartDate != updated.flightStartDate ||
               original.flightEndDate != updated.flightEndDate ||
               original.baseCoordinate.latitude != updated.baseCoordinate.latitude ||
               original.baseCoordinate.longitude != updated.baseCoordinate.longitude ||
               original.radius != updated.radius ||
               original.height != updated.height
    }
    
    /// Firestore 데이터를 ShapeModel로 변환 (ShapeFirebaseStore의 로직과 동일)
    private func parseShapeFromDocument(_ data: [String: Any], id: String) throws -> ShapeModel {
        guard let idString = data["id"] as? String,
              let uuid = UUID(uuidString: idString),
              let title = data["title"] as? String,
              let shapeTypeString = data["shapeType"] as? String,
              let shapeType = DronePass.ShapeType(rawValue: shapeTypeString.lowercased()),
              let baseCoordData = data["baseCoordinate"] as? [String: Any],
              let baseLat = baseCoordData["latitude"] as? Double,
              let baseLng = baseCoordData["longitude"] as? Double,
              let color = data["color"] as? String else {
            throw ConflictResolutionError.invalidData
        }
        
        let baseCoordinate = CoordinateManager(latitude: baseLat, longitude: baseLng)
        let memo = data["memo"] as? String
        let address = data["address"] as? String
        
        // 날짜 필드들 읽기
        let flightStartDate: Date
        if let flightStartTimestamp = data["flightStartDate"] as? Timestamp {
            flightStartDate = flightStartTimestamp.dateValue()
        } else if let startedAtTimestamp = data["startedAt"] as? Timestamp {
            flightStartDate = startedAtTimestamp.dateValue()
        } else {
            throw ConflictResolutionError.invalidData
        }
        
        let flightEndDate: Date?
        if let flightEndTimestamp = data["flightEndDate"] as? Timestamp {
            flightEndDate = flightEndTimestamp.dateValue()
        } else {
            flightEndDate = (data["expireDate"] as? Timestamp)?.dateValue()
        }
        
        let createdAt: Date
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            createdAt = createdAtTimestamp.dateValue()
        } else {
            createdAt = flightStartDate
        }
        
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
}

// MARK: - 충돌 해결 에러
enum ConflictResolutionError: LocalizedError {
    case authenticationRequired
    case shapeNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return NSLocalizedString("error.auth.required", comment: "Authentication required.")
        case .shapeNotFound:
            return NSLocalizedString("error.shape.notFound", comment: "Shape not found.")
        case .invalidData:
            return NSLocalizedString("error.data.invalid", comment: "Invalid data format.")
        }
    }
}