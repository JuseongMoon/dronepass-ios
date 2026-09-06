//
//  VWorldConstants.swift
//  DronePass
//
//  VWorld API 관련 상수 및 레이어 정의
//

import Foundation
import SwiftUI

// MARK: - VWorld 드론 비행 구역 레이어

/// VWorld API의 드론 비행 구역 레이어 타입
enum FlightZoneLayer: String, CaseIterable, Identifiable {
    case controlZone = "lt_c_aisctrc"               // 관제권
    case prohibitedZone = "lt_c_aisprhc"            // 비행금지구역
    case restrictedZone = "lt_c_aisresc"            // 비행제한구역
    case dangerZone = "lt_c_aisdngc"                // 위험지역
    case temporaryProhibited = "lt_c_aistemp"       // 임시비행금지구역
    case boundaryZone = "lt_c_aisaltc"              // 경계구역
    case trafficZone = "lt_c_aisatzc"               // 비행장교통구역
    case ultraLightZone = "lt_c_aisuac"             // 초경량비행장치공역
    case lightAircraftZone = "lt_c_aisfldc"         // 경량항공기 이착륙장
    case obstacleZone = "lt_c_aisobls"              // 장애물공역
    case consultationZone = "lt_c_aispca"           // 사전협의구역
    case culturalHeritage = "lt_c_uo301"            // 문화재보호도
    case nationalPark = "lt_c_wgisnpgug"            // 국립자연공원

    var id: String { rawValue }

    /// 레이어 한글명
    var displayName: String {
        switch self {
        case .controlZone: return NSLocalizedString("vworld.layer.controlZone", comment: "Control Zone")
        case .prohibitedZone: return NSLocalizedString("vworld.layer.prohibitedZone", comment: "Prohibited Zone")
        case .restrictedZone: return NSLocalizedString("vworld.layer.restrictedZone", comment: "Restricted Zone")
        case .dangerZone: return NSLocalizedString("vworld.layer.dangerZone", comment: "Danger Zone")
        case .temporaryProhibited: return NSLocalizedString("vworld.layer.temporaryProhibited", comment: "Temporary Prohibited Zone")
        case .boundaryZone: return NSLocalizedString("vworld.layer.boundaryZone", comment: "Boundary Zone")
        case .trafficZone: return NSLocalizedString("vworld.layer.trafficZone", comment: "Aerodrome Traffic Zone")
        case .ultraLightZone: return NSLocalizedString("vworld.layer.ultraLightZone", comment: "Ultralight Aircraft Zone")
        case .lightAircraftZone: return NSLocalizedString("vworld.layer.lightAircraftZone", comment: "Light Aircraft Airfield")
        case .obstacleZone: return NSLocalizedString("vworld.layer.obstacleZone", comment: "Obstacle Zone")
        case .consultationZone: return NSLocalizedString("vworld.layer.consultationZone", comment: "Prior Consultation Zone")
        case .culturalHeritage: return NSLocalizedString("vworld.layer.culturalHeritage", comment: "Cultural Heritage Protection Zone")
        case .nationalPark: return NSLocalizedString("vworld.layer.nationalPark", comment: "National Park")
        }
    }

    /// 레이어 설명
    var description: String {
        switch self {
        case .controlZone:
            return NSLocalizedString("vworld.layer.desc.controlZone", comment: "Control zone near airports requiring flight approval")
        case .prohibitedZone:
            return NSLocalizedString("vworld.layer.desc.prohibitedZone", comment: "Area where drone flight is completely prohibited")
        case .restrictedZone:
            return NSLocalizedString("vworld.layer.desc.restrictedZone", comment: "Area where flight is allowed with restrictions")
        case .dangerZone:
            return NSLocalizedString("vworld.layer.desc.dangerZone", comment: "Area with potential flight hazards")
        case .temporaryProhibited:
            return NSLocalizedString("vworld.layer.desc.temporaryProhibited", comment: "Area temporarily prohibited for flight")
        case .boundaryZone:
            return NSLocalizedString("vworld.layer.desc.boundaryZone", comment: "Area with established flight boundaries")
        case .trafficZone:
            return NSLocalizedString("vworld.layer.desc.trafficZone", comment: "Traffic zone near aerodromes")
        case .ultraLightZone:
            return NSLocalizedString("vworld.layer.desc.ultraLightZone", comment: "Zone dedicated to ultralight aircraft")
        case .lightAircraftZone:
            return NSLocalizedString("vworld.layer.desc.lightAircraftZone", comment: "Light aircraft takeoff and landing zone")
        case .obstacleZone:
            return NSLocalizedString("vworld.layer.desc.obstacleZone", comment: "Area with obstacles")
        case .consultationZone:
            return NSLocalizedString("vworld.layer.desc.consultationZone", comment: "Area requiring prior consultation")
        case .culturalHeritage:
            return NSLocalizedString("vworld.layer.desc.culturalHeritage", comment: "Cultural heritage protection zone")
        case .nationalPark:
            return NSLocalizedString("vworld.layer.desc.nationalPark", comment: "National park zone")
        }
    }

