//
//  WeatherManager.swift
//  DronePass
//
//  Created by 문주성 on 10/14/25.
//

import Foundation
import WeatherKit
import CoreLocation
import Combine
import SwiftUI

// MARK: - Weather Forecast Configuration

/// 날씨 예보 일수 (1~10일, 권장: 3일)
private let FORECAST_DAYS: Int = 3

// MARK: - Gust Evaluation Constants

/// 돌풍 평가 상수
private struct GustEvaluationConstants {
    static let meanMinForGF: Double = 1.0           // GF 계산 최소 평균풍속
    static let gfCap: Double = 4.0                  // GF 상한 (비현실적 값 방지)
    static let hardStopMargin: Double = 0.8         // 하드-스톱 여유 (0.5~1.0)
    static let estimatedGFBase: Double = 1.3        // 기본 추정 GF

    // MARK: 국지 돌풍 전용 상수
    static let lgLowMeanMin: Double = 0.8           // 저평균풍 보정 최소값
    static let lgLowMeanMax: Double = 1.0           // 저평균풍 보정 최대값
    static let lgLowMeanDiffBoost: Double = 1.0     // 저평균풍 시 diff 증가량
    static let lgMinMeanForGF: Double = 1.0         // 국지 GF 평가 최소 평균풍속
}

// MARK: - Localized Gust Policy

/// 국지 돌풍 전용 정책 구조체
fileprivate struct LocalizedGustPolicy {
    let diff: Double              // LG_diff: 증가량 임계값
    let gf: Double               // LG_GF: Gust Factor 임계값
    let absGust: Double          // LG_abs_gust: 절대 돌풍 임계값
    let votesRequired: Int       // 필요 투표수 (1-3표)
    let minMeanForEval: Double   // GF 평가 최소 평균풍속
    let hysteresisMinVotes: Int  // 히스테리시스: 끄기 위한 최대 투표수

    /// 기체별 오버라이드 적용
    func withModelOverride(_ modelThresholds: AbsoluteWindThresholds?) -> LocalizedGustPolicy {
        guard let override = modelThresholds else { return self }

        // 기체 스펙의 gustCaution보다 높지 않게 제한
        let effectiveAbsGust = min(self.absGust, override.gustCaution)

        return LocalizedGustPolicy(
            diff: self.diff,
            gf: self.gf,
            absGust: effectiveAbsGust,
            votesRequired: self.votesRequired,
            minMeanForEval: self.minMeanForEval,
            hysteresisMinVotes: self.hysteresisMinVotes
        )
    }
}

// MARK: - Drone Make Model

/// 드론 기종별 세부 설정 (DJI 등 제조사 기종)
enum DroneMakeModel: String, CaseIterable, Identifiable {
    // 250g 이하
    case mini2 = "DJI Mini 2"
    case mini3Pro = "DJI Mini 3 Pro"
    case mini4Pro = "DJI Mini 4 Pro"

    // 250g~2kg
    case air2S = "DJI Air 2S"
    case air3 = "DJI Air 3"
    case air3S = "DJI Air 3S"

    // 2kg~7kg
    case mavic3 = "DJI Mavic 3"
    case mavic3Pro = "DJI Mavic 3 Pro"
    case mavic4Pro = "DJI Mavic 4 Pro"
    case inspire3 = "DJI Inspire 3"

    // 7kg~25kg
    case industrial = "산업용 드론"
    case custom = "사용자 정의"

    var id: String { rawValue }

    /// 기종이 속한 드론 카테고리
    var category: DroneCategory {
        switch self {
        case .mini2, .mini3Pro, .mini4Pro:
            return .toy
        case .air2S, .air3, .air3S:
            return .class4
        case .mavic3, .mavic3Pro, .mavic4Pro, .inspire3:
            return .class3
        case .industrial, .custom:
            return .class2
        }
    }

    /// 기체별 절대 임계값 오버라이드 (실제 스펙 기준)
    var absoluteWindOverride: AbsoluteWindThresholds? {
        switch self {
        case .mini4Pro:
            return AbsoluteWindThresholds(
                sustainedCaution: 7.0,
                sustainedDanger: 9.0,
                gustCaution: 9.0,
                gustDanger: 10.7
            )
        case .air3:
            return AbsoluteWindThresholds(
                sustainedCaution: 8.5,
                sustainedDanger: 10.5,
                gustCaution: 10.5,
                gustDanger: 12.0
            )
        case .mavic3, .mavic3Pro:
            return AbsoluteWindThresholds(
                sustainedCaution: 10.0,
                sustainedDanger: 12.0,
                gustCaution: 12.0,
                gustDanger: 12.0  // Mavic 3는 12
            )
        case .mavic4Pro:
            return AbsoluteWindThresholds(
                sustainedCaution: 10.0,
                sustainedDanger: 12.0,
                gustCaution: 12.0,
                gustDanger: 12.0  // Mavic 4 Pro는 12
            )
        case .inspire3:
            return AbsoluteWindThresholds(
                sustainedCaution: 10.0,
                sustainedDanger: 12.0,
                gustCaution: 12.0,
                gustDanger: 14.0  // Inspire 3는 14
            )
        default:
            return nil  // 등급 기본값 사용
        }
    }
}

// MARK: - Absolute Wind Thresholds

/// 절대 풍속 임계값 구조체
struct AbsoluteWindThresholds {
    let sustainedCaution: Double    // 평균풍 주의
    let sustainedDanger: Double     // 평균풍 위험
    let gustCaution: Double         // 돌풍 주의
    let gustDanger: Double          // 돌풍 위험
}

// MARK: - Drone Category

/// 한국 드론 자격 등급 기준 (항공안전법)
enum DroneCategory: String, CaseIterable, Identifiable {
    case toy = "≤250g"              // ~250g
    case class4 = "250g~2kg"        // 250g~2kg
    case class3 = "2kg~7kg"         // 2~7kg
    case class2 = "7kg~25kg"        // 7~25kg

    var id: String { rawValue }

    /// 로컬라이즈된 카테고리 이름
    var localizedName: String {
        switch self {
        case .toy:
            return NSLocalizedString("weather.droneCategory.toy", comment: "≤250g")
        case .class4:
            return NSLocalizedString("weather.droneCategory.class4", comment: "250g~2kg")
        case .class3:
            return NSLocalizedString("weather.droneCategory.class3", comment: "2kg~7kg")
        case .class2:
            return NSLocalizedString("weather.droneCategory.class2", comment: "7kg~25kg")
        }
    }

    /// 드론 카테고리 상세 설명
    var description: String {
        switch self {
        case .toy:
            return NSLocalizedString("weather.droneCategory.toy.description", comment: "Mini Series\nNo License Required")
        case .class4:
            return NSLocalizedString("weather.droneCategory.class4.description", comment: "Air Series\nClass 4 License Required")
        case .class3:
            return NSLocalizedString("weather.droneCategory.class3.description", comment: "Mavic, Inspire\nClass 3 License Required")
        case .class2:
            return NSLocalizedString("weather.droneCategory.class2.description", comment: "Industrial Drones\nClass 2 License Required")
        }
    }

    /// 대표 기종
    var examples: String {
        switch self {
        case .toy:
            return NSLocalizedString("weather.droneCategory.toy.examples", comment: "Mini 2, Mini 3 Pro, Mini 4 Pro")
        case .class4:
            return NSLocalizedString("weather.droneCategory.class4.examples", comment: "Air 2S, Air 3, Air 3S")
        case .class3:
            return NSLocalizedString("weather.droneCategory.class3.examples", comment: "Mavic 3 Pro, Mavic 4 Pro, Inspire 3")
        case .class2:
            return NSLocalizedString("weather.droneCategory.class2.examples", comment: "Agricultural/Industrial Drones")
        }
    }

