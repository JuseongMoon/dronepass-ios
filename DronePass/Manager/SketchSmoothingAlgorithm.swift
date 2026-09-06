//
//  SketchSmoothingAlgorithm.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 선 스무딩 알고리즘
// 연관기능: SketchManager → 스케치 완료 시 선 다듬기

import Foundation

/// 스케치 선 스무딩 알고리즘
struct SketchSmoothingAlgorithm {

    // MARK: - Public Methods

    /// 포인트 개수에 따른 최적 세그먼트 수 계산
    /// - Parameter pointCount: 원본 포인트 개수
    /// - Returns: 최적 보간 포인트 개수
    static func calculateOptimalSegments(for pointCount: Int) -> Int {
        switch pointCount {
        case 100...:
            return 5    // 긴 스케치: 보간 줄여 성능 최적화
        case 50..<100:
            return 7    // 중간 스케치
        default:
            return 10   // 짧은 스케치: 부드러움 유지
        }
    }

    /// Catmull-Rom 스플라인을 사용하여 포인트 스무딩
    /// - Parameters:
    ///   - points: 원본 좌표 배열
    ///   - segmentsPerOriginal: 각 원본 선분 사이에 생성할 보간 포인트 개수 (nil이면 자동 계산)
    /// - Returns: 스무딩된 좌표 배열
    static func smoothUsingCatmullRom(
        _ points: [CoordinateManager],
        segmentsPerOriginal: Int? = nil
    ) -> [CoordinateManager] {
        // 세그먼트 수 결정: 명시적 지정 또는 포인트 개수 기반 자동 계산
        let segments = segmentsPerOriginal ?? calculateOptimalSegments(for: points.count)
        // 포인트가 2개 미만이면 그대로 반환
        guard points.count >= 2 else { return points }

        // 보간 개수가 0 이하면 그대로 반환
        guard segments > 0 else { return points }

        // 2개 포인트인 경우 선형 보간
        if points.count == 2 {
            return linearInterpolate(points[0], points[1], segments: segments)
        }

        // 3개 이상: Catmull-Rom 스플라인 적용
        // 가상 끝점 추가 (첫 포인트 앞, 마지막 포인트 뒤)
        let virtualStart = createVirtualStart(points)
        let virtualEnd = createVirtualEnd(points)

        var extendedPoints = [virtualStart]
        extendedPoints.append(contentsOf: points)
        extendedPoints.append(virtualEnd)

        var smoothedPoints: [CoordinateManager] = []

        // 각 원본 선분에 대해 보간
        // extendedPoints: [v0, p0, p1, p2, ..., pn, vn+1]
        // 실제 포인트는 인덱스 1부터 count-2까지
        for i in 1..<(extendedPoints.count - 2) {
            let p0 = extendedPoints[i - 1]
            let p1 = extendedPoints[i]
            let p2 = extendedPoints[i + 1]
            let p3 = extendedPoints[i + 2]

            // 첫 번째 원본 포인트 추가
            if i == 1 {
                smoothedPoints.append(p1)
            }

            // 보간 포인트 생성 (p1에서 p2 사이)
            for j in 1...segments {
                let t = Double(j) / Double(segments)
                let interpolated = catmullRomInterpolate(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
                smoothedPoints.append(interpolated)
            }
        }

        return smoothedPoints
    }

    // MARK: - Private Methods

    /// Catmull-Rom 스플라인 보간
    /// - Parameters:
    ///   - p0: 이전 포인트 (p1 앞)
    ///   - p1: 시작 포인트
    ///   - p2: 끝 포인트
    ///   - p3: 다음 포인트 (p2 뒤)
    ///   - t: 보간 진행도 (0.0 ~ 1.0, p1에서 p2로)
    /// - Returns: 보간된 좌표
    private static func catmullRomInterpolate(
        p0: CoordinateManager,
        p1: CoordinateManager,
        p2: CoordinateManager,
        p3: CoordinateManager,
        t: Double
    ) -> CoordinateManager {
        let t2 = t * t
        let t3 = t2 * t

        // Catmull-Rom 공식 (tension = 0.5)
        // Q(t) = 0.5 * [2*P1 + (-P0+P2)*t + (2*P0-5*P1+4*P2-P3)*t² + (-P0+3*P1-3*P2+P3)*t³]

        let latValue = 0.5 * (
            2.0 * p1.latitude +
            (-p0.latitude + p2.latitude) * t +
            (2.0 * p0.latitude - 5.0 * p1.latitude + 4.0 * p2.latitude - p3.latitude) * t2 +
            (-p0.latitude + 3.0 * p1.latitude - 3.0 * p2.latitude + p3.latitude) * t3
        )

        let lonValue = 0.5 * (
            2.0 * p1.longitude +
            (-p0.longitude + p2.longitude) * t +
            (2.0 * p0.longitude - 5.0 * p1.longitude + 4.0 * p2.longitude - p3.longitude) * t2 +
            (-p0.longitude + 3.0 * p1.longitude - 3.0 * p2.longitude + p3.longitude) * t3
        )

        return CoordinateManager(latitude: latValue, longitude: lonValue)
    }

    /// 첫 번째 포인트 앞의 가상 포인트 생성
    /// 기울기를 유지하여 자연스러운 시작점 생성
    private static func createVirtualStart(_ points: [CoordinateManager]) -> CoordinateManager {
        guard points.count >= 2 else {
            return points[0]
        }

        let p0 = points[0]
        let p1 = points[1]

        // p0를 중심으로 p1의 반대편 (p0에서 p0-p1 방향으로 같은 거리)
        return CoordinateManager(
            latitude: p0.latitude * 2 - p1.latitude,
            longitude: p0.longitude * 2 - p1.longitude
        )
    }

    /// 마지막 포인트 뒤의 가상 포인트 생성
    /// 기울기를 유지하여 자연스러운 끝점 생성
    private static func createVirtualEnd(_ points: [CoordinateManager]) -> CoordinateManager {
        guard points.count >= 2 else {
            return points[points.count - 1]
        }

        let pLast = points[points.count - 1]
        let pPrev = points[points.count - 2]

        // pLast를 중심으로 pPrev의 반대편
        return CoordinateManager(
            latitude: pLast.latitude * 2 - pPrev.latitude,
            longitude: pLast.longitude * 2 - pPrev.longitude
        )
    }

    /// 선형 보간 (2개 포인트인 경우)
    private static func linearInterpolate(
        _ p1: CoordinateManager,
        _ p2: CoordinateManager,
        segments: Int
    ) -> [CoordinateManager] {
        var result = [p1]

        for i in 1...segments {
            let t = Double(i) / Double(segments)
            result.append(
                CoordinateManager(
                    latitude: p1.latitude + (p2.latitude - p1.latitude) * t,
                    longitude: p1.longitude + (p2.longitude - p1.longitude) * t
                )
            )
        }

        return result
    }
}
