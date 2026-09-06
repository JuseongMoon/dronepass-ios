//
//  AnalyticsDataGenerator.swift
//  DronePass
//
//  Created by Claude on 2025-10-02.
//

import Foundation
import FirebaseFirestore

/// 회원 탈퇴 시 익명화 데이터 생성을 담당하는 클래스
@MainActor
final class AnalyticsDataGenerator {

    static let shared = AnalyticsDataGenerator()

    private init() {}

    // MARK: - User Data Generation

    /// 사용자 통계 생성 (email 제외)
    func generateAnonymizedUserData(user: User?) -> [String: Any] {
        var data: [String: Any] = [
            "deletedAt": Timestamp(date: Date()),
            "totalShapesCreated": ShapeFileStore.shared.shapes.count,
            "cloudSyncEnabled": SettingManager.shared.isCloudBackupEnabled,
            "devicePlatform": "iOS"
        ]

        // 계정 생성일 추가
        if let createdAt = user?.createdAt {
            data["accountCreatedAt"] = Timestamp(date: createdAt)
        }

        // 드론 수 계산 (삭제되지 않은 드론만)
        let activeDrones = DroneManager.shared.drones.filter { !$0.isDeleted }
        data["totalDronesUsed"] = activeDrones.count

        // 도형 타입 분포 계산
        let shapes = ShapeFileStore.shared.shapes
        data["shapeTypeDistribution"] = calculateShapeTypeDistribution(shapes)

        return data
    }

    // MARK: - Shape Data Generation

    /// 도형 데이터 변환 (모든 필드 원본 그대로)
    func generateShapeData(_ shapes: [ShapeModel]) -> [[String: Any]] {
        return shapes.compactMap { shape in
            return shapeToFirestoreData(shape)
        }
    }

    /// ShapeModel을 Firestore 데이터로 변환 (모든 필드 포함)
    private func shapeToFirestoreData(_ shape: ShapeModel) -> [String: Any] {
        var data: [String: Any] = [
            "id": shape.id.uuidString,
            "title": shape.title,
            "shapeType": shape.shapeType.rawValue,
            "baseCoordinate": [
                "latitude": shape.baseCoordinate.latitude,
                "longitude": shape.baseCoordinate.longitude
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

        // droneId 추가 (있는 경우에만)
        if let droneId = shape.droneId {
            data["droneId"] = droneId
        }

        // 추가 도형 데이터
        if let radius = shape.radius {
            data["radius"] = radius
        }

        if let secondCoordinate = shape.secondCoordinate {
            data["secondCoordinate"] = [
                "latitude": secondCoordinate.latitude,
                "longitude": secondCoordinate.longitude
            ]
        }

        if let polygonCoordinates = shape.polygonCoordinates {
            data["polygonCoordinates"] = polygonCoordinates.map { coord in
                [
                    "latitude": coord.latitude,
                    "longitude": coord.longitude
                ]
            }
        }

        if let polylineCoordinates = shape.polylineCoordinates {
            data["polylineCoordinates"] = polylineCoordinates.map { coord in
                [
                    "latitude": coord.latitude,
                    "longitude": coord.longitude
                ]
            }
        }

        return data
    }

    // MARK: - Drone Data Generation

    /// 드론 데이터 변환 (모든 필드 원본 그대로)
    func generateDroneData(_ drones: [DroneModel]) -> [[String: Any]] {
        return drones.map { drone in
            return droneToFirestoreData(drone)
        }
    }

    /// DroneModel을 Firestore 데이터로 변환 (모든 필드 포함)
    private func droneToFirestoreData(_ drone: DroneModel) -> [String: Any] {
        var data: [String: Any] = [
            "id": drone.id,
            "name": drone.name,
            "color": drone.color,
            "createdAt": Timestamp(date: drone.createdAt),
            "updatedAt": Timestamp(date: drone.updatedAt),
            "isDeleted": drone.isDeleted
        ]

        // deletedAt이 있는 경우에만 추가
        if let deletedAt = drone.deletedAt {
            data["deletedAt"] = Timestamp(date: deletedAt)
        }

        return data
    }

    // MARK: - Helper Methods

    /// 도형 타입 분포 계산
    func calculateShapeTypeDistribution(_ shapes: [ShapeModel]) -> [String: Int] {
        var distribution: [String: Int] = [:]

        for shape in shapes {
            let typeKey = shape.shapeType.rawValue
            distribution[typeKey, default: 0] += 1
        }

        return distribution
    }
}