    /// 최대 풍속 저항 (참고용, m/s)
    var maxWindResistance: Double {
        switch self {
        case .toy: return 10.7
        case .class4: return 12.0
        case .class3: return 12.0
        case .class2: return 15.0
        }
    }

    /// 풍속 임계값 (m/s)
    /// - 업계 표준 2/3 규칙 + 안전 마진 20% 적용
    /// - Beaufort Scale 기준 참조
    var windSpeedThresholds: (caution: Double, danger: Double) {
        switch self {
        case .toy:
            return (7.0, 9.0)    // 최대 저항 10.7의 65%, 84%
        case .class4:
            return (8.5, 10.5)   // 최대 저항 12의 71%, 88%
        case .class3:
            return (10.0, 12.0)  // 최대 저항 12의 83%, 100%
        case .class2:
            return (12.0, 15.0)  // Level 6/7 기준
        }
    }

    /// 순간풍속증가량 임계값 (m/s)
    /// - 항공 기상학 돌풍 정의(4.6 m/s) 기준
    /// - 드론 무게별 안정성 반영
    var gustDifferenceThresholds: (caution: Double, danger: Double) {
        switch self {
        case .toy:
            return (5.0, 7.0)    // 경량급 특성
        case .class4:
            return (6.0, 8.5)    // 중량급
        case .class3:
            return (7.0, 9.5)    // 준전문가급
        case .class2:
            return (9.0, 12.0)   // 산업용
        }
    }

    /// 최소 평균풍속 임계값 (Floor Class)
    /// 이 값보다 평균풍속이 낮으면 돌풍 경보를 억제
    var minimumSustainedWind: Double {
        switch self {
        case .toy: return 4.0
        case .class4: return 5.0
        case .class3: return 6.0
        case .class2: return 7.0
        }
    }

    /// Gust Factor 임계값 (등급별 미세 조정)
    var gustFactorThresholds: (caution: Double, danger: Double) {
        switch self {
        case .toy: return (1.35, 1.55)      // 경량급, 돌풍에 취약
        case .class4: return (1.40, 1.60)   // 표준
        case .class3: return (1.40, 1.60)   // 표준
        case .class2: return (1.45, 1.65)   // 중량급, 돌풍 대응력 우수
        }
    }

    /// 등급별 기본 절대 임계값 (기체별 오버라이드가 없을 때)
    var absoluteWindThresholds: AbsoluteWindThresholds {
        switch self {
        case .toy:
            return AbsoluteWindThresholds(
                sustainedCaution: 7.0,
                sustainedDanger: 9.0,
                gustCaution: 9.0,
                gustDanger: 10.7
            )
        case .class4:
            return AbsoluteWindThresholds(
                sustainedCaution: 8.5,
                sustainedDanger: 10.5,
                gustCaution: 10.5,
                gustDanger: 12.0
            )
        case .class3:
            return AbsoluteWindThresholds(
                sustainedCaution: 10.0,
                sustainedDanger: 12.0,
                gustCaution: 12.0,
                gustDanger: 13.0  // 등급 평균값
            )
        case .class2:
            return AbsoluteWindThresholds(
                sustainedCaution: 12.0,
                sustainedDanger: 15.0,
                gustCaution: 15.0,
                gustDanger: 18.0
            )
        }
    }

    /// 등급별 국지 돌풍 정책
    fileprivate var localizedGustPolicy: LocalizedGustPolicy {
        switch self {
        case .toy:      // 250g 이하 - 매우 민감
            return LocalizedGustPolicy(
                diff: 3.0,
                gf: 1.50,
                absGust: 8.0,
                votesRequired: 1,
                minMeanForEval: GustEvaluationConstants.lgMinMeanForGF,
                hysteresisMinVotes: 0  // 0표면 끔
            )
        case .class4:   // 250g~2kg - 표준 민감도
            return LocalizedGustPolicy(
                diff: 4.0,
                gf: 1.60,
                absGust: 9.5,
                votesRequired: 1,
                minMeanForEval: GustEvaluationConstants.lgMinMeanForGF,
                hysteresisMinVotes: 0
            )
        case .class3:   // 2kg~7kg - 보수적
            return LocalizedGustPolicy(
                diff: 5.0,
                gf: 1.60,
                absGust: 10.5,
                votesRequired: 2,
                minMeanForEval: GustEvaluationConstants.lgMinMeanForGF,
                hysteresisMinVotes: 1  // 1표 이하면 끔 (깜빡임 방지)
            )
        case .class2:   // 7kg~25kg - 매우 보수적
            return LocalizedGustPolicy(
                diff: 6.0,
                gf: 1.70,
                absGust: 12.0,
                votesRequired: 2,
                minMeanForEval: GustEvaluationConstants.lgMinMeanForGF,
                hysteresisMinVotes: 1
            )
        }
    }
}

// MARK: - WeatherThresholds

/// 날씨 경고 임계값을 중앙에서 관리하는 구조체
/// 모든 임계값을 이곳에서 정의하여 일관성 있게 사용
struct WeatherThresholds {

    // MARK: - 온도 임계값 (°C)

    /// 저온 주의 임계값
    static let temperatureLowCaution: Double = -10.0

    /// 고온 주의 임계값
    static let temperatureHighCaution: Double = 35.0

    // MARK: - 풍속 임계값 (m/s)
    // ⚠️ 레거시: DroneCategory의 windSpeedThresholds 사용 권장

    /// 풍속 주의 임계값
    static let windSpeedCaution: Double = 7.0

    /// 풍속 위험 임계값
    static let windSpeedDanger: Double = 11.0

    // MARK: - 순간 풍속 증가량 임계값 (m/s)
    // ⚠️ 레거시: DroneCategory의 gustDifferenceThresholds 사용 권장

    /// 순간 풍속 증가량 주의 임계값
    static let gustDifferenceCaution: Double = 5.0

    /// 순간 풍속 증가량 위험 임계값
    static let gustDifferenceDanger: Double = 8.0

    // MARK: - 가시거리 임계값 (km)

    /// 가시거리 양호 임계값
    static let visibilityGood: Double = 10.0

    /// 가시거리 위험 임계값
    static let visibilityPoor: Double = 2.0

    // MARK: - 결로위험지수 임계값 (1-100)

    /// CRI 주의 임계값 (1-39: 안전, 40-69: 주의)
    static let criModerate: Double = 40.0

    /// CRI 경고 임계값 (70-100: 경고)
    static let criHigh: Double = 70.0

    // MARK: - 강수량 임계값 (mm)

    /// 강수량 감지 임계값 (0보다 큰 값)
    static let precipitationDetection: Double = 0.0
}

// MARK: - 온도 경고 레벨

enum TemperatureWarningLevel {
    case safe           // 정상 범위
    case lowTemp        // 저온 주의
    case highTemp       // 고온 주의

    static func from(_ temperature: Double) -> TemperatureWarningLevel {
        if temperature < WeatherThresholds.temperatureLowCaution {
            return .lowTemp
        } else if temperature > WeatherThresholds.temperatureHighCaution {
            return .highTemp
        } else {
            return .safe
        }
    }

    var color: Color? {
        switch self {
        case .safe: return nil  // 경고 없음
        case .lowTemp, .highTemp: return .orange
        }
    }

    var description: String {
        switch self {
        case .safe: return "정상"
        case .lowTemp: return "저온"
        case .highTemp: return "고온"
        }
    }
}

// MARK: - 풍속 경고 레벨

enum WindSpeedWarningLevel {
    case safe           // 안전
    case caution        // 주의
    case danger         // 위험

