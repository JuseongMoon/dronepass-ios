//
//  VWorldModels.swift
//  DronePass
//
//  VWorld API GeoJSON 데이터 모델
//

import Foundation
import CoreLocation

// MARK: - GeoJSON 기본 구조

/// GeoJSON FeatureCollection
struct GeoJSONFeatureCollection: Codable {
    let type: String
    let features: [GeoJSONFeature]
    let totalFeatures: Int?
    let numberMatched: Int?
    let numberReturned: Int?
    let timeStamp: String?
    let crs: GeoJSONCRS?
}

/// GeoJSON CRS (좌표계 정보)
struct GeoJSONCRS: Codable {
    let type: String
    let properties: GeoJSONCRSProperties
}

struct GeoJSONCRSProperties: Codable {
    let name: String
}

/// GeoJSON Feature
struct GeoJSONFeature: Codable {
    let type: String
    let id: String
    let geometry: GeoJSONGeometry
    let properties: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, id, geometry, properties
    }
}

/// GeoJSON Geometry
struct GeoJSONGeometry: Codable {
    let type: String
    let coordinates: GeoJSONCoordinates
}

/// GeoJSON 좌표 (재귀적 구조 처리)
enum GeoJSONCoordinates: Codable {
    case point([Double])                          // [lon, lat]
    case lineString([[Double]])                   // [[lon, lat], ...]
    case polygon([[[Double]]])                    // [[[lon, lat], ...], ...]
    case multiPolygon([[[[Double]]]])             // [[[[lon, lat], ...], ...], ...]
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // MultiPolygon 시도
        if let multiPolygon = try? container.decode([[[[Double]]]].self) {
            self = .multiPolygon(multiPolygon)
            return
        }

        // Polygon 시도
        if let polygon = try? container.decode([[[Double]]].self) {
            self = .polygon(polygon)
            return
        }

        // LineString 시도
        if let lineString = try? container.decode([[Double]].self) {
            self = .lineString(lineString)
            return
        }

        // Point 시도
        if let point = try? container.decode([Double].self) {
            self = .point(point)
            return
        }

        // 알 수 없는 형식
        self = .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .point(let coords):
            try container.encode(coords)
        case .lineString(let coords):
            try container.encode(coords)
        case .polygon(let coords):
            try container.encode(coords)
        case .multiPolygon(let coords):
            try container.encode(coords)
        case .unknown:
            try container.encodeNil()
        }
    }
}

// MARK: - AnyCodable (동적 JSON 속성 처리)

/// 동적 타입을 위한 래퍼
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - 드론 구역 Feature 모델

/// 드론 비행 구역 Feature (앱에서 사용하기 쉬운 형태)
struct DroneZoneFeature: Identifiable {
    let id: String
    let layer: FlightZoneLayer
    let geometry: GeoJSONGeometry
    let properties: [String: Any]

    // MARK: - 레이어별 실제 필드 매핑

    /// 구역 코드/이름 (레이어별 실제 필드)
    var zoneCode: String? {
        switch layer {
        case .prohibitedZone:
            return properties["prh_lbl_1"] as? String
        case .temporaryProhibited:
            return properties["prh_lbl_1"] as? String
        case .controlZone:
            return properties["ctr_lbl_1"] as? String
        case .restrictedZone:
            return properties["res_lbl_1"] as? String
        case .dangerZone:
            return properties["dng_lbl_1"] as? String
        case .boundaryZone:
            return properties["alt_lbl_1"] as? String
        case .ultraLightZone:
            return properties["uac_lbl_1"] as? String ?? properties["name_txt"] as? String
        case .consultationZone:
            return properties["nm_kor"] as? String
        case .culturalHeritage:
            return properties["alias"] as? String ?? properties["remark"] as? String
        case .nationalPark:
            // VWorld API는 properties가 비어있으므로, Feature ID로 공원명 매핑
            return mapNationalParkName(from: id)
        default:
            return nil
        }
    }

    /// 구역 이름 (fallback)
    var name: String? {
        zoneCode ?? layer.displayName
    }

