//
//  FlightZoneCalculator.swift
//  DronePass
//
//  드론 비행 가능 여부 판정 로직
//

import Foundation
import CoreLocation

// MARK: - 비행 허가 결과

/// 비행 허가 판정 결과
struct FlightPermissionResult {
    let isAllowed: Bool                          // 비행 가능 여부
    let restrictionLevel: FlightRestrictionLevel // 제한 레벨
    let affectedZones: [DroneZoneFeature]        // 영향받는 구역들
    let message: String                          // 사용자 메시지
    let details: [String]                        // 상세 정보

    /// 비행 불가 결과 생성
    static func denied(zones: [DroneZoneFeature], reason: String) -> FlightPermissionResult {
        let level: FlightRestrictionLevel = zones.contains { $0.layer.restrictionLevel == .prohibited } ? .prohibited : .restricted
        let details = zones.map { "\($0.layer.displayName): \($0.name ?? String(localized: "flightzone.name.unknown"))" }

        return FlightPermissionResult(
            isAllowed: false,
            restrictionLevel: level,
            affectedZones: zones,
            message: reason,
            details: details
        )
    }

    /// 비행 가능 결과 생성
    static func allowed(message: String? = nil) -> FlightPermissionResult {
        return FlightPermissionResult(
            isAllowed: true,
            restrictionLevel: .advisory,
            affectedZones: [],
            message: message ?? String(localized: "flightzone.allowed"),
            details: []
        )
    }

    /// 주의 권고 결과 (문화재, 공원 등)
    static func advisory(zones: [DroneZoneFeature]) -> FlightPermissionResult {
        let details = zones.map { "\($0.layer.displayName): \($0.name ?? String(localized: "flightzone.name.unknown"))" }

        return FlightPermissionResult(
            isAllowed: true,
            restrictionLevel: .advisory,
            affectedZones: zones,
            message: String(localized: "flightzone.advisory"),
            details: details
        )
    }
}

// MARK: - 비행 구역 계산기

/// 드론 비행 가능 여부를 계산하는 클래스
final class FlightZoneCalculator {

    // MARK: - Public Methods

    /// 특정 좌표에서 비행 가능 여부 판정
    /// - Parameters:
    ///   - coordinate: 확인할 좌표
    ///   - zones: 확인할 구역 데이터 (레이어별)
    ///   - altitude: 비행 고도 (미터, 기본값 120m)
    /// - Returns: 비행 허가 판정 결과
    func checkFlightPermission(
        at coordinate: CLLocationCoordinate2D,
        zones: [FlightZoneLayer: [DroneZoneFeature]],
        altitude: Double = 120.0
    ) -> FlightPermissionResult {

        var prohibitedZones: [DroneZoneFeature] = []  // 비행금지
        var restrictedZones: [DroneZoneFeature] = []  // 비행제한
        var advisoryZones: [DroneZoneFeature] = []    // 주의권고

        // 모든 구역을 순회하며 포함 여부 확인
        for (layer, features) in zones {
            for feature in features {
                if isCoordinateInside(coordinate, feature: feature) {
                    // 제한 레벨에 따라 분류
                    switch layer.restrictionLevel {
                    case .prohibited:
                        prohibitedZones.append(feature)
                    case .restricted, .consultation:
                        restrictedZones.append(feature)
                    case .advisory:
                        advisoryZones.append(feature)
                    }
                }
            }
        }

        // 판정 로직
        if !prohibitedZones.isEmpty {
            // 비행금지구역이 하나라도 있으면 비행 불가
            let layerNames = prohibitedZones.map { $0.layer.displayName }.joined(separator: ", ")
            return .denied(
                zones: prohibitedZones,
                reason: String(format: String(localized: "flightzone.prohibited"), layerNames)
            )
        } else if !restrictedZones.isEmpty {
            // 비행제한구역이 있으면 승인 필요
            let layerNames = restrictedZones.map { $0.layer.displayName }.joined(separator: ", ")
            return .denied(
                zones: restrictedZones,
                reason: String(format: String(localized: "flightzone.restricted"), layerNames)
            )
        } else if !advisoryZones.isEmpty {
            // 주의권고 구역 (비행은 가능)
            return .advisory(zones: advisoryZones)
        } else {
            // 모든 검사 통과
            return .allowed()
        }
    }