    static func from(_ windSpeed: Double) -> WindSpeedWarningLevel {
        if windSpeed >= WeatherThresholds.windSpeedDanger {
            return .danger
        } else if windSpeed >= WeatherThresholds.windSpeedCaution {
            return .caution
        } else {
            return .safe
        }
    }

    var color: Color? {
        switch self {
        case .safe: return nil
        case .caution: return .orange
        case .danger: return .red
        }
    }

    var description: String {
        switch self {
        case .safe: return NSLocalizedString("weather.wind.safe", comment: "Safe")
        case .caution: return NSLocalizedString("weather.wind.caution", comment: "Caution")
        case .danger: return "위험"
        }
    }
}

// MARK: - 순간 풍속 증가량 경고 레벨

enum GustDifferenceWarningLevel {
    case safe           // 양호
    case caution        // 주의
    case danger         // 위험

    static func from(_ gustDifference: Double) -> GustDifferenceWarningLevel {
        if gustDifference >= WeatherThresholds.gustDifferenceDanger {
            return .danger
        } else if gustDifference >= WeatherThresholds.gustDifferenceCaution {
            return .caution
        } else {
            return .safe
        }
    }

    var color: Color? {
        switch self {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        }
    }

    var description: String {
        switch self {
        case .safe: return "양호"
        case .caution: return NSLocalizedString("weather.wind.caution", comment: "Caution")
        case .danger: return "위험"
        }
    }
}

// MARK: - 강수량 경고 레벨

enum PrecipitationWarningLevel {
    case none           // 강수 없음
    case detected       // 강수 감지

    static func from(_ precipitation: Double) -> PrecipitationWarningLevel {
        if precipitation > WeatherThresholds.precipitationDetection {
            return .detected
        } else {
            return .none
        }
    }

    var color: Color? {
        switch self {
        case .none: return nil
        case .detected: return .blue
        }
    }

    var description: String {
        switch self {
        case .none: return NSLocalizedString("weather.precipitation.none", comment: "None")
        case .detected: return NSLocalizedString("weather.precipitation.rain", comment: "Rain")
        }
    }
}

// MARK: - 가시거리 경고 레벨

enum VisibilityWarningLevel {
    case good           // 양호
    case moderate       // 보통
    case poor           // 불량

    static func from(_ visibility: Double) -> VisibilityWarningLevel {
        if visibility < WeatherThresholds.visibilityPoor {
            return .poor
        } else if visibility >= WeatherThresholds.visibilityGood {
            return .good
        } else {
            return .moderate
        }
    }

    var color: Color? {
        switch self {
        case .good: return .green
        case .moderate: return nil  // 보통은 경고 없음
        case .poor: return .red
        }
    }

    var description: String {
        switch self {
        case .good: return "양호"
        case .moderate: return "보통"
        case .poor: return "불량"
        }
    }
}

// MARK: - 결로위험지수 경고 레벨

/// CRI 경고 레벨 (3단계, 히스테리시스 적용)
enum CRIWarningLevel {
    case safe           // 1-39: 안전
    case caution        // 40-69: 주의
    case warning        // 70-100: 경고

    static func from(_ cri: Double) -> CRIWarningLevel {
        if cri >= WeatherThresholds.criHigh {
            return .warning
        } else if cri >= WeatherThresholds.criModerate {
            return .caution
        } else {
            return .safe
        }
    }

    var color: Color? {
        switch self {
        case .safe: return nil
        case .caution: return .yellow
        case .warning: return .red
        }
    }

    var description: String {
        switch self {
        case .safe: return NSLocalizedString("weather.wind.safe", comment: "Safe")
        case .caution: return NSLocalizedString("weather.wind.caution", comment: "Caution")
        case .warning: return NSLocalizedString("weather.wind.warning", comment: "Warning")
        }
    }
}

// MARK: - Legacy Enums

/// CRI 위험 등급 (레거시 - CRIWarningLevel 사용 권장)
enum CRILevel {
    case low        // < 40: 안전
    case moderate   // 40-69: 주의
    case high       // 70+: 경고

    static func from(_ cri: Double) -> CRILevel {
        switch cri {
        case 70...: return .high
        case 40..<70: return .moderate
        default: return .low
        }
    }

    var description: String {
        switch self {
        case .low: return "안전"
        case .moderate: return "주의"
        case .high: return "경고"
        }
    }

    var color: String {
        switch self {
        case .low: return "green"
        case .moderate: return "yellow"
        case .high: return "red"
        }
    }
}

/// 순간 풍속 증가량 위험 등급 (레거시 - WeatherThresholds의 GustDifferenceWarningLevel 사용 권장)
enum GustDifferenceLevel: String, Comparable {
    case safe = "safe"
    case localizedGust = "gustRisk"  // NEW: 평균풍 낮음
    case caution = "caution"
    case danger = "danger"

    var description: String {
        return self.rawValue
    }

    var color: String {
        switch self {
        case .safe: return "green"
        case .localizedGust: return "yellow"
        case .caution: return "orange"
        case .danger: return "red"
        }
    }

    var priority: Int {
        switch self {
        case .safe: return 0
        case .localizedGust: return 1
        case .caution: return 2
        case .danger: return 3
        }
    }

    static func < (lhs: GustDifferenceLevel, rhs: GustDifferenceLevel) -> Bool {
        lhs.priority < rhs.priority
    }

    // 레거시 지원용 (기존 코드와의 호환성)
    static func from(_ gustDifference: Double) -> GustDifferenceLevel {
        switch gustDifference {
        case WeatherThresholds.gustDifferenceDanger...: return .danger
        case WeatherThresholds.gustDifferenceCaution..<WeatherThresholds.gustDifferenceDanger: return .caution
        default: return .safe
        }
    }
}

/// 순간 풍속 증가량 계산 결과
struct GustDifferenceResult {
    let meanWindMS: Double              // 평균풍 (m/s)
    let gustWindMS: Double              // 돌풍 (m/s)
    let gustDifferenceMS: Double        // 순간 풍속 증가량 (m/s)
    let gustFactor: Double              // NEW: Gust Factor (gust/sustained)
    let gustSource: String              // NEW: "observed" or "estimated(×1.3)"
    let level: GustDifferenceLevel
    let rationale: String               // 사용자 메시지
    let debugInfo: String               // NEW: 판정 근거 상세
    let votes: (danger: Int, caution: Int)  // NEW: 3축 투표 결과
    let floorMet: Bool                  // NEW: Floor 충족 여부
    let hardStop: Bool                  // NEW: 하드-스톱 발동 여부
}

/// 순간 풍속 증가량 계산기 (3축 판정 + 2-out-of-3 투표 + 히스테리시스)
struct GustDifferenceCalculator {

    // 상태 보존 (히스테리시스용)
    private static var previousLevel: GustDifferenceLevel = .safe
    private static var previousLocalizedVotes: Int = 0  // 국지 돌풍 이전 투표수