    /// 상한 고도
    var upperAltitude: String? {
        switch layer {
        case .prohibitedZone, .temporaryProhibited:
            return properties["prh_lbl_2"] as? String
        case .restrictedZone:
            return properties["res_lbl_2"] as? String
        case .dangerZone:
            return properties["dng_lbl_2"] as? String
        case .boundaryZone:
            return properties["alt_lbl_2"] as? String
        case .ultraLightZone:
            return properties["uac_lbl_2"] as? String
        default:
            return nil
        }
    }

    /// 하한 고도
    var lowerAltitude: String? {
        switch layer {
        case .prohibitedZone, .temporaryProhibited:
            return properties["prh_lbl_3"] as? String
        case .restrictedZone:
            return properties["res_lbl_3"] as? String
        case .dangerZone:
            return properties["dng_lbl_3"] as? String
        case .boundaryZone:
            return properties["alt_lbl_3"] as? String
        case .ultraLightZone:
            return properties["uac_lbl_3"] as? String
        default:
            return nil
        }
    }

    /// 고도 정보 문자열 (표시용)
    var altitudeInfo: String? {
        guard let upper = upperAltitude, let lower = lowerAltitude else {
            return nil
        }
        return "\(lower) ~ \(upper)"
    }

    /// 포맷팅된 상한 고도 (미터 및 설명 포함)
    var formattedUpperAltitude: String? {
        guard let upper = upperAltitude else { return nil }
        return AltitudeFormatter.format(upper)
    }

    /// 포맷팅된 하한 고도 (미터 및 설명 포함)
    var formattedLowerAltitude: String? {
        guard let lower = lowerAltitude else { return nil }
        return AltitudeFormatter.format(lower)
    }

    /// 포맷팅된 고도 정보 문자열 (표시용)
    var formattedAltitudeInfo: String? {
        guard let upper = formattedUpperAltitude, let lower = formattedLowerAltitude else {
            return nil
        }
        return "\(lower) ~ \(upper)"
    }

    // MARK: - 임시비행금지구역 전용 (NOTAM)

    /// NOTAM 원본 문자열
    var notam: String? {
        guard layer == .temporaryProhibited else { return nil }
        return properties["notam"] as? String
    }

    /// NOTAM 시작 일시
    var notamStartDate: Date? {
        guard let notam = notam else { return nil }
        return parseNotamDate(from: notam, field: "B")
    }

    /// NOTAM 종료 일시
    var notamEndDate: Date? {
        guard let notam = notam else { return nil }
        return parseNotamDate(from: notam, field: "C")
    }

    /// NOTAM 상태
    var notamStatus: NotamStatus {
        guard let start = notamStartDate, let end = notamEndDate else {
            return .unknown
        }
        let now = Date()
        if now < start {
            return .scheduled
        } else if now > end {
            return .expired
        } else {
            return .active
        }
    }

