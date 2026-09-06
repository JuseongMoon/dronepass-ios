//
//  KPIndexModel.swift
//  DronePass
//
//  Created by Claude Code
//

import Foundation
import SwiftUI

// MARK: - KP 지수 데이터 모델

/// KP 지수 단일 데이터 포인트
struct KPIndexData: Codable, Identifiable {
    var id: String { timeTag }
    let timeTag: String
    let kp: Double
    let observed: String?
    let noaaScale: String?

    /// 시간 문자열을 Date로 변환
    var date: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // 먼저 소수점 없는 형식 시도
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: timeTag) {
            return date
        }

        // 소수점 있는 형식 시도
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        if let date = formatter.date(from: timeTag) {
            return date
        }

        // ISO 8601 형식 시도 (NOAA SWPC API)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: timeTag)
    }

    /// 관측 상태 (observed, estimated, predicted)
    var observationStatus: ObservationStatus {
        guard let observed = observed else { return .observed }
        return ObservationStatus(rawValue: observed) ?? .observed
    }

    enum ObservationStatus: String {
        case observed = "observed"
        case estimated = "estimated"
        case predicted = "predicted"
    }
}

/// KP 지수 레벨 (G 등급 경보 체계)
enum KPLevel: String, CaseIterable {
    case normal = "Normal"
    case g1 = "G1"
    case g2 = "G2"
    case g3 = "G3"
    case g4 = "G4"
    case g5 = "G5"

    /// KP 값으로부터 레벨 판단
    static func level(from kp: Double) -> KPLevel {
        switch kp {
        case ..<5:
            return .normal
        case 5..<6:
            return .g1
        case 6..<7:
            return .g2
        case 7..<8:
            return .g3
        case 8..<9:
            return .g4
        default: // 9 이상
            return .g5
        }
    }

    /// 로컬라이즈된 레벨 이름
    var localizedName: String {
        switch self {
        case .normal:
            return NSLocalizedString("kp.level.normal.name", comment: "Normal")
        case .g1:
            return NSLocalizedString("kp.level.g1.name", comment: "G1 (Minor)")
        case .g2:
            return NSLocalizedString("kp.level.g2.name", comment: "G2 (Moderate)")
        case .g3:
            return NSLocalizedString("kp.level.g3.name", comment: "G3 (Strong)")
        case .g4:
            return NSLocalizedString("kp.level.g4.name", comment: "G4 (Severe)")
        case .g5:
            return NSLocalizedString("kp.level.g5.name", comment: "G5 (Extreme)")
        }
    }

    /// 레벨에 따른 색상
    var color: Color {
        switch self {
        case .normal:
            return Color(red: 0.0, green: 0.8, blue: 0.7) // 청록 - 안전
        case .g1:
            return Color(red: 0.0, green: 0.9, blue: 0.5) // 청록그린 - 정상
        case .g2:
            return Color(red: 0.75, green: 0.95, blue: 0.06) // 골드 - 경계
        case .g3:
            return Color(red: 1.0, green: 0.75, blue: 0.0) // 엠버 - 주의
        case .g4:
            return Color(red: 1.0, green: 0.4, blue: 0.0) // 딥오렌지 - 경고
        case .g5:
            return Color(red: 0.86, green: 0.08, blue: 0.24) // 크림슨 - 위험
        }
    }

    /// 레벨에 따른 아이콘
    var icon: String {
        switch self {
        case .normal:
            return "checkmark.circle.fill"
        case .g1:
            return "circle.fill"
        case .g2:
            return "circle.lefthalf.filled"
        case .g3:
            return "exclamationmark.circle.fill"
        case .g4:
            return "exclamationmark.triangle.fill"
        case .g5:
            return "xmark.octagon.fill"
        }
    }

    /// 경고가 필요한 레벨인지 (G1 이상)
    var isWarning: Bool {
        return self != .normal
    }
}

/// KP 지수 API 응답
struct KPIndexResponse {
    let data: [KPIndexData]
    let lastUpdated: Date

    /// 현재 KP 지수 (가장 최근 데이터)
    var currentKP: KPIndexData? {
        return data.last
    }

    /// 향후 24시간 예보 데이터
    var forecast24Hours: [KPIndexData] {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .hour, value: 24, to: now)!

        return data.filter { dataPoint in
            guard let date = dataPoint.date else { return false }
            return date >= now && date <= tomorrow
        }
    }
}