    /// 3축 판정 + 2-out-of-3 투표 + 하드스톱 + 히스테리시스
    mutating func evaluate(
        meanWindMS: Double,
        gustWindMS: Double?,
        category: DroneCategory,
        droneMakeModel: DroneMakeModel? = nil,
        locationFactor: Double = 1.0
    ) -> GustDifferenceResult? {

        guard meanWindMS >= 0 else { return nil }

        // ========== 1. 돌풍값 처리 (추정계수 정책화) ==========
        let gust: Double
        let gustSource: String

        if let g = gustWindMS {
            gust = max(g, meanWindMS)
            gustSource = "observed"
        } else {
            let estimatedGF = GustEvaluationConstants.estimatedGFBase * locationFactor
            gust = meanWindMS * estimatedGF
            gustSource = "estimated(×\(estimatedGF.rounded2))"
        }

        let gustDiff = max(0, gust - meanWindMS)

        // ========== 2. GF 계산 (저평균풍 폭주 방지) ==========
        let rawGF = meanWindMS > 0 ? gust / meanWindMS : .infinity
        let gustFactor: Double
        let gfEvaluable: Bool

        if meanWindMS >= GustEvaluationConstants.meanMinForGF {
            gustFactor = min(rawGF, GustEvaluationConstants.gfCap)
            gfEvaluable = true
        } else {
            gustFactor = 1.0
            gfEvaluable = false
        }

        // ========== 3. 임계값 가져오기 (기체별 오버라이드 우선) ==========
        let diffThresholds = category.gustDifferenceThresholds
        let gfThresholds = category.gustFactorThresholds
        let absThresholds = droneMakeModel?.absoluteWindOverride ?? category.absoluteWindThresholds
        let floor = category.minimumSustainedWind

        // ========== 4. 하드-스톱 체크 (즉시 위험) ==========
        let hardStop = (gust >= absThresholds.gustDanger + GustEvaluationConstants.hardStopMargin)
                    || (meanWindMS >= absThresholds.sustainedDanger + GustEvaluationConstants.hardStopMargin)

        if hardStop {
            let result = GustDifferenceResult(
                meanWindMS: meanWindMS,
                gustWindMS: gust,
                gustDifferenceMS: gustDiff,
                gustFactor: gustFactor,
                gustSource: gustSource,
                level: .danger,
                rationale: "🚨 기체 스펙 초과 (하드-스톱) - 즉시 착륙 필요",
                debugInfo: buildDebugInfo(
                    mean: meanWindMS, gust: gust, diff: gustDiff, gf: gustFactor,
                    source: gustSource, votes: (3, 3), floor: floor, floorMet: meanWindMS >= floor,
                    hardStop: true, axes: "N/A (하드-스톱)"
                ),
                votes: (danger: 3, caution: 3),
                floorMet: meanWindMS >= floor,
                hardStop: true
            )
            Self.previousLevel = .danger
            return result
        }

        // ========== 5. Floor 체크 (국지 돌풍: 등급별 정책) ==========
        if meanWindMS < floor {
            // 기체별 오버라이드 적용
            let policy = category.localizedGustPolicy.withModelOverride(
                droneMakeModel?.absoluteWindOverride
            )

            // 저평균풍 구간 보정 (0.8~1.0 m/s에서 과민 억제)
            var lgDiff = policy.diff
            if meanWindMS >= GustEvaluationConstants.lgLowMeanMin
                && meanWindMS < GustEvaluationConstants.lgLowMeanMax {
                lgDiff += GustEvaluationConstants.lgLowMeanDiffBoost
            }

            // 3축 평가 (국지 돌풍 전용 임계값)
            let aPrime = (gustDiff >= lgDiff)
            let bPrime = (meanWindMS >= policy.minMeanForEval)
                         && gfEvaluable
                         && (gustFactor >= policy.gf)
            let cPrime = (gust >= policy.absGust)

            // 투표
            let votes = [aPrime, bPrime, cPrime].filter { $0 }.count

            // 히스테리시스 적용 (깜빡임 방지)
            let triggered: Bool
            if Self.previousLevel == .localizedGust {
                // 국지 돌풍에서 끄려면 hysteresisMinVotes 이하여야 함
                triggered = (votes > policy.hysteresisMinVotes)
            } else {
                // 켜려면 votesRequired 이상이어야 함
                triggered = (votes >= policy.votesRequired)
            }

            let level: GustDifferenceLevel = triggered ? .localizedGust : .safe
            let rationale = triggered
                ? "평균풍 낮음 (\(meanWindMS.rounded1)<\(floor)m/s). 국지 돌풍 주의 (\(votes)표/필요 \(policy.votesRequired)표)"
                : "안전 (평균풍 낮음, 돌풍 신호 부족: \(votes)표)"

            // 디버그 정보 강화 (정책 버전, 각 축 상세)
            let axes = """
            [국지 돌풍 축 - v1.0]
            A'(증가량): \(aPrime ? "충족" : "미충족") (실측: \(gustDiff.rounded1) / 기준: \(lgDiff.rounded1)m/s)
            B'(GF): \(bPrime ? "충족" : "미충족") (실측: \(gustFactor.rounded2) / 기준: \(policy.gf.rounded2))
            C'(절대gust): \(cPrime ? "충족" : "미충족") (실측: \(gust.rounded1) / 기준: \(policy.absGust.rounded1)m/s)

            투표: \(votes)/3표 (필요: \(policy.votesRequired)표, 끄기: ≤\(policy.hysteresisMinVotes)표)
            Floor: \(floor.rounded1)m/s
            GF 평가: \(gfEvaluable ? "가능" : "불가 (mean<\(policy.minMeanForEval))")
            저평균풍 보정: \(meanWindMS < GustEvaluationConstants.lgLowMeanMax ? "적용 (+\(GustEvaluationConstants.lgLowMeanDiffBoost)m/s)" : "없음")
            """

            let result = GustDifferenceResult(
                meanWindMS: meanWindMS,
                gustWindMS: gust,
                gustDifferenceMS: gustDiff,
                gustFactor: gustFactor,
                gustSource: gustSource,
                level: level,
                rationale: rationale,
                debugInfo: buildDebugInfo(
                    mean: meanWindMS, gust: gust, diff: gustDiff, gf: gustFactor,
                    source: gustSource, votes: (0, 0), floor: floor, floorMet: false,
                    hardStop: false, axes: axes
                ),
                votes: (danger: 0, caution: 0),
                floorMet: false,
                hardStop: false
            )

            Self.previousLevel = level
            Self.previousLocalizedVotes = votes
            return result
        }

        // ========== 6. 3축 평가 ==========

        // 축A: Gust Difference
        let isDangerByDiff = gustDiff >= diffThresholds.danger
        let isCautionByDiff = gustDiff >= diffThresholds.caution

        // 축B: Gust Factor (평가 가능할 때만)
        let isDangerByGF = gfEvaluable && gustFactor >= gfThresholds.danger
        let isCautionByGF = gfEvaluable && gustFactor >= gfThresholds.caution

        // 축C: Absolute Wind
        let isDangerByAbsolute = (meanWindMS >= absThresholds.sustainedDanger)
                              || (gust >= absThresholds.gustDanger)
        let isCautionByAbsolute = (meanWindMS >= absThresholds.sustainedCaution)
                               || (gust >= absThresholds.gustCaution)

        // ========== 7. 2-out-of-3 투표 ==========
        let dangerVotes = [isDangerByDiff, isDangerByGF, isDangerByAbsolute].filter { $0 }.count
        let cautionVotes = [isCautionByDiff, isCautionByGF, isCautionByAbsolute].filter { $0 }.count

        // ========== 8. 초기 레벨 결정 ==========
        var proposedLevel: GustDifferenceLevel
        var rationale: String

        if dangerVotes >= 2 {
            proposedLevel = .danger
            rationale = "강한 돌풍 위험 (3축 중 \(dangerVotes)표) - 비행 자제"
        } else if cautionVotes >= 2 || dangerVotes == 1 {
            proposedLevel = .caution
            rationale = "돌풍 주의 (3축 중 주의\(cautionVotes)표, 위험\(dangerVotes)표) - 숙련자만"
        } else {
            proposedLevel = .safe
            rationale = "안전 (모든 축 임계 미만)"
        }

        // ========== 9. 히스테리시스 적용 ==========
        let finalLevel = applyHysteresis(
            proposed: proposedLevel,
            previous: Self.previousLevel,
            dangerVotes: dangerVotes,
            cautionVotes: cautionVotes
        )

        // ========== 10. 디버그 정보 ==========
        let axesInfo = """
        축A (증가량): \(isDangerByDiff ? "위험" : isCautionByDiff ? "주의" : "안전")
        축B (GF): \(gfEvaluable ? (isDangerByGF ? "위험" : isCautionByGF ? "주의" : "안전") : "평가 안함(mean<\(GustEvaluationConstants.meanMinForGF))")
        축C (절대값): \(isDangerByAbsolute ? "위험" : isCautionByAbsolute ? "주의" : "안전")
        """

        let debugInfo = buildDebugInfo(
            mean: meanWindMS, gust: gust, diff: gustDiff, gf: gustFactor,
            source: gustSource, votes: (dangerVotes, cautionVotes),
            floor: floor, floorMet: true, hardStop: false, axes: axesInfo
        )

        let result = GustDifferenceResult(
            meanWindMS: meanWindMS,
            gustWindMS: gust,
            gustDifferenceMS: gustDiff,
            gustFactor: gustFactor,
            gustSource: gustSource,
            level: finalLevel,
            rationale: rationale + (finalLevel != proposedLevel ? " (히스테리시스)" : ""),
            debugInfo: debugInfo,
            votes: (danger: dangerVotes, caution: cautionVotes),
            floorMet: true,
            hardStop: false
        )

        Self.previousLevel = finalLevel
        return result
    }