    /// 남은 일수 (활성 상태일 때만)
    var daysRemaining: Int? {
        guard notamStatus == .active, let end = notamEndDate else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: Date(), to: end).day
    }

    // MARK: - 사전협의구역 전용

    /// 관리기관명 (한글)
    var authorityNameKor: String? {
        guard layer == .consultationZone else { return nil }
        return properties["nm_kor"] as? String
    }

    /// 관리기관명 (영문)
    var authorityNameEng: String? {
        guard layer == .consultationZone else { return nil }
        return properties["nm_eng"] as? String
    }

    /// 관리부서명
    var operatingInstitution: String? {
        guard layer == .consultationZone else { return nil }
        return properties["oper_inst"] as? String
    }

    /// 연락처 전화번호
    var phoneNumber: String? {
        guard layer == .consultationZone else { return nil }
        return properties["telno"] as? String
    }

    // MARK: - 문화재보호구역 전용

    /// 시도명
    var sidoName: String? {
        guard layer == .culturalHeritage else { return nil }
        return properties["sido_name"] as? String
    }

    /// 시군구명
    var sigunguName: String? {
        guard layer == .culturalHeritage else { return nil }
        return properties["sigg_name"] as? String
    }

    /// 용도지역명
    var zoneName: String? {
        guard layer == .culturalHeritage else { return nil }
        return properties["uname"] as? String
    }

    /// 고시년도
    var designationYear: String? {
        guard layer == .culturalHeritage else { return nil }
        return properties["dyear"] as? String
    }

    /// 고시번호
    var designationNumber: String? {
        guard layer == .culturalHeritage else { return nil }
        return properties["dnum"] as? String
    }

    /// 행정구역 전체 문자열
    var fullAddress: String? {
        guard let sido = sidoName, let sigungu = sigunguName else {
            return nil
        }
        return "\(sido) \(sigungu)"
    }

    // MARK: - 공공기관 연락처 (수동 수집 데이터)

    /// 공공기관 연락처 (VWorld 공식 데이터 우선, 수동 수집 데이터 fallback)
    var publicContact: PublicContactInfo? {
        // 1순위: VWorld 공식 데이터 (사전협의구역의 telno)
        if let officialPhone = phoneNumber,
           let orgName = authorityNameKor {
            return PublicContactInfo(
                organizationName: orgName,
                phoneNumber: officialPhone
            )
        }

        // 2순위: 수동 수집 데이터 (문화재, 국립공원 등)
        guard let zoneName = zoneCode ?? name else { return nil }
        return VWorldContactManager.shared.findContact(for: zoneName)
    }

    // MARK: - Helper: NOTAM 날짜 파싱

    private func parseNotamDate(from notam: String, field: String) -> Date? {
        // "A)RKRR B)2501311500 C)2504301459" 형식에서 B) 또는 C) 추출
        let pattern = "\(field)\\)(\\d{10})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: notam, range: NSRange(notam.startIndex..., in: notam)),
              let range = Range(match.range(at: 1), in: notam) else {
            return nil
        }

        let dateString = String(notam[range])

        // YYMMDDHHMM 파싱
        guard dateString.count == 10,
              let year = Int(dateString.prefix(2)),
              let month = Int(dateString.dropFirst(2).prefix(2)),
              let day = Int(dateString.dropFirst(4).prefix(2)),
              let hour = Int(dateString.dropFirst(6).prefix(2)),
              let minute = Int(dateString.dropFirst(8).prefix(2)) else {
            return nil
        }

        var components = DateComponents()
        components.year = 2000 + year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "UTC") // NOTAM은 UTC 기준

        return Calendar.current.date(from: components)
    }

    /// 국립자연공원 Feature ID → 공원명 매핑
    /// - Parameter featureId: VWorld Feature ID (예: "lt_c_wgisnpgug.29")
    /// - Returns: 공원명 (예: "지리산국립공원사무소")
    private func mapNationalParkName(from featureId: String?) -> String? {
        guard let id = featureId,
              let idNumber = id.split(separator: ".").last,
              let num = Int(idNumber) else {
            return nil
        }

        // 디버깅용: Feature ID와 좌표 로깅
        let center = geometry.centerCoordinate
        print("🏔️ [국립공원] Feature ID: \(id) (번호: \(num)), 좌표: \(center.latitude), \(center.longitude)")

        // Feature ID → 국립공원명 매핑 (좌표 기반 자동 분류)
        switch num {
        // 지리산국립공원 (4개)
        case 29, 42, 77, 80:
            return "지리산국립공원사무소"

        // 설악산국립공원 (1개) - ID 63만 설악산, 105-106은 오대산
        case 63:
            return "설악산국립공원사무소"

        // 북한산국립공원 (1개)
        case 30:
            return "북한산국립공원사무소"

        // 한라산국립공원 (1개)
        case 103:
            return "한라산국립공원사무소"

        // 덕유산국립공원 (2개)
        case 67, 68:
            return "덕유산국립공원사무소"

        // 오대산국립공원 (2개)
        case 105, 106:
            return "오대산국립공원사무소"

        // 주왕산국립공원 (4개)
        case 20, 22, 28, 69:
            return "주왕산국립공원사무소"

        // 경주국립공원 (9개)
        case 17, 18, 19, 21, 23, 24, 25, 26, 27:
            return "경주국립공원사무소"

        // 팔공산국립공원 (2개)
        case 94, 96:
            return "팔공산국립공원사무소"

        // 속리산국립공원 (1개)
        case 64:
            return "속리산국립공원사무소"

        // 내장산국립공원 (2개)
        case 65, 66:
            return "내장산국립공원사무소"

        // 가야산국립공원 (2개)
        case 5, 95:
            return "가야산국립공원사무소"

        // 계룡산국립공원 (1개)
        case 32:
            return "계룡산국립공원사무소"

        // 다도해해상국립공원 (23개)
        case 33, 34, 36, 37, 40, 41, 45, 47, 48, 49, 50, 51, 52, 53, 55, 56, 57, 58, 59, 60, 61, 62, 75:
            return "다도해해상국립공원사무소"

        // 무등산국립공원 (3개)
        case 43, 44, 97:
            return "무등산국립공원사무소"

        // 변산반도국립공원 (10개)
        case 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
            return "변산반도국립공원사무소"

        // 월악산국립공원 (5개)
        case 98, 99, 100, 101, 102:
            return "월악산국립공원사무소"

        // 월출산국립공원 (5개)
        case 1, 35, 38, 46, 54:
            return "월출산국립공원사무소"

        // 치악산국립공원 (1개)
        case 16:
            return "치악산국립공원사무소"

        // 태백산국립공원 (1개)
        case 31:
            return "태백산국립공원사무소"

        // 소백산국립공원 (1개)
        case 104:
            return "소백산국립공원사무소"

        // 태안해안국립공원 (3개)
        case 2, 3, 4:
            return "태안해안국립공원사무소"

        // 한려해상국립공원 (22개)
        case 39, 70, 71, 72, 73, 74, 76, 78, 79, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93:
            return "한려해상국립공원사무소"

        default:
            return nil
        }
    }

    /// GeoJSON Feature에서 생성
    init(from geoJSON: GeoJSONFeature, layer: FlightZoneLayer) {
        self.id = geoJSON.id
        self.layer = layer
        self.geometry = geoJSON.geometry

        // ✅ 성능 최적화: 레이어별 필수 필드만 선택적으로 파싱
        let requiredKeys = layer.requiredProperties
        var props: [String: Any] = [:]

        if let geoProperties = geoJSON.properties {
            for (key, anyCodable) in geoProperties {
                // 필수 필드만 저장 (불필요한 메모리 사용 방지)
                if requiredKeys.contains(key) {
                    props[key] = anyCodable.value
                }
            }
        }
        self.properties = props
    }

    /// 좌표 배열 추출 (Polygon, MultiPolygon 대응)
    func extractCoordinates() -> [[[CLLocationCoordinate2D]]] {
        switch geometry.coordinates {
        case .polygon(let rings):
            // Polygon: [ring1, ring2, ...] → [[ring1], [ring2], ...]
            return [rings.map { ring in
                ring.map { coord in
                    CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                }
            }]

        case .multiPolygon(let polygons):
            // MultiPolygon: [[ring1, ring2], [ring3, ring4], ...] → 그대로
            return polygons.map { polygon in
                polygon.map { ring in
                    ring.map { coord in
                        CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    }
                }
            }

        case .point(let coord):
            // Point는 좌표 1개만 (원으로 표현 가능)
            let location = CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
            return [[[location]]]

        case .lineString(let coords):
            // LineString은 폴리곤이 아니므로 빈 배열
            return []

        case .unknown:
            return []
        }
    }
}