    /// 레이어 색상 (오버레이용, 투명도 30%)
    var overlayColor: Color {
        switch self {
        case .prohibitedZone, .temporaryProhibited:
            return Color.red.opacity(0.3)
        case .restrictedZone, .controlZone, .dangerZone:
            return Color.orange.opacity(0.3)
        case .boundaryZone, .trafficZone, .obstacleZone:
            return Color.yellow.opacity(0.3)
        case .culturalHeritage, .nationalPark:
            return Color.green.opacity(0.3)
        case .ultraLightZone, .lightAircraftZone, .consultationZone:
            return Color.blue.opacity(0.3)
        }
    }

    /// UIColor 변환 (NMFPolygonOverlay용)
    var uiColor: UIColor {
        UIColor(overlayColor)
    }

    /// 레이어 테두리 색상 (불투명)
    var borderUIColor: UIColor {
        switch self {
        case .prohibitedZone, .temporaryProhibited:
            return UIColor.red
        case .restrictedZone, .controlZone, .dangerZone:
            return UIColor.orange
        case .boundaryZone, .trafficZone, .obstacleZone:
            return UIColor.yellow
        case .culturalHeritage, .nationalPark:
            return UIColor.green
        case .ultraLightZone, .lightAircraftZone, .consultationZone:
            return UIColor.blue
        }
    }

    /// 중요도 (1: 가장 중요, 3: 덜 중요)
    /// 오버레이 Z-index 결정에 사용
    var priority: Int {
        switch self {
        case .prohibitedZone, .temporaryProhibited:
            return 1  // 최우선
        case .restrictedZone, .controlZone, .dangerZone:
            return 2  // 중요
        case .boundaryZone, .trafficZone, .obstacleZone,
             .ultraLightZone, .lightAircraftZone, .consultationZone:
            return 3  // 일반
        case .culturalHeritage, .nationalPark:
            return 4  // 정보성
        }
    }

    /// 로딩 우선순위 (1위가 가장 먼저 로드됨)
    /// 사용자에게 중요한 정보를 먼저 표시하기 위해 사용
    var loadingPriority: Int {
        switch self {
        case .prohibitedZone:
            return 1  // 비행금지구역 - 가장 중요
        case .temporaryProhibited:
            return 2  // 임시비행금지구역
        case .controlZone:
            return 3  // 관제권 (공항 주변)
        case .restrictedZone:
            return 4  // 비행제한구역
        case .dangerZone:
            return 5  // 위험지역
        case .boundaryZone:
            return 6  // 경계구역
        case .trafficZone:
            return 7  // 비행장교통구역
        case .ultraLightZone:
            return 8  // 초경량비행장치공역
        case .lightAircraftZone:
            return 9  // 경량항공기 이착륙장
        case .obstacleZone:
            return 10  // 장애물공역
        case .consultationZone:
            return 11  // 사전협의구역
        case .culturalHeritage:
            return 12  // 문화재보호도
        case .nationalPark:
            return 13  // 국립자연공원
        }
    }

    /// 비행 제한 레벨 (비행 승인 판정에 사용)
    var restrictionLevel: FlightRestrictionLevel {
        switch self {
        case .prohibitedZone, .temporaryProhibited:
            return .prohibited
        case .restrictedZone, .controlZone, .dangerZone,
             .boundaryZone, .trafficZone, .obstacleZone:
            return .restricted
        case .culturalHeritage, .nationalPark:
            return .advisory
        case .ultraLightZone, .lightAircraftZone, .consultationZone:
            return .consultation
        }
    }