    // MARK: - 히스테리시스 로직

    private func applyHysteresis(
        proposed: GustDifferenceLevel,
        previous: GustDifferenceLevel,
        dangerVotes: Int,
        cautionVotes: Int
    ) -> GustDifferenceLevel {

        // 위험 → 안전/주의로 내려갈 때: 위험 투표가 1개 이하일 때만 허용
        if previous == .danger && proposed < .danger {
            if dangerVotes <= 1 {
                return proposed
            } else {
                return .danger
            }
        }

        // 주의 → 안전으로 내려갈 때: 주의 투표가 0개일 때만 허용
        if previous == .caution && proposed == .safe {
            if cautionVotes == 0 {
                return .safe
            } else {
                return .caution
            }
        }

        // 그 외 (올라갈 때, 동일 레벨): 즉시 반영
        return proposed
    }

    // MARK: - 디버그 정보 생성

    private func buildDebugInfo(
        mean: Double, gust: Double, diff: Double, gf: Double,
        source: String, votes: (Int, Int), floor: Double, floorMet: Bool,
        hardStop: Bool, axes: String
    ) -> String {
        return """
        [판정 근거]
        평균풍: \(mean.rounded1) m/s
        돌풍: \(gust.rounded1) m/s (\(source))
        증가량: \(diff.rounded1) m/s
        GF: \(gf.rounded2)

        \(axes)

        투표: 위험 \(votes.0)/3, 주의 \(votes.1)/3
        Floor: \(floorMet ? "충족" : "미달 (\(floor)m/s)")
        하드-스톱: \(hardStop ? "YES" : "NO")
        """
    }
}

// Double 반올림 Extension
private extension Double {
    var rounded1: Double { (self * 10).rounded() / 10 }
    var rounded2: Double { (self * 100).rounded() / 100 }
}

/// CRI 계산 결과
struct CRIResult {
    let value: Double           // 0-100
    let level: CRILevel
    let temperature: Double
    let dewPoint: Double
    let dewPointDiff: Double
}

/// CRI 상태 관리 (히스테리시스 적용)
struct CRIState {
    var level: CRIWarningLevel = .safe

    /// 비대칭 임계값으로 깜빡임 방지
    mutating func transition(smoothedCRI: Double) {
        switch level {
        case .safe:
            if smoothedCRI >= 40 {
                level = .caution
            }
        case .caution:
            if smoothedCRI >= 70 {
                level = .warning
            } else if smoothedCRI <= 35 {
                level = .safe
            }
        case .warning:
            if smoothedCRI <= 65 {
                level = .caution
            }
        }
    }
}

/// 시간별 날씨 데이터
struct HourlyWeatherData: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double        // °C
    let windSpeed: Double           // m/s
    let windDirection: Double       // degrees (0-360)
    let windGust: Double?           // m/s (Optional)
    let gustDifference: Double      // m/s (순간 풍속 증가량)
    let precipitation: Double       // mm
    let visibility: Double          // km
    let dewPoint: Double            // °C
    let cri: Double                 // 0-100
}