// MARK: - API 요청 파라미터

/// VWorld WFS 요청 파라미터
struct VWorldWFSRequest {
    let service: String = "WFS"
    let version: String = VWorldAPIConfig.wfsVersion
    let request: String = VWorldAPIConfig.requestType
    let typename: String  // 레이어 이름
    let outputFormat: String = VWorldAPIConfig.outputFormat
    let srsname: String = VWorldAPIConfig.defaultSRS
    let bbox: String  // "minX,minY,maxX,maxY"
    let key: String = VWorldAPIConfig.apiKey
    let domain: String = VWorldAPIConfig.domain

    /// URL Query Items 생성
    func toQueryItems() -> [URLQueryItem] {
        return [
            URLQueryItem(name: "service", value: service),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "request", value: request),
            URLQueryItem(name: "typename", value: typename),
            URLQueryItem(name: "outputFormat", value: outputFormat),
            URLQueryItem(name: "srsname", value: srsname),
            URLQueryItem(name: "bbox", value: bbox),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "domain", value: domain)
        ]
    }
}

// MARK: - NOTAM 상태

/// NOTAM 유효 상태
enum NotamStatus {
    case scheduled  // 예정됨 (시작 전)
    case active     // 활성 (현재 유효)
    case expired    // 만료됨 (종료됨)
    case unknown    // 알 수 없음