    /// 특정 좌표가 Feature 내부에 있는지 확인
    /// - Parameters:
    ///   - coordinate: 확인할 좌표
    ///   - feature: 구역 Feature
    /// - Returns: 포함 여부
    func isCoordinateInside(_ coordinate: CLLocationCoordinate2D, feature: DroneZoneFeature) -> Bool {
        let polygons = feature.extractCoordinates()

        for polygon in polygons {
            // 첫 번째 ring (외부 경계)만 체크
            // TODO: 추후 hole (내부 경계) 처리 추가 가능
            if let outerRing = polygon.first {
                if isPointInPolygon(point: coordinate, polygon: outerRing) {
                    return true
                }
            }
        }

        return false
    }

    /// Ray Casting 알고리즘으로 점-폴리곤 포함 여부 판정
    /// - Parameters:
    ///   - point: 확인할 점
    ///   - polygon: 폴리곤 좌표 배열
    /// - Returns: 포함 여부
    func isPointInPolygon(point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var intersections = 0
        let n = polygon.count

        for i in 0..<n {
            let j = (i + 1) % n
            let pi = polygon[i]
            let pj = polygon[j]

            // Ray casting: 점에서 오른쪽으로 수평선을 그었을 때 교차 횟수 계산
            if ((pi.latitude > point.latitude) != (pj.latitude > point.latitude)) &&
               (point.longitude < (pj.longitude - pi.longitude) * (point.latitude - pi.latitude) / (pj.latitude - pi.latitude) + pi.longitude) {
                intersections += 1
            }
        }

        // 교차 횟수가 홀수면 내부, 짝수면 외부
        return intersections % 2 == 1
    }

    /// 특정 반경 내 모든 구역 찾기
    /// - Parameters:
    ///   - coordinate: 중심 좌표
    ///   - radius: 반경 (미터)
    ///   - zones: 검색할 구역 데이터
    /// - Returns: 반경 내 구역 목록
    func findZonesNearby(
        coordinate: CLLocationCoordinate2D,
        radius: Double,
        zones: [FlightZoneLayer: [DroneZoneFeature]]
    ) -> [DroneZoneFeature] {

        var nearbyZones: [DroneZoneFeature] = []

        for (_, features) in zones {
            for feature in features {
                if isFeatureNearby(coordinate: coordinate, radius: radius, feature: feature) {
                    nearbyZones.append(feature)
                }
            }
        }

        // 중요도 순으로 정렬
        nearbyZones.sort { $0.layer.priority < $1.layer.priority }

        return nearbyZones
    }

    /// Feature가 특정 좌표 반경 내에 있는지 확인
    /// - Parameters:
    ///   - coordinate: 중심 좌표
    ///   - radius: 반경 (미터)
    ///   - feature: 확인할 Feature
    /// - Returns: 반경 내 여부
    func isFeatureNearby(coordinate: CLLocationCoordinate2D, radius: Double, feature: DroneZoneFeature) -> Bool {
        let polygons = feature.extractCoordinates()

        for polygon in polygons {
            for ring in polygon {
                for vertex in ring {
                    let distance = coordinate.distance(to: vertex)
                    if distance <= radius {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// BoundingBox 생성 (특정 좌표 주변)
    /// - Parameters:
    ///   - coordinate: 중심 좌표
    ///   - radiusMeters: 반경 (미터)
    /// - Returns: (minLon, minLat, maxLon, maxLat)
    func createBoundingBox(
        around coordinate: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {

        // 지구 반경 (미터)
        let earthRadius = 6378137.0

        // 위도 1도당 거리 (약 111km)
        let latDelta = (radiusMeters / earthRadius) * (180.0 / .pi)

        // 경도 1도당 거리 (위도에 따라 변화)
        let lonDelta = latDelta / cos(coordinate.latitude * .pi / 180.0)

        return (
            minLon: coordinate.longitude - lonDelta,
            minLat: coordinate.latitude - latDelta,
            maxLon: coordinate.longitude + lonDelta,
            maxLat: coordinate.latitude + latDelta
        )
    }
}

// MARK: - CLLocationCoordinate2D Extensions

extension CLLocationCoordinate2D {
    /// 두 좌표 간 거리 계산 (Haversine 공식)
    /// - Parameter other: 비교 대상 좌표
    /// - Returns: 거리 (미터)
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6378137.0  // 지구 반경 (미터)

        let lat1 = self.latitude * .pi / 180.0
        let lon1 = self.longitude * .pi / 180.0
        let lat2 = other.latitude * .pi / 180.0
        let lon2 = other.longitude * .pi / 180.0

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat / 2.0) * sin(dLat / 2.0) +
                cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))

        return earthRadius * c
    }
}