// MARK: - API 응답 디코딩 헬퍼

/// NOAA SWPC API 디코더 - 배열의 배열로 응답하므로 커스텀 디코딩 필요
struct KPIndexAPIDecoder {
    /// 현재 KP 지수 API 응답 디코딩
    static func decodeCurrentKP(from data: Data) throws -> [KPIndexData] {
        let decoder = JSONDecoder()
        let rawArray = try decoder.decode([[String?]].self, from: data)

        // 첫 번째 행은 헤더이므로 건너뜀
        guard rawArray.count > 1 else { return [] }

        var result: [KPIndexData] = []

        for row in rawArray.dropFirst() {
            guard row.count >= 2,
                  let timeTag = row[0],
                  let kpString = row[1],
                  let kp = Double(kpString) else {
                continue
            }

            let dataPoint = KPIndexData(
                timeTag: timeTag,
                kp: kp,
                observed: "observed",
                noaaScale: nil
            )
            result.append(dataPoint)
        }

        return result
    }

    /// NOAA SWPC 예보 API 응답 객체
    private struct ForecastAPIResponse: Codable {
        let time_tag: String
        let kp: Double
        let observed: String?
        let noaa_scale: String?
    }

    /// 예보 KP 지수 API 응답 디코딩
    static func decodeForecastKP(from data: Data) throws -> [KPIndexData] {
        print("🔄 [SWPC] 예보 데이터 디코딩 시작...")

        let decoder = JSONDecoder()

        do {
            let responses = try decoder.decode([ForecastAPIResponse].self, from: data)
            print("✅ [SWPC] JSON 디코딩 성공: \(responses.count)개 항목")

            let result = responses.map { response in
                KPIndexData(
                    timeTag: response.time_tag,
                    kp: response.kp,
                    observed: response.observed,
                    noaaScale: response.noaa_scale
                )
            }

            print("✅ [SWPC] 디코딩 완료: \(result.count)개 데이터 포인트")
            return result

        } catch {
            print("❌ [SWPC] JSON 디코딩 실패: \(error)")

            if let jsonString = String(data: data.prefix(500), encoding: .utf8) {
                print("📄 [SWPC] 응답 데이터 (첫 500바이트):\n\(jsonString)")
            }

            throw error
        }
    }
}

// MARK: - SWPC 27-Day Outlook API 디코더

/// SWPC 27일 예보 텍스트 파일 파서
/// 형식: YYYY MMM DD RadioFlux AIndex KpIndex
/// 예: 2025 Oct 06     150          15          4
struct SWPC27DayDecoder {
    /// 27일 예보 데이터 디코딩
    /// - Parameter data: 텍스트 형식의 27일 예보 데이터
    /// - Returns: 27일간의 KP 지수 데이터 배열
    static func decode27DayOutlook(from data: Data) throws -> [KPIndexData] {
        print("🔄 [27Day] 27일 예보 데이터 디코딩 시작...")

        guard let text = String(data: data, encoding: .utf8) else {
            print("❌ [27Day] UTF-8 텍스트 변환 실패")
            throw KPIndexError.decodingError
        }

        // 라인별로 분리 (헤더 및 주석 제외)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") && !$0.starts(with: ":") }

        guard !lines.isEmpty else {
            print("⚠️ [27Day] 유효한 데이터 라인이 없음")
            return []
        }

        print("📊 [27Day] \(lines.count)개 라인 발견")

        var result: [KPIndexData] = []

        // DateFormatter 설정
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy MMM dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for (index, line) in lines.enumerated() {
            // 공백으로 구분 (여러 공백 처리)
            let components = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            // 최소 6개 컬럼 필요: Year Month Day RadioFlux AIndex KpIndex
            guard components.count >= 6 else {
                print("⚠️ [27Day] 행 \(index): 컴포넌트 개수 부족 (\(components.count)개, 최소 6개 필요)")
                continue
            }

            // 날짜 파싱: "2025 Oct 06" → UTC 00:00:00
            let dateString = "\(components[0]) \(components[1]) \(components[2])"
            guard let date = formatter.date(from: dateString) else {
                print("❌ [27Day] 행 \(index): 날짜 파싱 실패 - \(dateString)")
                continue
            }

            // 정오(12:00 UTC)로 설정: 12시간(43200초) 추가
            let noonDate = date.addingTimeInterval(12 * 3600)

            // KP 값은 6번 인덱스 (마지막 컬럼)
            let kpString = components[5]
            guard let kp = Double(kpString) else {
                print("❌ [27Day] 행 \(index): KP 값을 Double로 변환 실패: \(kpString)")
                continue
            }

            // KPIndexData 형식으로 변환
            let timeTagFormatter = DateFormatter()
            timeTagFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            timeTagFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            timeTagFormatter.locale = Locale(identifier: "en_US_POSIX")
            let timeTag = timeTagFormatter.string(from: noonDate)

            // 개별 행 로그는 제거 (요약 로그만 유지)

            let dataPoint = KPIndexData(
                timeTag: timeTag,
                kp: kp,
                observed: "predicted",
                noaaScale: nil
            )

            result.append(dataPoint)
        }

        print("✅ [27Day] 디코딩 완료: \(result.count)개 데이터 포인트")
        return result
    }
}