    var displayName: String {
        switch self {
        case .scheduled: return NSLocalizedString("vworld.notam.status.scheduled", comment: "Scheduled")
        case .active: return NSLocalizedString("vworld.notam.status.active", comment: "Active")
        case .expired: return NSLocalizedString("vworld.notam.status.expired", comment: "Expired")
        case .unknown: return NSLocalizedString("vworld.notam.status.unknown", comment: "Unknown")
        }
    }

    var emoji: String {
        switch self {
        case .scheduled: return "🔵"
        case .active: return "🔴"
        case .expired: return "⚫️"
        case .unknown: return "❓"
        }
    }
}

// MARK: - 공공기관 연락처

/// 공공기관 연락처 정보 (S3에서 수동 수집)
struct PublicContactInfo: Codable, Identifiable, Hashable {
    let id = UUID()
    let organizationName: String  // 기관명 (예: "국가유산청", "경복궁")
    let phoneNumber: String       // 전화번호

    enum CodingKeys: String, CodingKey {
        case organizationName, phoneNumber
    }
}

// MARK: - 에러 타입

enum VWorldAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case noData
    case invalidAPIKey
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("vworld.error.invalidURL", comment: "Invalid URL.")
        case .networkError(let error):
            return String(format: NSLocalizedString("vworld.error.networkError", comment: "Network error: %@"), error.localizedDescription)
        case .decodingError(let error):
            return String(format: NSLocalizedString("vworld.error.decodingError", comment: "Data parsing error: %@"), error.localizedDescription)
        case .noData:
            return NSLocalizedString("vworld.error.noData", comment: "No data available.")
        case .invalidAPIKey:
            return NSLocalizedString("vworld.error.invalidAPIKey", comment: "VWorld API key is invalid.")
        case .rateLimitExceeded:
            return NSLocalizedString("vworld.error.rateLimitExceeded", comment: "API rate limit exceeded.")
        }
    }
}

// MARK: - 고도 포맷터

/// 고도 값 파싱 및 변환 유틸리티
struct AltitudeFormatter {

    /// 고도 단위
    enum AltitudeUnit: String {
        case amsl = "AMSL"      // Above Mean Sea Level (평균 해수면)
        case agl = "AGL"        // Above Ground Level (지상 기준)
        case msl = "MSL"        // Mean Sea Level
        case flightLevel = "FL" // Flight Level (비행고도층)
        case ftHeight = "FT HEI"  // Feet Height
        case ftAltitude = "FT ALT" // Feet Altitude
        case unlimited = "UNL"  // Unlimited (무제한)
        case ground = "GND"     // Ground (지상)
        case surface = "SFC"    // Surface (표면)
        case unknown = ""

        var description: String {
            switch self {
            case .amsl: return NSLocalizedString("altitude.unit.amsl", comment: "평균 해수면")
            case .agl: return NSLocalizedString("altitude.unit.agl", comment: "지상 기준")
            case .msl: return NSLocalizedString("altitude.unit.msl", comment: "평균 해수면")
            case .flightLevel: return NSLocalizedString("altitude.unit.fl", comment: "비행고도층")
            case .ftHeight: return NSLocalizedString("altitude.unit.ftHeight", comment: "높이")
            case .ftAltitude: return NSLocalizedString("altitude.unit.ftAltitude", comment: "고도")
            case .unlimited: return NSLocalizedString("altitude.value.unlimited", comment: "제한없음")
            case .ground: return NSLocalizedString("altitude.value.ground", comment: "지상")
            case .surface: return NSLocalizedString("altitude.value.surface", comment: "표면")
            case .unknown: return ""
            }
        }
    }

    /// 고도 값 파싱 결과
    struct ParsedAltitude {
        let originalValue: String
        let numericValue: Double?
        let unit: AltitudeUnit
        let metersValue: Double?

        /// 포맷팅된 문자열 생성 (원본값 (미터, 설명))
        var formattedString: String {
            // 특수 값 처리
            if unit == .unlimited || unit == .ground || unit == .surface {
                return "\(originalValue) (\(unit.description))"
            }

            // 숫자 값이 없으면 원본 반환
            guard let meters = metersValue else {
                return originalValue
            }

            // 미터 값 포맷팅 (소수점 없으면 정수로, 있으면 1자리까지)
            let metersString: String
            if meters.truncatingRemainder(dividingBy: 1) == 0 {
                metersString = String(format: "%.0f", meters)
            } else {
                metersString = String(format: "%.1f", meters)
            }

            return "\(originalValue) (\(metersString)m, \(unit.description))"
        }
    }

