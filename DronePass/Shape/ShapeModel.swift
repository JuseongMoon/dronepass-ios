//
//  PlaceShape.swift
//  DronePass
//
//  Created by 문주성 on 5/13/25.
//

// 역할: 도형 데이터 모델
// 연관기능: 지도, 저장, 설정에서 공통 사용

import Foundation // Foundation 프레임워크를 가져옵니다. (기본적인 데이터 타입과 기능을 사용하기 위함)
import CoreLocation // CoreLocation 프레임워크를 가져옵니다. (위치 관련 기능을 사용하기 위함)

public enum ShapeType: String, Codable { // 도형의 타입을 정의하는 열거형입니다. Codable 프로토콜을 준수하여 JSON 변환이 가능합니다.
    case circle // 원형 도형
    case rectangle // 사각형 도형
    case polygon // 다각형 도형
    case polyline // 선형 도형
    
    public var koreanName: String {
        switch self {
        case .circle:    return NSLocalizedString("shape.type.circle", comment: "Circle")
        case .rectangle: return NSLocalizedString("shape.type.rectangle", comment: "Rectangle")
        case .polygon:   return NSLocalizedString("shape.type.polygon", comment: "Polygon")
        case .polyline:  return NSLocalizedString("shape.type.polyline", comment: "Line")
        }
    }
}

// ✅ color: PaletteColor(컬러매니저 기반 enum)로 변경
public struct ShapeModel: Codable, Identifiable, Equatable { // 지도에 표시될 도형의 데이터 모델입니다. Codable과 Identifiable 프로토콜을 준수합니다.
    public let id: UUID // 도형의 고유 식별자입니다.
    public var title: String // 도형의 제목입니다.
    public var shapeType: ShapeType // 도형의 타입입니다.
    public var baseCoordinate: CoordinateManager // 도형의 기준 좌표입니다.
    public var address: String? // 도형의 주소 정보입니다. (선택적)

    // 추가 도형 타입별 옵션
    public var radius: Double? // 원형 도형의 반경입니다. (선택적)
    public var secondCoordinate: CoordinateManager? // 사각형 도형의 두 번째 좌표입니다. (선택적)
    public var polygonCoordinates: [CoordinateManager]? // 다각형 도형의 좌표 배열입니다. (선택적)
    public var polylineCoordinates: [CoordinateManager]? // 선형 도형의 좌표 배열입니다. (선택적)
    public var height: Double? // 드론 비행 고도 (미터 단위, 선택적)

    public var memo: String? // 도형에 대한 메모입니다. (선택적)
    
    // 새로운 날짜 관련 필드들
    public var createdAt: Date // 도형이 만들어진 시간
    public var deletedAt: Date? // 도형이 삭제된 시간 (삭제되지 않았다면 nil)
    public var flightStartDate: Date // 드론비행승인 시작날짜
    public var flightEndDate: Date? // 드론비행승인 종료날짜
    public var updatedAt: Date // 마지막 수정 시간 (LWW 동기화 기준)

    /// **팔레트 컬러 (색상 팔레트에서 고름)**
    public var color: String // 도형의 색상입니다. (16진수 색상 코드)

    /// **드론 ID (다중 드론 지원)**
    public var droneId: String? // 도형이 연결된 드론의 ID (하이브리드 호환성)
    
    // MARK: - 커스텀 디코딩 (기존 데이터 호환성)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 기본 필드들
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        shapeType = try container.decode(ShapeType.self, forKey: .shapeType)
        baseCoordinate = try container.decode(CoordinateManager.self, forKey: .baseCoordinate)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        
        // 도형 타입별 옵션들
        radius = try container.decodeIfPresent(Double.self, forKey: .radius)
        secondCoordinate = try container.decodeIfPresent(CoordinateManager.self, forKey: .secondCoordinate)
        polygonCoordinates = try container.decodeIfPresent([CoordinateManager].self, forKey: .polygonCoordinates)
        polylineCoordinates = try container.decodeIfPresent([CoordinateManager].self, forKey: .polylineCoordinates)
        height = try container.decodeIfPresent(Double.self, forKey: .height)

        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        color = try container.decode(String.self, forKey: .color)

        // droneId 처리 (하이브리드 호환성 - 새 필드이므로 없을 수 있음)
        droneId = try container.decodeIfPresent(String.self, forKey: .droneId)
        
        // 새로운 날짜 필드들 - 안전한 마이그레이션 로직 (에러 로깅 포함)
        