// MARK: - GFZ Potsdam API 디코더

/// GFZ Potsdam nowcast 텍스트 파일 파서
/// 형식: YYYY MM DD hh.h hh._m days days_m Kp ap D
/// 예: 2025 10 12 18.0 19.50 34253.75000 34253.81250  4.667   39 0
struct GFZKPIndexDecoder {
    /// GFZ Potsdam nowcast 데이터 디코딩
    /// - Parameter data: 텍스트 형식의 nowcast 데이터
    /// - Returns: 현재 KP 지수 데이터 (가장 최근 유효 데이터)
    static func decodeNowcast(from data: Data) throws -> KPIndexData? {
        print("🔄 [GFZ] Nowcast 데이터 디코딩 시작...")

        guard let text = String(data: data, encoding: .utf8) else {
            print("❌ [GFZ] UTF-8 텍스트 변환 실패")
            throw KPIndexError.decodingError
        }

        // 라인별로 분리 (헤더 제외)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") }

        guard !lines.isEmpty else {
            print("⚠️ [GFZ] 유효한 데이터 라인이 없음")
            return nil
        }

        print("📊 [GFZ] \(lines.count)개 라인 발견")

        // 역순으로 검색하여 첫 번째 유효 데이터 찾기 (Kp >= 0)
        for line in lines.reversed() {
            print("📄 [GFZ] 라인 분석: \(line)")

            // 공백으로 구분 (여러 공백 처리)
            let components = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            // 최소 10개 컬럼 필요: YYYY MM DD hh.h hh._m days days_m Kp ap D
            guard components.count >= 10 else {
                print("⚠️ [GFZ] 컴포넌트 개수 부족: \(components.count)개 (최소 10개 필요)")
                continue
            }

            // 컬럼 파싱
            guard let year = Int(components[0]),
                  let month = Int(components[1]),
                  let day = Int(components[2]),
                  let hourFloat = Double(components[3]) else {
                print("⚠️ [GFZ] 날짜/시간 파싱 실패")
                continue
            }

            let hour = Int(hourFloat)

            // Kp 값은 7번 인덱스
            let kpString = components[7]
            guard let kp = Double(kpString) else {
                print("❌ [GFZ] KP 값을 Double로 변환 실패: \(kpString)")
                continue
            }

            // Kp < 0이면 무효 데이터 (아직 측정 안 됨)
            if kp < 0 {
                print("⚠️ [GFZ] 무효 KP 값 (< 0): \(kp), 이전 라인 확인")
                continue
            }

            // 날짜 생성
            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = month
            dateComponents.day = day
            dateComponents.hour = hour
            dateComponents.minute = 0
            dateComponents.second = 0
            dateComponents.timeZone = TimeZone(secondsFromGMT: 0)

            guard let date = Calendar.current.date(from: dateComponents) else {
                print("❌ [GFZ] 날짜 생성 실패")
                continue
            }

            // KPIndexData 형식으로 변환
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let timeTag = formatter.string(from: date)

            let dataPoint = KPIndexData(
                timeTag: timeTag,
                kp: kp,
                observed: "observed",
                noaaScale: nil
            )

            print("✅ [GFZ] 디코딩 완료 - 시간: \(timeTag), KP: \(kp)")
            return dataPoint
        }

        print("⚠️ [GFZ] 유효한 KP 데이터를 찾을 수 없음")
        return nil
    }
}