/// Apple WeatherKit을 사용한 날씨 정보 관리 매니저
@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    // MARK: - Published Properties

    /// 풍속 (m/s)
    @Published var windSpeed: Double?

    /// 풍향 (각도, 0-360)
    @Published var windDirection: Double?

    /// 돌풍 (m/s)
    @Published var windGust: Double?

    /// 강수 강도 (mm/h)
    @Published var precipitationIntensity: Double?

    /// 날씨 상태
    @Published var weatherCondition: WeatherCondition?

    /// 온도 (°C)
    @Published var temperature: Double?

    /// 가시거리 (km)
    @Published var visibility: Double?

    /// 이슬점 (°C)
    @Published var dewPoint: Double?

    /// CRI 지수 (0-100)
    @Published var criValue: Double?

    /// CRI 위험도
    @Published var criLevel: CRILevel = .low

    /// CRI 상태 (히스테리시스 적용)
    @Published private(set) var criState: CRIState = CRIState()

    /// 결빙 위험 플래그
    @Published var icingRisk: Bool = false

    /// 순간 풍속 증가량 (m/s)
    @Published var gustDifference: Double?

    /// 순간 풍속 증가량 위험도
    @Published var gustDifferenceLevel: GustDifferenceLevel = .safe

    /// 로딩 상태
    @Published var isLoading: Bool = false

    /// 에러 메시지
    @Published var errorMessage: String?

    /// 마지막 업데이트 시간
    @Published var lastUpdateTime: Date?

    /// 시간별 예보 데이터 (설정된 일수만큼)
    @Published var hourlyForecast: [HourlyWeatherData] = []

    /// 위치 정확도 (m)
    @Published var locationAccuracy: Double?

    /// GPS 사용 가능 여부 (정확도 50m 이하면 GPS 사용 중으로 간주)
    @Published var isUsingGPS: Bool = false

    /// 일출 시간 (오늘, WeatherKit에서 가져옴)
    @Published var sunriseTime: Date?

    /// 일몰 시간 (오늘, WeatherKit에서 가져옴)
    @Published var sunsetTime: Date?

    /// 내일 일출 시간 (WeatherKit에서 가져옴)
    @Published var tomorrowSunriseTime: Date?

    /// 내일 일몰 시간 (WeatherKit에서 가져옴)
    @Published var tomorrowSunsetTime: Date?

    // MARK: - Private Properties

    private let weatherService = WeatherService.shared
    private var cancellables = Set<AnyCancellable>()

    /// CRI 이동평균 버퍼 (5틱)
    private var criMovingAverage: [Double] = []

    private init() {
        setupLocationObserver()
        setupAutoUpdateTimer()
    }

    // MARK: - Public Methods

    /// 날씨 데이터 가져오기
    /// - Parameters:
    ///   - location: 위치 정보 (nil인 경우 LocationManager의 현재 위치 사용)
    ///   - forceRefresh: 강제 새로고침 여부
    @MainActor
    func fetchWeatherData(for location: CLLocation? = nil, forceRefresh: Bool = false) async {
        // 위치 정보 확인
        let targetLocation = location ?? LocationManager.shared.currentLocation

        guard let targetLocation = targetLocation else {
            errorMessage = "위치 정보를 가져올 수 없습니다"
            return
        }

        // 로딩 시작
        isLoading = true
        errorMessage = nil

        // 위치 정확도 저장
        locationAccuracy = targetLocation.horizontalAccuracy
        isUsingGPS = targetLocation.horizontalAccuracy <= 50.0

        do {
            // WeatherKit으로 현재 날씨 정보 가져오기
            let weather = try await weatherService.weather(for: targetLocation)
            let currentWeather = weather.currentWeather

            // 데이터 업데이트
            windSpeed = currentWeather.wind.speed.converted(to: .metersPerSecond).value // m/s
            windDirection = currentWeather.wind.direction.value // degrees
            windGust = currentWeather.wind.gust?.converted(to: .metersPerSecond).value // m/s (Optional)
            temperature = currentWeather.temperature.converted(to: .celsius).value // °C
            visibility = currentWeather.visibility.value / 1000.0 // m -> km
            dewPoint = currentWeather.dewPoint.converted(to: .celsius).value // °C

            // 현재 강수 강도 (mm/h) - 실제 현재 내리는 강수량
            // 비, 눈, 진눈깨비 모두 포함
            precipitationIntensity = currentWeather.precipitationIntensity.value // mm/h

            // 날씨 상태 (비, 눈, 진눈깨비 등)
            weatherCondition = currentWeather.condition

            // CRI 계산
            if let criResult = calculateCurrentCRI() {
                criValue = criResult.value
                criLevel = criResult.level
            }

            // 순간 풍속 증가량 계산
            if let gdResult = calculateCurrentGustDifference() {
                gustDifference = gdResult.gustDifferenceMS
                gustDifferenceLevel = gdResult.level
            }

            // 일출/일몰 시간 가져오기 (DayWeather) - 날짜 기반 필터링
            let dailyForecastArray = Array(weather.dailyForecast)
            let calendar = Calendar.current
            let now = Date()

            // 오늘과 내일의 정확한 날짜 경계 계산
            let today = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

            // 오늘 데이터 찾기 (날짜 명시적 비교)
            let todayData = dailyForecastArray.first { dayWeather in
                calendar.isDate(dayWeather.date, inSameDayAs: today)
            }

            if let todayData = todayData {
                sunriseTime = todayData.sun.sunrise
                sunsetTime = todayData.sun.sunset
                print("   - 오늘 일출: \(sunriseTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
                print("   - 오늘 일몰: \(sunsetTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
            } else {
                print("   ⚠️ 오늘 날짜의 일출/일몰 데이터를 찾을 수 없습니다.")
            }

            // 내일 데이터 찾기 (날짜 명시적 비교)
            let tomorrowData = dailyForecastArray.first { dayWeather in
                calendar.isDate(dayWeather.date, inSameDayAs: tomorrow)
            }

            if let tomorrowData = tomorrowData {
                tomorrowSunriseTime = tomorrowData.sun.sunrise
                tomorrowSunsetTime = tomorrowData.sun.sunset
                print("   - 내일 일출: \(tomorrowSunriseTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
                print("   - 내일 일몰: \(tomorrowSunsetTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
            } else {
                print("   ⚠️ 내일 날짜의 일출/일몰 데이터를 찾을 수 없습니다.")
            }

            // N일 예보 데이터 가져오기 (1시간 전부터 N일 후까지)
            // 이미 위에서 now 변수 선언됨
            let startDate = now.addingTimeInterval(-3600) // 1시간 전
            let endDate = now.addingTimeInterval(Double(FORECAST_DAYS) * 24 * 60 * 60)
            hourlyForecast = weather.hourlyForecast.forecast
                .filter { $0.date >= startDate && $0.date <= endDate }
                .map { hourlyData in
                    let temp = hourlyData.temperature.converted(to: .celsius).value
                    let dew = hourlyData.dewPoint.converted(to: .celsius).value
                    let wind = hourlyData.wind.speed.converted(to: .metersPerSecond).value

                    // 극값 안정화
                    let tc = max(-80.0, min(60.0, temp))
                    let dc = max(-80.0, min(60.0, dew))
                    let dT = max(0.0, tc - dc)

                    // ΔT 채널
                    let cri_dt = max(1.0, min(100.0, 100.0 - 10.0 * dT))

                    // 습도 채널 (Magnus 공식)
                    let a = 17.625, b = 243.04
                    let rhPercent = 100.0 * exp((a * dc) / (b + dc)) / exp((a * tc) / (b + tc))
                    let cri_rh = max(0.0, min(100.0, rhPercent))

                    // 합성
                    var cri = max(cri_dt, cri_rh)

                    // 풍속 보정 + RH 바닥선
                    if wind >= 5.0 {
                        cri *= 0.8
                    } else if wind >= 2.0 {
                        cri *= 0.9
                    }
                    cri = max(cri, cri_rh)
                    let finalCRI = max(1.0, min(100.0, cri)).rounded()

                    // 순간 풍속 증가량 계산
                    let meanWind = hourlyData.wind.speed.converted(to: .metersPerSecond).value
                    let gustWind = hourlyData.wind.gust?.converted(to: .metersPerSecond).value
                    let gust = max(gustWind ?? meanWind, meanWind)
                    let gd = max(0, gust - meanWind)

                    return HourlyWeatherData(
                        date: hourlyData.date,
                        temperature: temp,
                        windSpeed: hourlyData.wind.speed.converted(to: .metersPerSecond).value,
                        windDirection: hourlyData.wind.direction.value,
                        windGust: hourlyData.wind.gust?.converted(to: .metersPerSecond).value,
                        gustDifference: gd,
                        precipitation: hourlyData.precipitationAmount.value,
                        visibility: hourlyData.visibility.value / 1000.0, // m -> km
                        dewPoint: dew,
                        cri: finalCRI
                    )
                }

            lastUpdateTime = Date()
            isLoading = false

            print("✅ WeatherManager: 날씨 데이터 업데이트 완료")
            print("   - 위치 정확도: \(locationAccuracy ?? 0)m (GPS: \(isUsingGPS ? "사용" : "미사용"))")
            print("   - 풍속: \(windSpeed ?? 0) m/s")
            print("   - 풍향: \(windDirection ?? 0)°")
            print("   - 돌풍: \(windGust ?? 0) m/s")
            print("   - 순간 풍속 증가량: \(gustDifference ?? 0) m/s (\(gustDifferenceLevel.description))")
            print("   - 온도: \(temperature ?? 0)°C")
            print("   - 가시거리: \(visibility ?? 0) km")
            print("   - 강수량: \(precipitationIntensity ?? 0) mm/h")
            print("   - 이슬점: \(dewPoint ?? 0)°C")
            print("   - CRI: \(criValue ?? 0) (\(criLevel.description))")
            print("   - \(FORECAST_DAYS)일 예보: \(hourlyForecast.count)개 데이터")

        } catch {
            errorMessage = "날씨 정보를 가져오는데 실패했습니다: \(error.localizedDescription)"
            isLoading = false
            print("❌ WeatherManager 에러: \(error.localizedDescription)")
        }
    }

    // MARK: - CRI Calculation Methods

    /// 현재 CRI 계산 (병렬 채널 + 풍속 보정 + 히스테리시스)
    func calculateCurrentCRI() -> CRIResult? {
        guard let temp = temperature,
              let dew = dewPoint else { return nil }

        // 극값 안정화 (-80°C ~ +60°C)
        let tc = max(-80.0, min(60.0, temp))
        let dc = max(-80.0, min(60.0, dew))
        let dT = max(0.0, tc - dc)

        // 채널 1: ΔT 기반 (기울기 10)
        let cri_dt = max(1.0, min(100.0, 100.0 - 10.0 * dT))

        // 채널 2: 상대습도 기반
        // Magnus 공식으로 상대습도 계산 (WeatherKit에서 humidity 제공 안 함)
        let rhPercent = calculateRelativeHumidity(temp: tc, dew: dc)
        let cri_rh = max(0.0, min(100.0, rhPercent))

        // 보수적 합성: 더 위험한 채널 채택
        var cri = max(cri_dt, cri_rh)

        // 풍속 보정 (RH 바닥선 유지)
        if let wind = windSpeed {
            if wind >= 5.0 {
                cri *= 0.8  // 20% 감소
            } else if wind >= 2.0 {
                cri *= 0.9  // 10% 감소
            }
            // 풍속 보정 후에도 RH 이하로는 낮추지 않음
            cri = max(cri, cri_rh)
        }

        // 최종 범위 제한
        cri = max(1.0, min(100.0, cri))

        // 이동평균 적용 (5틱)
        criMovingAverage.append(cri)
        if criMovingAverage.count > 5 {
            criMovingAverage.removeFirst()
        }
        let smoothedCRI = criMovingAverage.reduce(0.0, +) / Double(criMovingAverage.count)

        // 히스테리시스 상태 전환
        criState.transition(smoothedCRI: smoothedCRI)

        // 결빙 위험 체크 (영하 온도 + 고습)
        icingRisk = (tc <= 0.0 && rhPercent >= 80.0)

        return CRIResult(
            value: smoothedCRI.rounded(),
            level: CRILevel.from(smoothedCRI),
            temperature: tc,
            dewPoint: dc,
            dewPointDiff: dT
        )
    }

    /// Magnus 공식으로 상대습도 계산
    private func calculateRelativeHumidity(temp: Double, dew: Double) -> Double {
        let a = 17.625
        let b = 243.04

        let numerator = exp((a * dew) / (b + dew))
        let denominator = exp((a * temp) / (b + temp))

        return 100.0 * (numerator / denominator)
    }

    // MARK: - Gust Difference Calculation Methods

    /// 현재 순간 풍속 증가량 계산
    func calculateCurrentGustDifference() -> GustDifferenceResult? {
        guard let meanWind = windSpeed else { return nil }

        var calculator = GustDifferenceCalculator()
        let category = SettingManager.shared.selectedDroneCategory
        // TODO: 추후 SettingManager에 selectedDroneMakeModel 추가 시 사용
        // let droneMakeModel = SettingManager.shared.selectedDroneMakeModel
        return calculator.evaluate(
            meanWindMS: meanWind,
            gustWindMS: windGust,
            category: category,
            droneMakeModel: nil,  // 기체별 오버라이드는 나중에 추가
            locationFactor: 1.0  // 환경별 가중치는 나중에 추가
        )
    }

    /// 6시간 선제 경고 (최악 CRI 찾기)
    func calculateUpcomingCRIRisk(hours: Int = 6) -> CRIResult? {
        let horizon = Date().addingTimeInterval(Double(hours) * 3600)

        var worstCRI = -Double.infinity
        var worstResult: CRIResult?

        for hourData in hourlyForecast where hourData.date <= horizon {
            let diff = hourData.temperature - hourData.dewPoint
            let cri = hourData.cri

            if cri > worstCRI {
                worstCRI = cri
                worstResult = CRIResult(
                    value: cri,
                    level: CRILevel.from(cri),
                    temperature: hourData.temperature,
                    dewPoint: hourData.dewPoint,
                    dewPointDiff: diff
                )
            }
        }

        return worstResult
    }

    // MARK: - Private Methods

    /// LocationManager의 위치 업데이트 관찰
    private func setupLocationObserver() {
        NotificationCenter.default.publisher(for: NSNotification.Name("LocationDidUpdate"))
            .compactMap { $0.userInfo?["location"] as? CLLocation }
            .sink { [weak self] location in
                Task { [weak self] in
                    await self?.fetchWeatherData(for: location, forceRefresh: false)
                }
            }
            .store(in: &cancellables)
    }

    /// 3분마다 자동으로 날씨 데이터 업데이트
    private func setupAutoUpdateTimer() {
        // 3분(180초)마다 자동 업데이트
        Timer.publish(every: 180, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchWeatherData(forceRefresh: true)
                }
            }
            .store(in: &cancellables)

        print("✅ WeatherManager: 3분 자동 업데이트 타이머 설정 완료")
    }
}

// MARK: - Helper Extensions

extension WeatherManager {
    /// 풍속을 문자열로 반환
    var windSpeedString: String {
        guard let windSpeed = windSpeed else { return "-" }
        return String(format: "%.1f m/s", windSpeed)
    }

    /// 돌풍을 문자열로 반환
    var windGustString: String {
        guard let windGust = windGust else { return "-" }
        return String(format: "%.1f m/s", windGust)
    }

    /// 강수/강설 강도를 문자열로 반환 (날씨 상태에 따라 자동 전환)
    var precipitationString: String {
        guard let intensity = precipitationIntensity else { return "-" }

        // 눈이 오는 경우 cm/h로 변환하여 표시
        if isSnowing {
            let snowIntensityCm = intensity / 10.0 // mm/h -> cm/h
            return String(format: "%.1f cm/h", snowIntensityCm)
        }
        // 비가 오는 경우 mm/h로 표시
        return String(format: "%.1f mm/h", intensity)
    }

    /// 눈이 오는지 여부
    var isSnowing: Bool {
        guard let condition = weatherCondition else { return false }
        switch condition {
        case .snow, .blowingSnow, .heavySnow, .flurries:
            return true
        default:
            return false
        }
    }

    /// 강수/강설 라벨 (날씨 상태에 따라 자동 전환)
    var precipitationLabel: String {
        return isSnowing ? NSLocalizedString("weather.element.snowfall", comment: "Snowfall") : NSLocalizedString("weather.element.precipitation", comment: "Precipitation")
    }

    /// 온도를 문자열로 반환
    var temperatureString: String {
        guard let temperature = temperature else { return "-" }
        return String(format: "%.0f°", temperature)
    }

    /// 가시거리를 문자열로 반환
    var visibilityString: String {
        guard let visibility = visibility else { return "-" }
        return String(format: "%.1f km", visibility)
    }

    /// 풍향을 방위로 변환
    var windDirectionCompass: String {
        guard let direction = windDirection else { return "-" }

        let directions = [
            NSLocalizedString("weather.direction.n", comment: "North"),
            NSLocalizedString("weather.direction.ne", comment: "Northeast"),
            NSLocalizedString("weather.direction.e", comment: "East"),
            NSLocalizedString("weather.direction.se", comment: "Southeast"),
            NSLocalizedString("weather.direction.s", comment: "South"),
            NSLocalizedString("weather.direction.sw", comment: "Southwest"),
            NSLocalizedString("weather.direction.w", comment: "West"),
            NSLocalizedString("weather.direction.nw", comment: "Northwest")
        ]
        let index = Int((direction + 22.5) / 45.0) % 8
        return directions[index]
    }

    /// 풍향을 문자열로 반환 (방위 + 각도)
    var windDirectionString: String {
        guard let direction = windDirection else { return "-" }
        return String(format: "%@ %.0f°", windDirectionCompass, direction)
    }

    /// CRI를 문자열로 반환
    var criString: String {
        guard let cri = criValue else { return "-" }
        return String(format: "%.0f", cri)
    }

    /// CRI 색상 (SwiftUI Color용 이름)
    var criColorName: String {
        return criLevel.color
    }

    /// 순간 풍속 증가량를 문자열로 반환
    var gustDifferenceString: String {
        guard let gd = gustDifference else { return "-" }
        return String(format: "%.1f m/s", gd)
    }

    /// 순간 풍속 증가량 색상 (SwiftUI Color용 이름)
    var gustDifferenceColorName: String {
        return gustDifferenceLevel.color
    }

    /// 날씨 상태에 따른 동적 아이콘 이름
    var precipitationIconName: String {
        guard let condition = weatherCondition else {
            return "cloud" // 기본값
        }

        // 강수/강설이 있는 경우 강수 관련 아이콘
        let hasPrecipitation = (precipitationIntensity ?? 0) > 0

        if hasPrecipitation {
            // 강수/강설이 있을 때
            switch condition {
            case .rain, .heavyRain:
                return "cloud.rain"
            case .drizzle:
                return "cloud.drizzle"
            case .snow, .blowingSnow, .heavySnow, .flurries:
                return "cloud.snow"
            case .sleet, .freezingRain, .freezingDrizzle, .wintryMix:
                return "cloud.sleet"
            case .hail:
                return "cloud.hail"
            case .isolatedThunderstorms, .strongStorms, .thunderstorms, .scatteredThunderstorms:
                return "cloud.bolt.rain"
            default:
                return "cloud.rain"
            }
        } else {
            // 강수/강설이 없을 때 - 일반 날씨 아이콘
            switch condition {
            case .clear:
                return "sun.max"
            case .mostlyClear:
                return "sun.max"
            case .partlyCloudy:
                return "cloud.sun"
            case .mostlyCloudy:
                return "cloud"
            case .cloudy:
                return "cloud"
            case .foggy, .haze, .smoky:
                return "cloud.fog"
            case .breezy, .windy:
                return "wind"
            case .blizzard, .blowingDust, .blowingSnow:
                return "wind.snow"
            case .isolatedThunderstorms, .strongStorms, .thunderstorms, .scatteredThunderstorms:
                return "cloud.bolt"
            default:
                return "cloud"
            }
        }
    }

    // MARK: - 경고 레벨 Computed Properties

    /// 온도 경고 레벨
    var temperatureWarningLevel: TemperatureWarningLevel {
        guard let temp = temperature else { return .safe }
        return TemperatureWarningLevel.from(temp)
    }

    /// 풍속 경고 레벨 (드론 카테고리 반영)
    var windSpeedWarningLevel: WindSpeedWarningLevel {
        guard let speed = windSpeed else { return .safe }

        // SettingManager에서 선택된 드론 카테고리의 임계값 사용
        let category = SettingManager.shared.selectedDroneCategory
        let thresholds = category.windSpeedThresholds

        if speed >= thresholds.danger {
            return .danger
        } else if speed >= thresholds.caution {
            return .caution
        } else {
            return .safe
        }
    }

    /// 순간 풍속 증가량 경고 레벨 (드론 카테고리 반영)
    var gustDifferenceWarningLevel: GustDifferenceWarningLevel {
        guard let gd = gustDifference else { return .safe }

        // SettingManager에서 선택된 드론 카테고리의 임계값 사용
        let category = SettingManager.shared.selectedDroneCategory
        let thresholds = category.gustDifferenceThresholds

        if gd >= thresholds.danger {
            return .danger
        } else if gd >= thresholds.caution {
            return .caution
        } else {
            return .safe
        }
    }

    /// 강수/강설 강도 경고 레벨
    var precipitationWarningLevel: PrecipitationWarningLevel {
        // 비, 눈 모두 precipitationIntensity로 판단
        guard let intensity = precipitationIntensity else { return .none }
        return PrecipitationWarningLevel.from(intensity)
    }

    /// 가시거리 경고 레벨
    var visibilityWarningLevel: VisibilityWarningLevel {
        guard let vis = visibility else { return .moderate }
        return VisibilityWarningLevel.from(vis)
    }

    /// CRI 경고 레벨
    var criWarningLevel: CRIWarningLevel {
        guard let cri = criValue else { return .safe }
        return CRIWarningLevel.from(cri)
    }

    /// 날씨 상태를 한글로 반환 (Apple 공식 로컬라이제이션 사용)
    var weatherConditionString: String {
        guard let condition = weatherCondition else { return NSLocalizedString("weather.unknown", comment: "Unknown") }

        // WeatherCondition의 accessibilityDescription을 사용하여 Apple의 공식 번역 가져오기
        return condition.accessibilityDescription
    }

    // MARK: - 예보 최고/최저 온도

    /// 예보 기간 중 최고 온도
    var maxTemperature24h: Double? {
        guard !hourlyForecast.isEmpty else { return nil }
        return hourlyForecast.map { $0.temperature }.max()
    }

    /// 예보 기간 중 최저 온도
    var minTemperature24h: Double? {
        guard !hourlyForecast.isEmpty else { return nil }
        return hourlyForecast.map { $0.temperature }.min()
    }

    /// 최고 온도 문자열
    var maxTemperatureString: String {
        guard let temp = maxTemperature24h else { return "-" }
        return String(format: "%.0f°", temp)
    }

    /// 최저 온도 문자열
    var minTemperatureString: String {
        guard let temp = minTemperature24h else { return "-" }
        return String(format: "%.0f°", temp)
    }

    // MARK: - 날씨 추가 설명

    /// 날씨 추가 설명 (WeatherKit 공식 설명 사용)
    var weatherDescription: String {
        guard let condition = weatherCondition else { return "" }

        // WeatherKit의 공식 설명 사용
        return condition.description
    }

    /// 온도에 따른 그라데이션 색상 반환 (-10°C ~ 40°C 범위)
    var temperatureColor: Color {
        guard let temp = temperature else { return .gray }

        switch temp {
        case ..<(-10):
            return Color(hex: "#0072FF") // Cold Blue
        case -10..<7.5:
            return interpolateColor(
                from: Color(hex: "#0072FF"),
                to: Color(hex: "#00C8FF"),
                fraction: (temp + 10) / 17.5
            )
        case 7.5..<17.5:
            return interpolateColor(
                from: Color(hex: "#00C8FF"),
                to: Color(hex: "#A6E22E"),
                fraction: (temp - 7.5) / 10
            )
        case 17.5..<27.5:
            return interpolateColor(
                from: Color(hex: "#A6E22E"),
                to: Color(hex: "#FFA500"),
                fraction: (temp - 17.5) / 10
            )
        case 27.5..<40:
            return interpolateColor(
                from: Color(hex: "#FFA500"),
                to: Color(hex: "#FF3B30"),
                fraction: (temp - 27.5) / 12.5
            )
        default:
            return Color(hex: "#FF3B30") // Hot Red
        }
    }

    // MARK: - 예보 기간 관련

    /// 예보 기간 (시간)
    var forecastHours: Int {
        return FORECAST_DAYS * 24
    }

    /// 예보 기간 문자열 (로컬라이제이션용)
    var forecastPeriodString: String {
        if FORECAST_DAYS == 1 {
            return String(format: NSLocalizedString("weather.forecast.hours", comment: "24 Hours"), 24)
        } else {
            return String(format: NSLocalizedString("weather.forecast.days", comment: "N Days"), FORECAST_DAYS)
        }
    }
}

// MARK: - Color Extensions

extension Color {
    /// HEX 문자열로 Color 초기화
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 1)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}

/// RGB 값을 선형 보간하여 두 색상 사이의 중간 색상 반환
func interpolateColor(from: Color, to: Color, fraction: Double) -> Color {
    let fraction = max(0.0, min(1.0, fraction))
    let fromComponents = UIColor(from).cgColor.components ?? [0, 0, 0]
    let toComponents = UIColor(to).cgColor.components ?? [0, 0, 0]
    let r = fromComponents[0] + (toComponents[0] - fromComponents[0]) * fraction
    let g = fromComponents[1] + (toComponents[1] - fromComponents[1]) * fraction
    let b = fromComponents[2] + (toComponents[2] - fromComponents[2]) * fraction
    return Color(red: r, green: g, blue: b)
}
