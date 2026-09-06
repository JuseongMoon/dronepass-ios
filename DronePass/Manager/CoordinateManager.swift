//
//  Coordinate.swift
//  DronePass
//
//  Created by 문주성 on 5/13/25.
//

// 역할: GPS 좌표값을 관리하는 모델
// 연관기능: 지도 표시, 위치 검색, 도형 생성

import Foundation // Foundation 프레임워크를 가져옵니다. (기본적인 데이터 타입과 기능을 사용하기 위함)
import CoreLocation // CoreLocation 프레임워크를 가져옵니다. (위치 관련 기능을 사용하기 위함)
import NMapsMap // 네이버 지도 SDK를 가져옵니다. (지도 표시 기능을 사용하기 위함)

/// GPS 좌표값을 저장하는 모델
public struct CoordinateManager: Codable, Equatable { // GPS 좌표를 나타내는 구조체입니다. Codable과 Equatable 프로토콜을 준수합니다.
    public let latitude: Double // 위도 값입니다.
    public let longitude: Double // 경도 값입니다.

    public init(latitude: Double, longitude: Double) { // 위도와 경도를 직접 받아 초기화하는 생성자입니다.
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ coordinate: CLLocationCoordinate2D) { // CoreLocation의 좌표 객체로부터 초기화하는 생성자입니다.
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    public func toCLLocationCoordinate2D() -> CLLocationCoordinate2D { // CoreLocation의 좌표 객체로 변환하는 메서드입니다.
        return CLLocationCoordinate2D(latitude: latitude,
                                      longitude: longitude)
    }

    /// NMGLatLng으로 변환 (네이버 지도 API용)
    public func toNMGLatLng() -> NMGLatLng { // 네이버 지도의 좌표 객체로 변환하는 메서드입니다.
        return NMGLatLng(lat: latitude, lng: longitude)
    }

    var clCoordinate: CLLocationCoordinate2D { // CoreLocation 좌표 객체를 반환하는 계산 프로퍼티입니다.
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // MARK: - 좌표 파싱
    
    /// 다양한 형식의 좌표 문자열을 파싱하여 Coordinate 객체로 변환
    public static func parse(_ input: String) -> CoordinateManager? {
        let cleanedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let coordinate = parseDegreesMinutesSeconds(cleanedInput) { return coordinate }
        if let coordinate = parseDecimalDegrees(cleanedInput) { return coordinate }
        if let coordinate = parseSimpleDecimal(cleanedInput) { return coordinate }
        if let coordinate = parseGeo(cleanedInput) { return coordinate }
        if let coordinate = parseMGRS(cleanedInput) { return coordinate }
        if let coordinate = parsePlusCode(cleanedInput) { return coordinate }
        
        return nil
    }
    
    /// 도/분/초 형식 파싱 (예: 37° 38′ 55″ N 126° 41′ 12″ E)
    private static func parseDegreesMinutesSeconds(_ input: String) -> CoordinateManager? {
        let pattern = #"(\d+)°\s*(\d+)′\s*(\d+)″\s*([NS])\s*(\d+)°\s*(\d+)′\s*(\d+)″\s*([EW])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
            return nil
        }
        
        let groups = (1...8).map { index -> String in
            let range = match.range(at: index)
            return String(input[Range(range, in: input)!])
        }
        
        let latDegrees = Double(groups[0])!
        let latMinutes = Double(groups[1])!
        let latSeconds = Double(groups[2])!
        let latDirection = groups[3]
        
        let lonDegrees = Double(groups[4])!
        let lonMinutes = Double(groups[5])!
        let lonSeconds = Double(groups[6])!
        let lonDirection = groups[7]
        
        let latitude = (latDegrees + latMinutes/60 + latSeconds/3600) * (latDirection == "N" ? 1 : -1)
        let longitude = (lonDegrees + lonMinutes/60 + lonSeconds/3600) * (lonDirection == "E" ? 1 : -1)
        
        return CoordinateManager(latitude: latitude, longitude: longitude)
    }
    
    /// 십진도 형식 파싱 (예: 37.648611°, 126.686667°)
    private static func parseDecimalDegrees(_ input: String) -> CoordinateManager? {
        let pattern = #"(-?\d+\.?\d*)°?\s*,\s*(-?\d+\.?\d*)°?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
            return nil
        }
        
        let latRange = match.range(at: 1)
        let lonRange = match.range(at: 2)
        
        guard let lat = Double(input[Range(latRange, in: input)!]),
              let lon = Double(input[Range(lonRange, in: input)!]) else {
            return nil
        }
        
        return CoordinateManager(latitude: lat, longitude: lon)
    }
    
    /// 단순 십진수 형식 파싱 (예: 37.3855 126.4142)
    private static func parseSimpleDecimal(_ input: String) -> CoordinateManager? {
        let components = input.split(separator: " ").map(String.init)
        guard components.count == 2,
              let lat = Double(components[0]),
              let lon = Double(components[1]) else {
            return nil
        }
        
        return CoordinateManager(latitude: lat, longitude: lon)
    }
    
    /// Geo URI 형식 파싱 (예: geo:37.648611,126.686667)
    private static func parseGeo(_ input: String) -> CoordinateManager? {
        guard input.hasPrefix("geo:") else { return nil }
        let components = input.dropFirst(4).split(separator: ",").map(String.init)
        guard components.count == 2,
              let lat = Double(components[0]),
              let lon = Double(components[1]) else {
            return nil
        }
        
        return CoordinateManager(latitude: lat, longitude: lon)
    }
    
    /// MGRS 형식 파싱 (예: 52S DF 24174 67282)
    private static func parseMGRS(_ input: String) -> CoordinateManager? {
        // MGRS 파싱은 복잡하므로 여기서는 간단한 예시만 구현
        // 실제 구현은 MGRS 라이브러리 사용 권장
        return nil
    }
    
    /// Plus Code 형식 파싱 (예: 8Q98FXC7+M2)
    private static func parsePlusCode(_ input: String) -> CoordinateManager? {
        // Plus Code 파싱은 복잡하므로 여기서는 간단한 예시만 구현
        // 실제 구현은 OpenLocationCode 라이브러리 사용 권장
        return nil
    }
    
    /// 좌표를 도/분/초 형식의 문자열로 변환
    public var formattedCoordinate: String {
        let latAbs = abs(latitude)
        let latDegrees = Int(latAbs)
        let latMinutesDecimal = (latAbs - Double(latDegrees)) * 60
        let latMinutes = Int(latMinutesDecimal)
        let latSeconds = Int((latMinutesDecimal - Double(latMinutes)) * 60)
        let latDirection = latitude >= 0 ? "N" : "S"

        let lonAbs = abs(longitude)
        let lonDegrees = Int(lonAbs)
        let lonMinutesDecimal = (lonAbs - Double(lonDegrees)) * 60
        let lonMinutes = Int(lonMinutesDecimal)
        let lonSeconds = Int((lonMinutesDecimal - Double(lonMinutes)) * 60)
        let lonDirection = longitude >= 0 ? "E" : "W"

        let latString = "\(latDegrees)° \(latMinutes)′ \(latSeconds)″ \(latDirection)"
        let lonString = "\(lonDegrees)° \(lonMinutes)′ \(lonSeconds)″ \(lonDirection)"
        return "\(latString) \(lonString)"
    }

    /// 좌표를 십진수(DD) 형식의 문자열로 변환 (예: 37.648611, 126.686667)
    public var decimalCoordinate: String {
        return String(format: "%.6f, %.6f", latitude, longitude)
    }
}

extension CoordinateManager: Identifiable {
    public var id: String { "\(latitude),\(longitude)" }
}