    /// 고도 문자열 파싱
    /// - Parameter altitudeString: 원본 고도 문자열 (예: "3 000 AGL", "FL150", "UNL")
    /// - Returns: 파싱된 고도 정보
    static func parse(_ altitudeString: String?) -> ParsedAltitude? {
        guard let original = altitudeString?.trimmingCharacters(in: .whitespaces), !original.isEmpty else {
            return nil
        }

        let upperValue = original.uppercased()

        // 특수 값 처리
        if upperValue == "UNL" {
            return ParsedAltitude(originalValue: original, numericValue: nil, unit: .unlimited, metersValue: nil)
        }
        if upperValue == "GND" {
            return ParsedAltitude(originalValue: original, numericValue: 0, unit: .ground, metersValue: 0)
        }
        if upperValue == "SFC" {
            return ParsedAltitude(originalValue: original, numericValue: 0, unit: .surface, metersValue: 0)
        }

        // 단위 감지
        var unit: AltitudeUnit = .unknown
        var numericPart = upperValue

        if upperValue.contains("FT HEI") || upperValue.contains("FTHEI") {
            unit = .ftHeight
            numericPart = upperValue.replacingOccurrences(of: "FT HEI", with: "")
                                    .replacingOccurrences(of: "FTHEI", with: "")
        } else if upperValue.contains("FT ALT") || upperValue.contains("FTALT") {
            unit = .ftAltitude
            numericPart = upperValue.replacingOccurrences(of: "FT ALT", with: "")
                                    .replacingOccurrences(of: "FTALT", with: "")
        } else if upperValue.contains("AMSL") {
            unit = .amsl
            numericPart = upperValue.replacingOccurrences(of: "FT", with: "")
                                    .replacingOccurrences(of: "AMSL", with: "")
        } else if upperValue.contains("AGL") {
            unit = .agl
            numericPart = upperValue.replacingOccurrences(of: "FT", with: "")
                                    .replacingOccurrences(of: "AGL", with: "")
        } else if upperValue.contains("MSL") {
            unit = .msl
            numericPart = upperValue.replacingOccurrences(of: "FT", with: "")
                                    .replacingOccurrences(of: "MSL", with: "")
        } else if upperValue.hasPrefix("FL") {
            unit = .flightLevel
            numericPart = upperValue.replacingOccurrences(of: "FL", with: "")
        }

        // 숫자 추출 (공백 제거)
        let cleanedNumeric = numericPart.replacingOccurrences(of: " ", with: "")
                                        .trimmingCharacters(in: .whitespaces)

        guard let numericValue = Double(cleanedNumeric) else {
            // 숫자 파싱 실패 시 원본 반환
            return ParsedAltitude(originalValue: original, numericValue: nil, unit: .unknown, metersValue: nil)
        }

        // 피트 → 미터 변환
        let metersValue = convertToMeters(value: numericValue, unit: unit)

        return ParsedAltitude(
            originalValue: original,
            numericValue: numericValue,
            unit: unit,
            metersValue: metersValue
        )
    }

    /// 피트 → 미터 변환
    /// - Parameters:
    ///   - value: 숫자 값
    ///   - unit: 고도 단위
    /// - Returns: 미터 값
    private static func convertToMeters(value: Double, unit: AltitudeUnit) -> Double {
        switch unit {
        case .amsl, .agl, .msl, .ftHeight, .ftAltitude:
            // 피트 → 미터: 1 ft = 0.3048 m
            return value * 0.3048

        case .flightLevel:
            // Flight Level: FL100 = 10,000 ft
            return value * 100 * 0.3048

        case .ground, .surface:
            return 0

        case .unlimited, .unknown:
            return 0
        }
    }

    /// 고도 문자열을 포맷팅된 형태로 변환
    /// - Parameter altitudeString: 원본 고도 문자열
    /// - Returns: 포맷팅된 문자열 (예: "3 000 AGL (914m, 지상 기준)")
    static func format(_ altitudeString: String?) -> String? {
        guard let parsed = parse(altitudeString) else {
            return altitudeString
        }
        return parsed.formattedString
    }
}
