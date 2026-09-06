//
//  DistanceCalculator.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 지리적 거리 계산 유틸리티
// 연관기능: 스케치 → 좌표 샘플링, 지우개 모드 충돌 검사

import Foundation

/// 지리적 거리 계산 유틸리티
struct DistanceCalculator {

    /// 지구 반지름 (미터)
    private static let earthRadius: Double = 6371000

    // MARK: - Public Methods

    /// Haversine 공식으로 두 좌표 간 거리 계산 (정확한 거리)
    /// - Parameters:
    ///   - lat1: 첫 번째 좌표 위도
    ///   - lon1: 첫 번째 좌표 경도
    ///   - lat2: 두 번째 좌표 위도
    ///   - lon2: 두 번째 좌표 경도
    /// - Returns: 거리 (미터)
    static func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180

        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return earthRadius * c
    }

    /// Equirectangular 근사로 빠른 거리 계산 (짧은 거리용)
    /// Haversine 대비 약 3배 빠름, 50km 이내에서 정확도 우수
    /// - Parameters:
    ///   - lat1: 첫 번째 좌표 위도
    ///   - lon1: 첫 번째 좌표 경도
    ///   - lat2: 두 번째 좌표 위도
    ///   - lon2: 두 번째 좌표 경도
    /// - Returns: 거리 (미터)
    static func fastApprox(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let avgLat = (lat1 + lat2) / 2.0 * .pi / 180

        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180

        let x = dLon * cos(avgLat)
        let y = dLat

        return earthRadius * sqrt(x * x + y * y)
    }

    /// 점에서 선분까지의 최단 거리 (미터)
    /// - Parameters:
    ///   - point: 기준 점
    ///   - segmentStart: 선분 시작점
    ///   - segmentEnd: 선분 끝점
    /// - Returns: 거리 (미터)
    static func toSegment(
        point: CoordinateManager,
        segmentStart: CoordinateManager,
        segmentEnd: CoordinateManager
    ) -> Double {
        let pX = point.longitude
        let pY = point.latitude
        let aX = segmentStart.longitude
        let aY = segmentStart.latitude
        let bX = segmentEnd.longitude
        let bY = segmentEnd.latitude

        let abX = bX - aX
        let abY = bY - aY
        let apX = pX - aX
        let apY = pY - aY

        let abSquared = abX * abX + abY * abY

        // 선분 길이가 0인 경우 (시작점 = 끝점)
        if abSquared == 0 {
            return haversine(lat1: pY, lon1: pX, lat2: aY, lon2: aX)
        }

        // 투영 비율 t 계산 후 [0, 1]로 클램프
        var t = (apX * abX + apY * abY) / abSquared
        t = max(0, min(1, t))

        // 선분 위의 가장 가까운 점
        let closestLon = aX + t * abX
        let closestLat = aY + t * abY

        return haversine(lat1: pY, lon1: pX, lat2: closestLat, lon2: closestLon)
    }

    // MARK: - Convenience Methods (CoordinateManager 버전)

    /// 두 좌표 간 Haversine 거리
    static func haversine(from: CoordinateManager, to: CoordinateManager) -> Double {
        return haversine(lat1: from.latitude, lon1: from.longitude, lat2: to.latitude, lon2: to.longitude)
    }

    /// 두 좌표 간 빠른 근사 거리
    static func fastApprox(from: CoordinateManager, to: CoordinateManager) -> Double {
        return fastApprox(lat1: from.latitude, lon1: from.longitude, lat2: to.latitude, lon2: to.longitude)
    }
}
