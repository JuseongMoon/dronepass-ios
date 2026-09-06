//
//  KPIndexManager.swift
//  DronePass
//
//  Created by Claude Code
//

import Foundation
import Combine

/// KP 지수 관리 매니저 (싱글톤)
/// GFZ Potsdam과 NOAA SWPC API를 사용하여 하이브리드 방식으로 KP 지수 데이터를 가져옵니다.
/// - GFZ Potsdam: 현재 KP 지수 (110분마다 + 실시간 업데이트)
/// - NOAA SWPC: 예보 데이터 (3시간 간격)
final class KPIndexManager: ObservableObject {
    static let shared = KPIndexManager()

    // MARK: - Published Properties

    /// 현재 KP 지수 데이터
    @Published var currentKP: KPIndexData?

    /// 현재 KP 레벨
    @Published var currentLevel: KPLevel = .normal

    /// 예보 데이터 (향후 24시간)
    @Published var forecastData: [KPIndexData] = []

    /// 장기예보 데이터 (27일)
    @Published var longTermForecastData: [KPIndexData] = []

    /// 로딩 상태
    @Published var isLoading: Bool = false

    /// 에러 메시지
    @Published var errorMessage: String?

    // MARK: - Private Properties

    /// 마지막 업데이트 시간
    private var lastUpdateTime: Date?

    /// 캐시 유효 시간 (30분)
    private let cacheValidDuration: TimeInterval = 30 * 60

    /// API 엔드포인트
    private let gfzNowcastURL = "https://kp.gfz.de/app/files/Kp_ap_nowcast.txt"
    private let forecastKPURL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json"
    private let longTermForecastURL = "https://services.swpc.noaa.gov/text/27-day-outlook.txt"

