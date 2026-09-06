//
//  SketchModel.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 데이터 모델
// 연관기능: 지도 위 자유 그리기, 로컬/Firebase 저장

import Foundation
import CoreLocation

/// 스케치 데이터 모델
/// 지도 위에 자유롭게 그린 선(polyline)을 저장합니다.
public struct SketchModel: Codable, Identifiable, Equatable {
    public let id: UUID                         // 스케치 고유 식별자
    public var points: [CoordinateManager]      // 자유 그리기 좌표 배열 (원본, 저장용)
    public var color: String                    // 색상 (hex 코드)
    public var strokeWidth: Double              // 선 두께
    public var opacity: Double                  // 투명도 (0.0 ~ 1.0)
    public var createdAt: Date                  // 생성 시간
    public var updatedAt: Date                  // 수정 시간
    public var deletedAt: Date?                 // 삭제 시간 (soft delete)

    // 스무딩된 포인트 (렌더링용, Codable 제외 - 메모리에만 캐싱)
    public var smoothedPoints: [CoordinateManager]?

    /// 렌더링용 포인트 반환 (스무딩 적용)
    /// 우선순위: 1) 인스턴스 캐시 2) LRU 캐시 3) 실시간 계산
    public var displayPoints: [CoordinateManager] {
        // 1. 인스턴스에 캐싱된 값이 있으면 사용 (새로 생성된 스케치)
        if let smoothed = smoothedPoints {
            return smoothed
        }
        // 2. 포인트가 2개 미만이면 원본 반환
        guard points.count >= 2 else { return points }
        // 3. LRU 캐시에서 조회 또는 계산 (기존 스케치 렌더링)
        return SketchPointsCache.shared.getSmoothedPoints(for: self)
    }

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        points: [CoordinateManager] = [],
        color: String = "#FF0000",
        strokeWidth: Double = 3.0,
        opacity: Double = 1.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        smoothedPoints: [CoordinateManager]? = nil
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.smoothedPoints = smoothedPoints
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, points, color, strokeWidth, opacity
        case createdAt, updatedAt, deletedAt
    }

    // MARK: - Custom Decoding (호환성)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        points = try container.decodeIfPresent([CoordinateManager].self, forKey: .points) ?? []
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#FF0000"
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 3.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0

        // 날짜 필드들 - 안전한 디코딩
        if let existingCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = existingCreatedAt
        } else {
            createdAt = Date()
        }

        if let existingUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            updatedAt = existingUpdatedAt
        } else {
            updatedAt = createdAt
        }

        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)

        // smoothedPoints는 Codable에 포함되지 않음 (렌더링 시 실시간 생성)
        smoothedPoints = nil
    }

    // MARK: - Custom Encoding

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(points, forKey: .points)
        try container.encode(color, forKey: .color)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    // MARK: - Computed Properties

    /// 삭제된 스케치인지 확인
    public var isDeleted: Bool {
        return deletedAt != nil
    }

    /// 스케치에 포인트가 있는지 확인
    public var hasPoints: Bool {
        return !points.isEmpty
    }

    /// 포인트 개수
    public var pointCount: Int {
        return points.count
    }

    // MARK: - Equatable (smoothedPoints 제외)

    public static func == (lhs: SketchModel, rhs: SketchModel) -> Bool {
        return lhs.id == rhs.id &&
               lhs.points == rhs.points &&
               lhs.color == rhs.color &&
               lhs.strokeWidth == rhs.strokeWidth &&
               lhs.opacity == rhs.opacity &&
               lhs.createdAt == rhs.createdAt &&
               lhs.updatedAt == rhs.updatedAt &&
               lhs.deletedAt == rhs.deletedAt
        // smoothedPoints는 비교에서 제외 (캐시 데이터이므로)
    }
}