    /// API에서 필수로 파싱할 properties 필드 (성능 최적화)
    var requiredProperties: Set<String> {
        switch self {
        case .prohibitedZone:
            return ["prh_lbl_1", "prh_lbl_2", "prh_lbl_3"]
        case .temporaryProhibited:
            return ["prh_lbl_1", "prh_lbl_2", "prh_lbl_3", "notam"]
        case .controlZone:
            return ["ctr_lbl_1", "ctr_lbl_2", "ctr_lbl_3"]
        case .restrictedZone:
            return ["res_lbl_1", "res_lbl_2", "res_lbl_3"]
        case .dangerZone:
            return ["dng_lbl_1", "dng_lbl_2", "dng_lbl_3"]
        case .boundaryZone:
            return ["alt_lbl_1", "alt_lbl_2", "alt_lbl_3"]
        case .trafficZone:
            return ["atz_lbl_1", "atz_lbl_2", "atz_lbl_3"]
        case .ultraLightZone:
            return ["uac_lbl_1", "name_txt"]
        case .lightAircraftZone:
            return ["fld_lbl_1", "name"]
        case .obstacleZone:
            return ["obs_lbl_1", "obs_lbl_2"]
        case .consultationZone:
            return ["nm_kor", "nm_eng", "oper_inst", "telno"]
        case .culturalHeritage:
            return ["alias", "remark", "sido_name", "sigg_name", "uname", "dyear", "dnum"]
        case .nationalPark:
            return ["park_name", "desig_date"]
        }
    }
}

// MARK: - 비행 제한 레벨

enum FlightRestrictionLevel {
    case prohibited      // 비행 금지
    case restricted      // 비행 제한 (승인 필요)
    case consultation    // 사전 협의 필요
    case advisory        // 주의 권고

    var displayName: String {
        switch self {
        case .prohibited: return NSLocalizedString("vworld.restriction.prohibited", comment: "Prohibited")
        case .restricted: return NSLocalizedString("vworld.restriction.restricted", comment: "Approval Required")
        case .consultation: return NSLocalizedString("vworld.restriction.consultation", comment: "Consultation Required")
        case .advisory: return NSLocalizedString("vworld.restriction.advisory", comment: "Caution Advised")
        }
    }

    var color: Color {
        switch self {
        case .prohibited: return .red
        case .restricted: return .orange
        case .consultation: return .blue
        case .advisory: return .green
        }
    }
}

// MARK: - VWorld API 설정

struct VWorldAPIConfig {
    /// VWorld API 기본 URL
    static let baseURL = "https://api.vworld.kr/req/wfs"

    /// VWorld API 키 (Info.plist에서 읽기)
    static var apiKey: String {
        guard let key = Bundle.main.infoDictionary?["VWORLD_API_KEY"] as? String,
              !key.isEmpty else {
            print("⚠️ VWorld API Key가 Info.plist에 설정되지 않았습니다.")
            return "YOUR_API_KEY_HERE"
        }
        return key
    }

    /// API 도메인 (앱 이름)
    static let domain = "드론패스"

    /// WFS 서비스 버전
    static let wfsVersion = "1.1.0"

    /// 기본 좌표계 (EPSG:4326 - WGS84, 위도/경도)
    static let defaultSRS = "EPSG:4326"

    /// 응답 형식
    static let outputFormat = "application/json"

    /// 요청 타입
    static let requestType = "GetFeature"
}

// MARK: - 좌표 변환 유틸리티

struct CoordinateConverter {
    /// 지구 반경 (미터)
    private static let earthRadius: Double = 6378137.0

    /// WGS84 (경도, 위도) → Web Mercator (X, Y)
    static func wgs84ToMercator(lon: Double, lat: Double) -> (x: Double, y: Double) {
        let x = lon * .pi / 180.0 * earthRadius
        let y = log(tan(.pi / 4.0 + lat * .pi / 360.0)) * earthRadius
        return (x, y)
    }

    /// Web Mercator (X, Y) → WGS84 (경도, 위도)
    static func mercatorToWGS84(x: Double, y: Double) -> (lon: Double, lat: Double) {
        let lon = (x / earthRadius) * 180.0 / .pi
        let lat = (atan(exp(y / earthRadius)) * 2.0 - .pi / 2.0) * 180.0 / .pi
        return (lon, lat)
    }

    /// BoundingBox 변환: WGS84 → Web Mercator
    static func bboxWGS84ToMercator(minLon: Double, minLat: Double,
                                     maxLon: Double, maxLat: Double) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let min = wgs84ToMercator(lon: minLon, lat: minLat)
        let max = wgs84ToMercator(lon: maxLon, lat: maxLat)
        return (min.x, min.y, max.x, max.y)
    }
}