    /// URLSession
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// Combine 구독 저장소
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // 싱글톤 패턴
        setupAutoUpdateTimer()
    }

    // MARK: - Public Methods

    /// KP 지수 데이터 가져오기 (캐시 고려)
    /// - Parameters:
    ///   - forceRefresh: true면 캐시 무시하고 새로 가져옴
    ///   - fetchGFZ: true면 GFZ 현재 KP 데이터 가져오기 (false면 기존 데이터 유지)
    ///   - fetchNOAA: true면 NOAA 예보 데이터 가져오기 (false면 기존 데이터 유지)
    func fetchKPData(forceRefresh: Bool = false, fetchGFZ: Bool = true, fetchNOAA: Bool = true) async {
        // 캐시 유효성 확인
        if !forceRefresh, let lastUpdate = lastUpdateTime,
           Date().timeIntervalSince(lastUpdate) < cacheValidDuration {
            print("✅ KP 지수 캐시 사용 (마지막 업데이트: \(lastUpdate))")
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        var sources: [String] = []
        if fetchGFZ { sources.append("GFZ(현재)") }
        if fetchNOAA { sources.append("SWPC(예보+27일)") }
        print("🔄 KP 지수 업데이트 시작 [\(timestamp)] - \(sources.joined(separator: " + "))")

        // 선택적으로 데이터 가져오기
        var gfzCurrent: KPIndexData? = nil
        var swpcForecast: [KPIndexData] = []
        var longTermForecast: [KPIndexData] = []

        if fetchGFZ && fetchNOAA {
            // 모두 가져올 때는 병렬 처리
            async let gfzResult = fetchGFZCurrentKP()
            async let swpcResult = fetchForecastData()
            async let longTermResult = fetch27DayOutlook()

            let results = await (
                (try? gfzResult) ?? nil,
                (try? swpcResult) ?? [],
                (try? longTermResult) ?? []
            )
            gfzCurrent = results.0
            swpcForecast = results.1
            longTermForecast = results.2
        } else if fetchGFZ {
            // GFZ만 가져오기
            gfzCurrent = try? await fetchGFZCurrentKP()
        } else if fetchNOAA {
            // NOAA만 가져오기 (병렬 처리)
            async let swpcResult = fetchForecastData()
            async let longTermResult = fetch27DayOutlook()

            let results = await (
                (try? swpcResult) ?? [],
                (try? longTermResult) ?? []
            )
            swpcForecast = results.0
            longTermForecast = results.1
        }

        // 현재 KP 결정 (우선순위: GFZ > SWPC 최근 observed > SWPC 최근 데이터)
        var finalCurrentKP: KPIndexData?
        var dataSource: String = ""

        // fetchGFZ가 true인 경우에만 디버그 출력 및 KP 결정
        if fetchGFZ {
            // 📊 디버깅: 모든 소스 데이터 출력
            print("📊 [Debug] ========== 데이터 소스 비교 ==========")
            if let gfzCurrent = gfzCurrent {
                print("📊 [Debug] GFZ 데이터: KP=\(gfzCurrent.kp), 시간=\(gfzCurrent.timeTag)")
            } else {
                print("⚠️ [Debug] GFZ 데이터 없음 (API 실패 또는 타임아웃)")
            }

            if let swpcObserved = swpcForecast.last(where: { $0.observationStatus == .observed }) {
                print("📊 [Debug] SWPC observed: KP=\(swpcObserved.kp), 시간=\(swpcObserved.timeTag)")
            } else {
                print("⚠️ [Debug] SWPC observed 데이터 없음")
            }

            if let swpcLast = swpcForecast.last {
                print("📊 [Debug] SWPC 최근: KP=\(swpcLast.kp), 시간=\(swpcLast.timeTag), 상태=\(swpcLast.observationStatus.rawValue)")
            } else {
                print("⚠️ [Debug] SWPC 데이터 없음")
            }
            print("📊 [Debug] ========================================")

            if let gfzCurrent = gfzCurrent {
                finalCurrentKP = gfzCurrent
                dataSource = "GFZ Potsdam"
                print("✅ 현재 KP: GFZ 소스 사용 - \(gfzCurrent.kp)")
            } else if let swpcObserved = swpcForecast.last(where: { $0.observationStatus == .observed }) {
                finalCurrentKP = swpcObserved
                dataSource = "NOAA SWPC (fallback, 최근 observed)"
                print("⚠️ 현재 KP: GFZ 실패, SWPC 최근 observed 사용 - 시간: \(swpcObserved.timeTag), KP: \(swpcObserved.kp)")
            } else if let swpcLast = swpcForecast.last {
                finalCurrentKP = swpcLast
                dataSource = "NOAA SWPC (fallback, 최근 데이터)"
                print("⚠️ 현재 KP: GFZ 실패, SWPC 최근 데이터 사용 - \(swpcLast.kp)")
            }

            // 🎯 최종 선택 결과
            if let kp = finalCurrentKP {
                print("🎯 [Debug] 최종 선택: \(dataSource) - KP=\(kp.kp), 시간=\(kp.timeTag)")
            } else {
                print("❌ [Debug] 모든 소스에서 데이터 가져오기 실패")
            }
        }

        await MainActor.run {
            // NOAA 데이터 업데이트 (fetchNOAA가 true인 경우에만)
            if fetchNOAA {
                if !swpcForecast.isEmpty {
                    self.forecastData = swpcForecast
                    print("✅ 예보 데이터 업데이트: \(swpcForecast.count)개")
                } else {
                    print("⚠️ 예보 데이터 실패, 기존 데이터 유지: \(self.forecastData.count)개")
                }

                if !longTermForecast.isEmpty {
                    self.longTermForecastData = longTermForecast
                    print("✅ 장기예보 데이터 업데이트: \(longTermForecast.count)개")
                } else {
                    print("⚠️ 장기예보 데이터 실패, 기존 데이터 유지: \(self.longTermForecastData.count)개")
                }
            }

            // GFZ 현재 KP 데이터 업데이트 (fetchGFZ가 true인 경우에만)
            if fetchGFZ {
                if let kp = finalCurrentKP {
                    self.currentKP = kp
                    self.currentLevel = KPLevel.level(from: kp.kp)
                    print("✅ 현재 KP 업데이트: \(kp.kp) (\(dataSource))")
                    print("   📊 레벨: \(self.currentLevel.rawValue)")
                } else {
                    print("⚠️ 현재 KP 실패, 기존 데이터 유지")
                }
            }

            // 에러 메시지 처리: 요청한 모든 소스가 실패한 경우에만 표시
            let gfzFailed = fetchGFZ && finalCurrentKP == nil
            let noaaFailed = fetchNOAA && swpcForecast.isEmpty && longTermForecast.isEmpty

            if (fetchGFZ && fetchNOAA && gfzFailed && noaaFailed) ||
               (fetchGFZ && !fetchNOAA && gfzFailed) ||
               (!fetchGFZ && fetchNOAA && noaaFailed) {
                self.errorMessage = "KP 지수 데이터를 가져올 수 없습니다"
                print("❌ 요청한 소스에서 데이터 가져오기 실패")
            } else {
                self.errorMessage = nil
                print("✅ KP 지수 업데이트 완료")
            }

            self.lastUpdateTime = Date()
            self.isLoading = false
        }
    }

    /// 경고 레벨인지 확인 (활동적 이상)
    var isWarningLevel: Bool {
        return currentLevel.isWarning
    }

    /// 현재 KP 값 문자열
    var currentKPString: String {
        guard let kp = currentKP else { return "-" }
        return String(format: "%.1f", kp.kp)
    }

    /// 현재 KP 측정 시간 (KST)
    var currentKPTimeKST: String {
        guard let kp = currentKP, let date = kp.date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "MM/dd h:mm a"
        return formatter.string(from: date)
    }

    /// 향후 48시간 예보 데이터 필터링 (과거 6시간 포함)
    var next48HoursForecast: [KPIndexData] {
        let now = Date()
        let pastThreshold = Calendar.current.date(byAdding: .hour, value: -6, to: now)!
        let futureThreshold = Calendar.current.date(byAdding: .hour, value: 48, to: now)!

        print("📊 [Filter] ========== 필터링 시작 ==========")
        print("📊 [Filter] forecastData 원본: \(forecastData.count)개")
        print("📊 [Filter] 현재 시간: \(now)")
        print("📊 [Filter] 과거 임계값 (-6h): \(pastThreshold)")
        print("📊 [Filter] 미래 임계값 (+48h): \(futureThreshold)")

        // 각 데이터 포인트 검사
        for (index, dataPoint) in forecastData.prefix(5).enumerated() {
            if let date = dataPoint.date {
                let inRange = date >= pastThreshold && date <= futureThreshold
                print("📊 [Filter] [\(index)] \(dataPoint.timeTag) → \(date) → \(inRange ? "✅ 포함" : "❌ 제외")")
            } else {
                print("📊 [Filter] [\(index)] \(dataPoint.timeTag) → ❌ 날짜 파싱 실패")
            }
        }

        if forecastData.count > 5 {
            print("📊 [Filter] ... (총 \(forecastData.count)개 중 처음 5개만 표시)")
        }

        let filtered = forecastData.filter { dataPoint in
            guard let date = dataPoint.date else { return false }
            return date >= pastThreshold && date <= futureThreshold
        }

        print("📊 [Filter] 필터링 후: \(filtered.count)개")
        print("📊 [Filter] ========== 필터링 종료 ==========")
        return filtered
    }

    // MARK: - Private Methods

    /// GFZ Potsdam nowcast 현재 데이터 가져오기
    private func fetchGFZCurrentKP() async throws -> KPIndexData? {
        print("🔄 [GFZ] 현재 KP 데이터 요청 시작...")

        guard let url = URL(string: gfzNowcastURL) else {
            print("❌ [GFZ] 잘못된 URL: \(gfzNowcastURL)")
            throw KPIndexError.invalidURL
        }

        print("🌐 [GFZ] URL 요청: \(url)")
        let (data, response) = try await session.data(from: url)

        print("✅ [GFZ] 데이터 수신 완료: \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [GFZ] HTTP 응답 변환 실패")
            throw KPIndexError.invalidResponse
        }

        print("📊 [GFZ] HTTP 상태 코드: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [GFZ] 잘못된 상태 코드: \(httpResponse.statusCode)")
            throw KPIndexError.invalidResponse
        }

        let current = try GFZKPIndexDecoder.decodeNowcast(from: data)

        if current == nil {
            print("⚠️ [GFZ] 데이터가 nil")
            throw KPIndexError.emptyData
        }

        return current
    }

    /// NOAA SWPC 예보 데이터 가져오기
    private func fetchForecastData() async throws -> [KPIndexData] {
        print("🔄 [SWPC] 예보 데이터 요청 시작...")

        guard let url = URL(string: forecastKPURL) else {
            print("❌ [SWPC] 잘못된 URL: \(forecastKPURL)")
            throw KPIndexError.invalidURL
        }

        print("🌐 [SWPC] URL 요청: \(url)")
        let (data, response) = try await session.data(from: url)

        print("✅ [SWPC] 데이터 수신 완료: \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [SWPC] HTTP 응답 변환 실패")
            throw KPIndexError.invalidResponse
        }

        print("📊 [SWPC] HTTP 상태 코드: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [SWPC] 잘못된 상태 코드: \(httpResponse.statusCode)")
            throw KPIndexError.invalidResponse
        }

        do {
            let forecast = try KPIndexAPIDecoder.decodeForecastKP(from: data)
            print("✅ [SWPC] 디코딩 성공: \(forecast.count)개 데이터")

            if forecast.isEmpty {
                print("❌ [SWPC] 데이터가 비어있음")
                throw KPIndexError.emptyData
            }

            return forecast
        } catch {
            print("❌ [SWPC] 디코딩 실패: \(error)")
            throw error
        }
    }

    /// SWPC 27일 장기예보 데이터 가져오기
    private func fetch27DayOutlook() async throws -> [KPIndexData] {
        print("🔄 [27Day] 장기예보 데이터 요청 시작...")

        guard let url = URL(string: longTermForecastURL) else {
            print("❌ [27Day] 잘못된 URL: \(longTermForecastURL)")
            throw KPIndexError.invalidURL
        }

        print("🌐 [27Day] URL 요청: \(url)")
        let (data, response) = try await session.data(from: url)

        print("✅ [27Day] 데이터 수신 완료: \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [27Day] HTTP 응답 변환 실패")
            throw KPIndexError.invalidResponse
        }

        print("📊 [27Day] HTTP 상태 코드: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [27Day] 잘못된 상태 코드: \(httpResponse.statusCode)")
            throw KPIndexError.invalidResponse
        }

        do {
            let longTermData = try SWPC27DayDecoder.decode27DayOutlook(from: data)
            print("✅ [27Day] 디코딩 성공: \(longTermData.count)개 데이터")

            if longTermData.isEmpty {
                print("❌ [27Day] 데이터가 비어있음")
                throw KPIndexError.emptyData
            }

            return longTermData
        } catch {
            print("❌ [27Day] 디코딩 실패: \(error)")
            throw error
        }
    }

    /// 5분마다 자동으로 KP 지수 데이터 업데이트
    private func setupAutoUpdateTimer() {
        // 5분(300초)마다 자동 업데이트
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchKPData(forceRefresh: true)
                }
            }
            .store(in: &cancellables)

        print("✅ KPIndexManager: 5분 자동 업데이트 타이머 설정 완료")
    }
}

// MARK: - Error Types

enum KPIndexError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyData
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "유효하지 않은 URL입니다."
        case .invalidResponse:
            return "서버 응답이 올바르지 않습니다."
        case .emptyData:
            return "데이터가 비어있습니다."
        case .decodingError:
            return "데이터 해석에 실패했습니다."
        }
    }
}