        // createdAt 처리
        if let existingCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = existingCreatedAt
        } else {
            // 기존 startedAt에서 마이그레이션 (안전한 처리)
            if let migratedDate = Self.safeMigrateDate(from: container, forKey: .startedAt, fieldName: "createdAt", shapeName: title) {
                createdAt = migratedDate
            } else {
                createdAt = Date()
            }
        }
        
        // deletedAt 처리
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        
        // flightStartDate 처리
        if let existingFlightStartDate = try container.decodeIfPresent(Date.self, forKey: .flightStartDate) {
            flightStartDate = existingFlightStartDate
        } else {
            // 기존 startedAt에서 마이그레이션 (안전한 처리)
            if let migratedDate = Self.safeMigrateDate(from: container, forKey: .startedAt, fieldName: "flightStartDate", shapeName: title) {
                flightStartDate = migratedDate
            } else {
                flightStartDate = Date()
            }
        }
        
        // flightEndDate 처리
        if let existingFlightEndDate = try container.decodeIfPresent(Date.self, forKey: .flightEndDate) {
            flightEndDate = existingFlightEndDate
        } else {
            // 기존 expireDate에서 마이그레이션 (안전한 처리)  
            if let migratedDate = Self.safeMigrateDate(from: container, forKey: .expireDate, fieldName: "flightEndDate", shapeName: title) {
                flightEndDate = migratedDate
            } else {
                flightEndDate = nil
            }
        }
        
        // updatedAt 처리 (없으면 createdAt을 사용)
        if let existingUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            updatedAt = existingUpdatedAt
        } else {
            updatedAt = createdAt
        }
        
    }
    
    // MARK: - 안전한 날짜 마이그레이션 헬퍼
    
    /// 기존 필드에서 안전하게 날짜를 마이그레이션합니다.
    /// - Parameters:
    ///   - container: 디코딩 컨테이너
    ///   - key: 마이그레이션할 키
    ///   - fieldName: 대상 필드명 (로깅용)
    ///   - shapeName: 도형명 (로깅용)
    /// - Returns: 성공 시 Date, 실패 시 nil
    private static func safeMigrateDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys, fieldName: String, shapeName: String) -> Date? {
        
        // 1. Date 타입으로 직접 디코딩 시도
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        
        // 2. Double (timestamp) 타입으로 디코딩 시도
        if let timestamp = try? container.decodeIfPresent(Double.self, forKey: key) {
            // Swift Date는 timeIntervalSinceReferenceDate (2001-01-01 기준)를 사용
            let date = Date(timeIntervalSinceReferenceDate: timestamp)
            return date
        }
        
        // 3. Int (timestamp) 타입으로 디코딩 시도  
        if let timestamp = try? container.decodeIfPresent(Int.self, forKey: key) {
            // Swift Date는 timeIntervalSinceReferenceDate (2001-01-01 기준)를 사용
            let date = Date(timeIntervalSinceReferenceDate: TimeInterval(timestamp))
            return date
        }
        
        // 4. String 타입으로 디코딩 시도
        if let dateString = try? container.decodeIfPresent(String.self, forKey: key) {
            let iso8601Formatter = ISO8601DateFormatter()
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
    
    // MARK: - 커스텀 인코딩
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // 기본 필드들
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(shapeType, forKey: .shapeType)
        try container.encode(baseCoordinate, forKey: .baseCoordinate)
        try container.encodeIfPresent(address, forKey: .address)
        
        // 도형 타입별 옵션들
        try container.encodeIfPresent(radius, forKey: .radius)
        try container.encodeIfPresent(secondCoordinate, forKey: .secondCoordinate)
        try container.encodeIfPresent(polygonCoordinates, forKey: .polygonCoordinates)
        try container.encodeIfPresent(polylineCoordinates, forKey: .polylineCoordinates)
        try container.encodeIfPresent(height, forKey: .height)

        try container.encodeIfPresent(memo, forKey: .memo)
        try container.encode(color, forKey: .color)

        // droneId 저장 (하이브리드 호환성)
        try container.encodeIfPresent(droneId, forKey: .droneId)
        
        // 새로운 날짜 필드들만 저장 (기존 필드는 저장하지 않음)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(flightStartDate, forKey: .flightStartDate)
        try container.encodeIfPresent(flightEndDate, forKey: .flightEndDate)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    // MARK: - CodingKeys
    
    private enum CodingKeys: String, CodingKey {
        case id, title, shapeType, baseCoordinate, address
        case radius, secondCoordinate, polygonCoordinates, polylineCoordinates
        case height
        case memo, color, droneId
        case createdAt, deletedAt, flightStartDate, flightEndDate, updatedAt
        case startedAt, expireDate // 기존 필드 (호환성)
    }
    
    /// 만료 여부 (오늘 날짜 기준)
    public var isExpired: Bool {
        guard let flightEndDate = flightEndDate else { return false }
        return flightEndDate < Date()
    }

    /// 시작 전 여부 (오늘 날짜 기준)
    public var isNotStarted: Bool {
        return flightStartDate > Date()
    }

    /// 삭제된 도형인지 확인
    public var isDeleted: Bool {
        return deletedAt != nil
    }

    /// 효과적인 색상 (기본 색상 반환)
    /// 드론 색상 조회는 View에서 별도로 수행 (MainActor 호환성)
    public var effectiveColor: String {
        return color
    }

    /// 드론 색상을 포함한 효과적인 색상 (MainActor 컨텍스트에서만 사용)
    @MainActor
    public var effectiveColorWithDrone: String {
        if let droneId = droneId,
           let drone = DroneManager.shared.getDrone(by: droneId) {
            return drone.color // 드론 색상 우선
        }
        return color // 기존 색상 fallback
    }

    public init( // 초기화 메서드입니다.
        id: UUID = UUID(), // UUID를 생성합니다. 기본값으로 새로운 UUID를 사용합니다.
        title: String, // 도형의 제목을 설정합니다.
        shapeType: ShapeType = .circle, // 도형의 타입을 설정합니다. 기본값은 원형입니다.
        baseCoordinate: CoordinateManager, // 도형의 기준 좌표를 설정합니다.
        radius: Double? = nil, // 원형 도형의 반경을 설정합니다. (선택적)
        secondCoordinate: CoordinateManager? = nil, // 사각형 도형의 두 번째 좌표를 설정합니다. (선택적)
        polygonCoordinates: [CoordinateManager]? = nil, // 다각형 도형의 좌표 배열을 설정합니다. (선택적)
        polylineCoordinates: [CoordinateManager]? = nil, // 선형 도형의 좌표 배열을 설정합니다. (선택적)
        height: Double? = nil, // 드론 비행 고도를 설정합니다. (미터 단위, 선택적)
        memo: String? = nil, // 도형에 대한 메모를 설정합니다. (선택적)
        address: String? = nil, // 도형의 주소를 설정합니다. (선택적)
        createdAt: Date = Date(), // 도형이 만들어진 시간을 설정합니다. 기본값은 현재 시간입니다.
        deletedAt: Date? = nil, // 도형이 삭제된 시간을 설정합니다. (선택적)
        flightStartDate: Date = Date(), // 드론비행승인 시작날짜를 설정합니다. 기본값은 현재 시간입니다.
        flightEndDate: Date? = nil, // 드론비행승인 종료날짜를 설정합니다. (선택적)
        color: String = "#007AFF", // 도형의 색상을 설정합니다. 기본값은 파란색입니다.
        droneId: String? = nil, // 연결된 드론의 ID를 설정합니다. (선택적)
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.shapeType = shapeType
        self.baseCoordinate = baseCoordinate
        self.radius = radius
        self.secondCoordinate = secondCoordinate
        self.polygonCoordinates = polygonCoordinates
        self.polylineCoordinates = polylineCoordinates
        self.height = height
        self.memo = memo
        self.address = address
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.flightStartDate = flightStartDate
        self.flightEndDate = flightEndDate
        self.color = color
        self.droneId = droneId
        self.updatedAt = updatedAt
    }

    // MARK: - 드론 관련 헬퍼 메서드

    /// 드론에 연결되어 있는지 확인 (droneId가 있는지만 확인)
    public var isConnectedToDrone: Bool {
        return droneId != nil
    }

    /// 드론에 연결되어 있는지 확인 (MainActor 컨텍스트에서 드론 존재 여부까지 확인)
    @MainActor
    public var isConnectedToActiveDrone: Bool {
        return droneId != nil && DroneManager.shared.getDrone(by: droneId!) != nil
    }

    /// 연결된 드론 모델 가져오기 (MainActor 컨텍스트에서만 사용)
    @MainActor
    public var connectedDrone: DroneModel? {
        guard let droneId = droneId else { return nil }
        return DroneManager.shared.getDrone(by: droneId)
    }

    /// 드론 연결 설정
    public mutating func connectToDrone(_ droneId: String?) {
        self.droneId = droneId
        self.updatedAt = Date()
    }

    /// 레거시 도형 체크 (droneId가 없는 기존 도형)
    public var isLegacyShape: Bool {
        return droneId == nil
    }
}

// MARK: - CLLocationCoordinate2D Codable
extension CLLocationCoordinate2D: Codable { // CoreLocation의 CLLocationCoordinate2D를 Codable로 확장합니다.
    enum CodingKeys: String, CodingKey { // JSON 인코딩/디코딩에 사용할 키를 정의합니다.
        case latitude // 위도
        case longitude // 경도
    }
    
    public init(from decoder: Decoder) throws { // JSON에서 객체로 변환하는 초기화 메서드입니다.
        let container = try decoder.container(keyedBy: CodingKeys.self) // 디코딩 컨테이너를 생성합니다.
        let latitude = try container.decode(Double.self, forKey: .latitude) // 위도를 디코딩합니다.
        let longitude = try container.decode(Double.self, forKey: .longitude) // 경도를 디코딩합니다.
        self.init(latitude: latitude, longitude: longitude) // 좌표 객체를 생성합니다.
    }
    
    public func encode(to encoder: Encoder) throws { // 객체를 JSON으로 변환하는 메서드입니다.
        var container = encoder.container(keyedBy: CodingKeys.self) // 인코딩 컨테이너를 생성합니다.
        try container.encode(latitude, forKey: .latitude) // 위도를 인코딩합니다.
        try container.encode(longitude, forKey: .longitude) // 경도를 인코딩합니다.
    }
}
