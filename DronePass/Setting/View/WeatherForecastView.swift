//
//  WeatherInfoView.swift
//  DronePass
//
//  Created by 문주성 on 10/14/25.
//

import SwiftUI
import Charts

/// 현재 위치 기반 날씨 정보 뷰
struct WeatherForecastView: View {
    @ObservedObject var manager = WeatherManager.shared
    @ObservedObject var settingManager = SettingManager.shared
    @Environment(\.dismiss) var dismiss

    // 토스트 메시지 상태
    @State private var showToast = false
    @State private var toastMessage = ""

    // 날씨 정보 시트 표시 상태
    @State private var showWeatherInfo = false
    @State private var selectedWeatherElement: WeatherElementType? = nil

    // 초기 로드 여부 추적
    @State private var isInitialLoad = true

    // 성능 최적화: 캐시된 데이터
    @State private var cachedChartDates: [Date] = []
    @State private var cachedTemperatureYRange: ClosedRange<Double> = -30...50
    @State private var cachedTemperatureGradientStops: [Gradient.Stop] = []
    @State private var cachedPrecipitationYRange: ClosedRange<Double> = 0...10
    @State private var temperatureColorCache: [UUID: Color] = [:]


    // 경고 아이콘 타입
    enum WarningIconType {
        case none      // 안전 - 아이콘 없음
        case info      // 정보 - 노란색 원형 i
        case caution   // 주의 - 노란색 삼각형 느낌표
        case warning   // 경고 - 빨간색 원형 느낌표
    }

    // 날씨 요소 타입
    enum WeatherElementType: Hashable {
        case temperature
        case windSpeed
        case gustDifference
        case precipitation
        case visibility
        case cri
    }

    // MARK: - 경고 레벨 → 아이콘 변환

    private var temperatureWarningIcon: WarningIconType {
        switch manager.temperatureWarningLevel {
        case .safe:
            return .none
        case .lowTemp, .highTemp:
            return .caution
        }
    }

    private var windSpeedWarningIcon: WarningIconType {
        switch manager.windSpeedWarningLevel {
        case .safe:
            return .none
        case .caution:
            return .caution
        case .danger:
            return .warning
        }
    }

    private var gustDifferenceWarningIcon: WarningIconType {
        switch manager.gustDifferenceLevel {
        case .safe:
            return .none
        case .localizedGust:
            return .info
        case .caution:
            return .caution
        case .danger:
            return .warning
        }
    }

    private var gustDifferenceSubText: String? {
        if manager.gustDifferenceLevel == .localizedGust {
            return NSLocalizedString("weather.gust.warning", comment: "Local gust risk")
        }
        return nil
    }

    private var precipitationWarningIcon: WarningIconType {
        switch manager.precipitationWarningLevel {
        case .none:
            return .none
        case .detected:
            return .caution
        }
    }

    private var visibilityWarningIcon: WarningIconType {
        switch manager.visibilityWarningLevel {
        case .good:
            return .none
        case .moderate:
            return .caution
        case .poor:
            return .warning
        }
    }

    private var criWarningIcon: WarningIconType {
        switch manager.criWarningLevel {
        case .safe:
            return .none
        case .caution:
            return .caution
        case .warning:
            return .warning
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 일출/일몰 정보 카드
                    sunriseSunsetCard

                    // 현재 날씨 카드 (모든 정보 포함)
                    currentWeatherCard

                    // 예보 그래프들
                    if !manager.hourlyForecast.isEmpty {
                        // 온도 그래프
                        temperatureForecastChart

                        // 풍속 그래프
                        windSpeedForecastChart

                        // 순간풍속증가량 그래프
                        gustDifferenceForecastChart

                        // 강수량 그래프
                        precipitationForecastChart

                        // 가시거리 그래프
                        visibilityForecastChart

                        // 결로위험지수 그래프
                        criForecastChart
                    }

                    // 마지막 업데이트 시간
                    if let lastUpdateTime = manager.lastUpdateTime {
                        HStack {
                            Spacer()
                            Text(String(format: NSLocalizedString("weather.lastUpdate", comment: "Last update"), formatUpdateTime(lastUpdateTime)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Apple Weather 출처 표기 (Guideline 5.2.5 완전 준수)
                    HStack(spacing: 4) {
                        Spacer()
                        
                        // Apple Weather 상표
                        Text("Weather data provided by  Weather")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        // 법적 출처 링크 (반드시 이 URL 사용)
                        Link(NSLocalizedString("weather.legalNotice", comment: "Legal Notice"), destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 8)
                .padding(.top, 16)
            }
            .navigationTitle(NSLocalizedString("weather.navigation.title", comment: "Location-based Information"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showWeatherInfo = true
                    }) {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await manager.fetchWeatherData(forceRefresh: true)
                            // 수동 새로고침 완료 후 토스트 메시지 표시
                            if !isInitialLoad {
                                showToast = false
                                toastMessage = NSLocalizedString("weather.refresh", comment: "Refreshed")
                                showToast = true
                            }
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .toastMessage(isPresented: $showToast, message: $toastMessage)
            .sheet(isPresented: $showWeatherInfo) {
                WeatherInfoView(scrollToElement: nil)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedWeatherElement) { element in
                WeatherInfoView(scrollToElement: element)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
            }
            .task {
                // 캐시 업데이트만 수행 (자동 타이머가 3분마다 갱신)
                updateCaches()

                // 초기 로드 완료 표시 (토스트 메시지 없음)
                isInitialLoad = false
            }
        }
    }

    // MARK: - 일출/일몰 정보 카드

    private var sunriseSunsetCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("weather.section.sunriseSunset", comment: "Sunrise/Sunset"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(spacing: 16) {
                // 타임라인 프로그레스 바
                GeometryReader { geometry in
                    let progressWidth = geometry.size.width - 120 // 아이콘+시간 공간 제외

                    HStack(spacing: 8) {
                        // 시작 아이콘 + 시간 (낮: 오늘 일출, 밤: 오늘 일몰)
                        VStack(spacing: 4) {
                            Image(systemName: settingManager.isDaytime ? "sunrise.fill" : "sunset.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.orange)

                            Text(formatTime(settingManager.isDaytime ? settingManager.todaySunrise : settingManager.todaySunset))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 56)

                        // 프로그레스 바
                        ZStack(alignment: .center) {
                            // 배경 라인
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 2)

                            // 정오/자정 마커 (프로그레스바 뒤에 표시)
                            if let marker = calculateNoonMidnightMarker(in: progressWidth) {
                                VStack(spacing: 2) {
                                    // 다이아몬드 마커
                                    Diamond()
                                        .fill(Color.gray.opacity(0.5))
                                        .frame(width: 8, height: 8)

                                    // 수직선
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 1, height: 20)

                                    // 라벨
                                    Text(marker.label)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .offset(x: marker.position - (progressWidth / 2))
                            }

                            // 현재 상태 (낮/밤) - 원형 뱃지 (프로그레스 바 위를 이동)
                            ZStack {
                                Circle()
                                    .fill(
                                        settingManager.isDaytime
                                            ? LinearGradient(
                                                colors: [Color.orange.opacity(0.8), Color.yellow.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                            : LinearGradient(
                                                colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                    )
                                    .frame(width: 36, height: 36)
                                    .shadow(
                                        color: (settingManager.isDaytime ? Color.orange : Color.indigo).opacity(0.4),
                                        radius: 8,
                                        x: 0,
                                        y: 2
                                    )

                                Image(systemName: settingManager.isDaytime ? "sun.max.fill" : "moon.stars.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .offset(x: calculateProgress(in: progressWidth) - (progressWidth / 2))
                        }
                        .frame(width: progressWidth)

                        // 끝 아이콘 + 시간 (낮: 오늘 일몰, 밤: 내일 일출)
                        VStack(spacing: 4) {
                            Image(systemName: settingManager.isDaytime ? "sunset.fill" : "sunrise.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.orange)

                            VStack(spacing: 0) {
                                Text(formatTime(settingManager.isDaytime ? settingManager.todaySunset : settingManager.tomorrowSunrise))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 56)
                    }
                }
                .frame(height: 60)

                // 남은 시간 표시
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)

                    Text(settingManager.isDaytime ? NSLocalizedString("weather.until.sunset", comment: "Until sunset") : NSLocalizedString("weather.until.sunrise", comment: "Until sunrise"))
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text(formatRemainingTime(settingManager.timeUntilNextSunEvent))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)

                    Text(NSLocalizedString("weather.remaining", comment: "remaining"))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
        }
    }

    // MARK: - 현재 날씨 카드 (모든 정보 포함)

    private var currentWeatherCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("weather.section.current", comment: "Current Weather"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                // 드론 무게 라벨
                Text(NSLocalizedString("weather.drone.weight", comment: "Drone Weight:"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 드론 카테고리 선택 드롭다운
                Menu {
                    ForEach(DroneCategory.allCases) { category in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settingManager.selectedDroneCategory = category
                            }
                            // 드론 카테고리 변경 시 날씨 데이터 재계산
                            Task {
                                await manager.fetchWeatherData(forceRefresh: true)
                            }
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(category.localizedName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    if settingManager.selectedDroneCategory == category {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                    }
                                }

                                Text(category.examples)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.caption)
                        Text(settingManager.selectedDroneCategory.localizedName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            if manager.hourlyForecast.isEmpty && manager.isLoading {
                // 초기 로드 시에만 ProgressView 표시
                ProgressView()
                    .frame(height: 200)
            } else if manager.hourlyForecast.isEmpty && manager.errorMessage != nil {
                // 데이터가 없고 에러가 있을 때만 에러 표시
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(manager.errorMessage ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
            } else {
                // 날씨 데이터 표시 (로딩 중에도 이전 데이터 유지)
                ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    // 현재 날씨 상태 (좌측 아이콘 + 우측 정보)
                    HStack(alignment: .top, spacing: 16) {
                        // 왼쪽: 날씨 아이콘
                        Image(systemName: manager.precipitationIconName)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 64, height: 64)
                            .padding(.horizontal, 15)

                        // 오른쪽: 날씨 정보
                        VStack(alignment: .leading, spacing: 8) {
                            // 온도 + 상태
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(manager.temperatureString)
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(manager.temperatureColor)

                                Text(manager.weatherConditionString)
                                    .font(.title3)
                                    .foregroundColor(.primary)
                            }

                            // 최고/최저 온도
                            HStack(spacing: 8) {
                                Text(NSLocalizedString("weather.temperature.high", comment: "High:") + manager.maxTemperatureString)
                                Text("~")
                                Text(NSLocalizedString("weather.temperature.low", comment: "Low:") + manager.minTemperatureString)
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)

//                            Divider()
//
//                            // 추가 설명
//                            Text(manager.weatherDescription)
//                                .font(.subheadline)
//                                .foregroundColor(.secondary)
//                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(12)

                    // 나머지 날씨 정보 그리드
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        // 온도
                        weatherDataCard(
                        icon: "thermometer.medium",
                        iconColor: manager.temperatureColor,
                        label: NSLocalizedString("weather.element.temperature", comment: "Temperature"),
                        value: manager.temperatureString,
                        warningIcon: temperatureWarningIcon,
                        onTap: {
                            selectedWeatherElement = .temperature
                        }
                    )

                    // 풍속
                    weatherDataCard(
                        icon: "wind",
                        iconColor: .green,
                        label: NSLocalizedString("weather.element.windSpeed", comment: "Wind Speed"),
                        value: manager.windSpeedString,
                        warningIcon: windSpeedWarningIcon,
                        onTap: {
                            selectedWeatherElement = .windSpeed
                        }
                    )

                    // 풍향
                    weatherDataCard(
                        icon: "arrow.up",
                        iconColor: .teal,
                        label: NSLocalizedString("weather.element.windDirection", comment: "Wind Direction"),
                        value: manager.windDirectionCompass,
                        rotation: manager.windDirection
                    )

                    // 순간풍속증가량
                    weatherDataCard(
                        icon: "wind.snow",
                        iconColor: .orange,
                        label: NSLocalizedString("weather.element.gustDifference", comment: "Gust Difference"),
                        value: manager.gustDifferenceString,
                        warningIcon: gustDifferenceWarningIcon,
                        subText: gustDifferenceSubText,
                        onTap: {
                            selectedWeatherElement = .gustDifference
                        }
                    )

                    // 강수량/강설량 (아이콘 고정)
                    weatherDataCard(
                        icon: "cloud.rain.fill",
                        iconColor: .blue,
                        label: manager.precipitationLabel,
                        value: manager.precipitationString,
                        warningIcon: precipitationWarningIcon,
                        onTap: {
                            selectedWeatherElement = .precipitation
                        }
                    )

                    // 가시거리
                    weatherDataCard(
                        icon: "eye",
                        iconColor: .purple,
                        label: NSLocalizedString("weather.element.visibility", comment: "Visibility"),
                        value: manager.visibilityString,
                        warningIcon: visibilityWarningIcon,
                        onTap: {
                            selectedWeatherElement = .visibility
                        }
                    )

                    // 결로위험지수
                    weatherDataCard(
                        icon: "drop.fill",
                        iconColor: .cyan,
                        label: NSLocalizedString("weather.element.cri", comment: "Condensation Risk Index"),
                        value: manager.criString,
                        warningIcon: criWarningIcon,
                        onTap: {
                            selectedWeatherElement = .cri
                        }
                    )
                    }

                    // 면책 문구 (박스 안쪽 맨 아래)
                    HStack(alignment: .top, spacing: 4) {
                        Spacer()

                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(NSLocalizedString("weather.disclaimer", comment: "Caution and warning icons disclaimer"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, -2)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)

                // 재로딩 인디케이터 (우측 상단에 작게 표시)
                if manager.isLoading && !manager.hourlyForecast.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.9))
                        .cornerRadius(8)
                }
                }
            }
        }
    }

    // MARK: - Helper Views

    private func weatherDataCard(icon: String, iconColor: Color, label: String, value: String, rotation: Double? = nil, warningIcon: WarningIconType = .none, subText: String? = nil, onTap: (() -> Void)? = nil) -> some View {
        let hasSubText = subText != nil

        return HStack(spacing: 12) {
            // 왼쪽: 아이콘 (가운데 정렬)
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 32)
                .rotationEffect(Angle(degrees: rotation != nil ? rotation! + 180 : 0))

            // 오른쪽: 항목명 + 수치 + 서브텍스트
            VStack(alignment: .leading, spacing: hasSubText ? 1 : 2) {
                // 항목명
                Text(label)
                    .font(hasSubText ? .subheadline : .headline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // 수치
                Text(value)
                    .font(hasSubText ? .body.weight(.semibold) : .title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // 서브텍스트 (국지 돌풍)
                if let subText = subText {
                    Text(subText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 경고 아이콘 표시
            if warningIcon != .none {
                Image(systemName: warningIconSymbol(for: warningIcon))
                    .font(.system(size: 16))
                    .foregroundColor(warningIconColor(for: warningIcon))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            }
        }
    }

    // 경고 아이콘 심볼 반환
    private func warningIconSymbol(for type: WarningIconType) -> String {
        switch type {
        case .none:
            return ""
        case .info:
            return "info.circle.fill"
        case .caution:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        }
    }

    // 경고 아이콘 색상 반환
    private func warningIconColor(for type: WarningIconType) -> Color {
        switch type {
        case .none:
            return .clear
        case .info:
            return .yellow
        case .caution:
            return .yellow
        case .warning:
            return .red
        }
    }

    // MARK: - 온도 예보 Y축 범위 계산 (Helper 함수)

    private func calculateTemperatureYRange() -> ClosedRange<Double> {
        guard !manager.hourlyForecast.isEmpty else {
            return -30...50
        }

        let temps = manager.hourlyForecast.map { $0.temperature }
        let minTemp = temps.min() ?? 0
        let maxTemp = temps.max() ?? 30

        // 상하 5도씩 여백 추가 후 5도 단위로 내림/올림
        let yMinWithMargin = minTemp - 5
        let yMaxWithMargin = maxTemp + 5

        // 5도 단위로 내림/올림
        let yMin = max(-30, floor(yMinWithMargin / 5) * 5)
        let yMax = min(50, ceil(yMaxWithMargin / 5) * 5)

        return yMin...yMax
    }

    // MARK: - 온도 그라데이션 Stops 계산 (Helper 함수)

    private func calculateTemperatureGradientStops(yRange: ClosedRange<Double>) -> [Gradient.Stop] {
        let yMin = yRange.lowerBound
        let yMax = yRange.upperBound
        let yRangeValue = yMax - yMin

        // 온도 기준점들
        let tempPoints: [(temp: Double, color: Color)] = [
            (-10.0, Color(hex: "#0072FF")),    // Cold Blue
            (7.5, Color(hex: "#00C8FF")),      // Cyan
            (17.5, Color(hex: "#A6E22E")),     // Green-Yellow
            (27.5, Color(hex: "#FFA500")),     // Orange
            (40.0, Color(hex: "#FF3B30"))      // Red
        ]

        // 각 기준점의 Y축 내 위치 계산 (0.0 ~ 1.0)
        var stops: [Gradient.Stop] = []
        for point in tempPoints {
            let location = (point.temp - yMin) / yRangeValue
            // 범위 내에 있거나 경계에 있는 경우만 추가
            let clampedLocation = max(0.0, min(1.0, location))
            stops.append(Gradient.Stop(color: point.color, location: clampedLocation))
        }

        // location 기준으로 정렬
        stops.sort { $0.location < $1.location }

        return stops
    }

    // MARK: - 강수량 예보 Y축 범위 계산 (Helper 함수)

    private func calculatePrecipitationYRange() -> ClosedRange<Double> {
        guard !manager.hourlyForecast.isEmpty else {
            return 0...10
        }

        let precipitations = manager.hourlyForecast.map { $0.precipitation }
        let maxPrecip = precipitations.max() ?? 0

        // 최소 범위: 0-10mm
        // 최대값이 10을 넘으면 최대값 + 여백(20%)로 범위 설정
        let yMax = max(10, ceil(maxPrecip * 1.2))

        return 0...yMax
    }

    // MARK: - 온도 예보 그래프

    private var temperatureForecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("weather.chart.temperature.title.dynamic", comment: "Temperature Forecast"), manager.forecastPeriodString))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("weather.unit.celsius", comment: "Unit: °C"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart {
                // 라인 그래프 (각 데이터 포인트별로 온도 색상 적용)
                ForEach(manager.hourlyForecast) { data in
                    LineMark(
                        x: .value("시간", data.date),
                        y: .value("온도", data.temperature)
                    )
                    .foregroundStyle(temperatureColorCache[data.id] ?? .gray)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // 점 그래프 (온도별 그라데이션 색상)
                ForEach(manager.hourlyForecast) { data in
                    PointMark(
                        x: .value("시간", data.date),
                        y: .value("온도", data.temperature)
                    )
                    .foregroundStyle(temperatureColorCache[data.id] ?? .gray)
                    .symbolSize(60)
                }

                // 영역 그래프 (전체 데이터를 하나의 영역으로, Y축 실제 범위에 맞춘 그라데이션)
                ForEach(manager.hourlyForecast) { data in
                    AreaMark(
                        x: .value("시간", data.date),
                        yStart: .value("최소", cachedTemperatureYRange.lowerBound),
                        yEnd: .value("온도", data.temperature)
                    )
                }
                .foregroundStyle(
                    LinearGradient(
                        stops: cachedTemperatureGradientStops.map { stop in
                            Gradient.Stop(color: stop.color.opacity(0.3), location: stop.location)
                        },
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

                // 저온 주의선
                RuleMark(y: .value("저온", WeatherThresholds.temperatureLowCaution))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 고온 주의선
                RuleMark(y: .value("고온", WeatherThresholds.temperatureHighCaution))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 현재 시간 표시선
                RuleMark(x: .value(NSLocalizedString("weather.chart.current", comment: "Now"), Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .center) {
                        Text(NSLocalizedString("weather.chart.current", comment: "Now"))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 43200) // 12시간 표시
            .chartYScale(domain: cachedTemperatureYRange)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.0f", doubleValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: cachedChartDates) { value in
                    AxisGridLine()
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: date)

                            if hour == 0 {
                                // 자정(00시)인 경우 날짜 표기
                                Text(formatChartDate(date))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .offset(x: -19)
                            } else {
                                // 일반 시간 표기
                                Text(formatChartTime(date))
                                    .font(.caption2)
                                    .offset(x: -10.5)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)

            // 범례
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.lowTemp", comment: "Low Temp"), Int(WeatherThresholds.temperatureLowCaution)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.highTemp", comment: "High Temp"), Int(WeatherThresholds.temperatureHighCaution)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.leading, 23)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - 풍속 예보 그래프

    private var windSpeedForecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("weather.chart.windSpeed.title.dynamic", comment: "Wind Speed Forecast"), manager.forecastPeriodString))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("weather.unit.mps", comment: "Unit: m/s"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart {
                ForEach(manager.hourlyForecast) { data in
                    // 영역 그래프
                    AreaMark(
                        x: .value("시간", data.date),
                        y: .value("풍속", data.windSpeed)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.3),
                                Color.green.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 라인 그래프
                    LineMark(
                        x: .value("시간", data.date),
                        y: .value("풍속", data.windSpeed)
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    // 점 그래프
                    PointMark(
                        x: .value("시간", data.date),
                        y: .value("풍속", data.windSpeed)
                    )
                    .foregroundStyle(Color.green)
                }

                // 주의선 (드론 카테고리 반영)
                RuleMark(y: .value("주의", settingManager.selectedDroneCategory.windSpeedThresholds.caution))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 위험선 (드론 카테고리 반영)
                RuleMark(y: .value("위험", settingManager.selectedDroneCategory.windSpeedThresholds.danger))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 현재 시간 표시선
                RuleMark(x: .value(NSLocalizedString("weather.chart.current", comment: "Now"), Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .center) {
                        Text(NSLocalizedString("weather.chart.current", comment: "Now"))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 43200) // 12시간 표시
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.0f", doubleValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: cachedChartDates) { value in
                    AxisGridLine()
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: date)

                            if hour == 0 {
                                Text(formatChartDate(date))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .offset(x: -19)
                            } else {
                                Text(formatChartTime(date))
                                    .font(.caption2)
                                    .offset(x: -10.5)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)

            // 범례 (동적 업데이트)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.caution", comment: "Caution"), settingManager.selectedDroneCategory.windSpeedThresholds.caution))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.danger", comment: "Danger"), settingManager.selectedDroneCategory.windSpeedThresholds.danger))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.leading, 23)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - 순간풍속증가량 예보 그래프

    private var gustDifferenceForecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("weather.chart.gustDifference.title.dynamic", comment: "Gust Difference Forecast"), manager.forecastPeriodString))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("weather.unit.mps", comment: "Unit: m/s"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart {
                ForEach(manager.hourlyForecast) { data in
                    // 영역 그래프
                    AreaMark(
                        x: .value("시간", data.date),
                        y: .value("순간풍속증가량", data.gustDifference)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.indigo.opacity(0.3),
                                Color.indigo.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 라인 그래프
                    LineMark(
                        x: .value("시간", data.date),
                        y: .value("순간풍속증가량", data.gustDifference)
                    )
                    .foregroundStyle(Color.indigo)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    // 점 그래프
                    PointMark(
                        x: .value("시간", data.date),
                        y: .value("순간풍속증가량", data.gustDifference)
                    )
                    .foregroundStyle(Color.indigo)
                }

                // 주의선 (드론 카테고리 반영)
                RuleMark(y: .value("주의", settingManager.selectedDroneCategory.gustDifferenceThresholds.caution))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 위험선 (드론 카테고리 반영)
                RuleMark(y: .value("위험", settingManager.selectedDroneCategory.gustDifferenceThresholds.danger))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 현재 시간 표시선
                RuleMark(x: .value(NSLocalizedString("weather.chart.current", comment: "Now"), Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .center) {
                        Text(NSLocalizedString("weather.chart.current", comment: "Now"))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 43200) // 12시간 표시
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.0f", doubleValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: cachedChartDates) { value in
                    AxisGridLine()
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: date)

                            if hour == 0 {
                                Text(formatChartDate(date))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .offset(x: -19)
                            } else {
                                Text(formatChartTime(date))
                                    .font(.caption2)
                                    .offset(x: -10.5)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)

            // 범례 (동적 업데이트)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.caution", comment: "Caution"), settingManager.selectedDroneCategory.gustDifferenceThresholds.caution))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.danger", comment: "Danger"), settingManager.selectedDroneCategory.gustDifferenceThresholds.danger))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.leading, 23)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - 강수량 예보 그래프

    private var precipitationForecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("weather.chart.precipitation.title.dynamic", comment: "Precipitation Forecast"), manager.forecastPeriodString))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("weather.unit.mmph", comment: "Unit: mm/h"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart {
                ForEach(manager.hourlyForecast) { data in
                    // 영역 그래프
                    AreaMark(
                        x: .value("시간", data.date),
                        y: .value("강수량", data.precipitation)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.blue.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 라인 그래프
                    LineMark(
                        x: .value("시간", data.date),
                        y: .value("강수량", data.precipitation)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    // 점 그래프
                    PointMark(
                        x: .value("시간", data.date),
                        y: .value("강수량", data.precipitation)
                    )
                    .foregroundStyle(Color.blue)
                }

                // 현재 시간 표시선
                RuleMark(x: .value(NSLocalizedString("weather.chart.current", comment: "Now"), Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .center) {
                        Text(NSLocalizedString("weather.chart.current", comment: "Now"))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
            }
            .chartYScale(domain: cachedPrecipitationYRange)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 43200) // 12시간 표시
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.1f", doubleValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: cachedChartDates) { value in
                    AxisGridLine()
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: date)

                            if hour == 0 {
                                Text(formatChartDate(date))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .offset(x: -19)
                            } else {
                                Text(formatChartTime(date))
                                    .font(.caption2)
                                    .offset(x: -10.5)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }


    // MARK: - 결로위험지수 예보 그래프

    private var criForecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("weather.chart.cri.title.dynamic", comment: "CRI Forecast"), manager.forecastPeriodString))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("weather.unit.custom", comment: "Unit: Custom"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart {
                ForEach(manager.hourlyForecast) { data in
                    // 영역 그래프
                    AreaMark(
                        x: .value("시간", data.date),
                        y: .value("CRI", data.cri)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.3),
                                Color.cyan.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 라인 그래프
                    LineMark(
                        x: .value("시간", data.date),
                        y: .value("CRI", data.cri)
                    )
                    .foregroundStyle(Color.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    // 점 그래프
                    PointMark(
                        x: .value("시간", data.date),
                        y: .value("CRI", data.cri)
                    )
                    .foregroundStyle(Color.cyan)
                }

                // 주의 기준선
                RuleMark(y: .value("주의", WeatherThresholds.criModerate))
                    .foregroundStyle(.yellow)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 경고 기준선
                RuleMark(y: .value("경고", WeatherThresholds.criHigh))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 현재 시간 표시선
                RuleMark(x: .value(NSLocalizedString("weather.chart.current", comment: "Now"), Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .center) {
                        Text(NSLocalizedString("weather.chart.current", comment: "Now"))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
            }
            .chartYScale(domain: 0...100)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 43200) // 12시간 표시
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.0f", doubleValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: cachedChartDates) { value in
                    AxisGridLine()
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: date)

                            if hour == 0 {
                                Text(formatChartDate(date))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .offset(x: -19)
                            } else {
                                Text(formatChartTime(date))
                                    .font(.caption2)
                                    .offset(x: -10.5)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)

            // 범례 (3단계)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow)
                        .frame(width: 16, height: 8)
                    Text(NSLocalizedString("weather.legend.criCaution", comment: "Caution ≥ 40"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 16, height: 8)
                    Text(NSLocalizedString("weather.legend.criWarning", comment: "Warning ≥ 70"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.leading, 23)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - 가시거리 예보 그래프

    private var visibilityForecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: NSLocalizedString("weather.chart.visibility.title.dynamic", comment: "Visibility Forecast"), manager.forecastPeriodString))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("weather.unit.km", comment: "Unit: km"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart {
                ForEach(manager.hourlyForecast) { data in
                    // 영역 그래프
                    AreaMark(
                        x: .value("시간", data.date),
                        y: .value("가시거리", data.visibility)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(0.3),
                                Color.purple.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 라인 그래프
                    LineMark(
                        x: .value("시간", data.date),
                        y: .value("가시거리", data.visibility)
                    )
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    // 점 그래프
                    PointMark(
                        x: .value("시간", data.date),
                        y: .value("가시거리", data.visibility)
                    )
                    .foregroundStyle(Color.purple)
                }

                // 위험선
                RuleMark(y: .value("위험", WeatherThresholds.visibilityPoor))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 양호선
                RuleMark(y: .value("양호", WeatherThresholds.visibilityGood))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // 현재 시간 표시선
                RuleMark(x: .value(NSLocalizedString("weather.chart.current", comment: "Now"), Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, alignment: .center) {
                        Text(NSLocalizedString("weather.chart.current", comment: "Now"))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 43200) // 12시간 표시
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.0f", doubleValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: cachedChartDates) { value in
                    AxisGridLine()
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: date)

                            if hour == 0 {
                                Text(formatChartDate(date))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .offset(x: -19)
                            } else {
                                Text(formatChartTime(date))
                                    .font(.caption2)
                                    .offset(x: -10.5)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)

            // 범례
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.poor", comment: "Poor"), Int(WeatherThresholds.visibilityPoor)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: 16, height: 8)
                    Text(String(format: NSLocalizedString("weather.legend.good", comment: "Good"), Int(WeatherThresholds.visibilityGood)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.leading, 23)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Helper Methods

    /// 캐시 데이터 일괄 업데이트 (중복 제거)
    private func updateCaches() {
        cachedChartDates = manager.hourlyForecast.map { $0.date }
        cachedTemperatureYRange = calculateTemperatureYRange()
        cachedTemperatureGradientStops = calculateTemperatureGradientStops(yRange: cachedTemperatureYRange)
        cachedPrecipitationYRange = calculatePrecipitationYRange()
        temperatureColorCache = Dictionary(uniqueKeysWithValues:
            manager.hourlyForecast.map { data in
                (data.id, colorForTemperature(data.temperature))
            }
        )
    }

    /// 온도값에 따른 그라데이션 색상 반환
    private func colorForTemperature(_ temp: Double) -> Color {
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

    /// 프로그레스 바 위치 계산 (0.0 ~ progressWidth)
    private func calculateProgress(in progressWidth: CGFloat) -> CGFloat {
        let now = Date()

        if settingManager.isDaytime {
            // 낮: 오늘 일출 → 현재 → 오늘 일몰
            guard let sunrise = settingManager.todaySunrise,
                  let sunset = settingManager.todaySunset else {
                return 0
            }

            let totalInterval = sunset.timeIntervalSince(sunrise)
            let currentInterval = now.timeIntervalSince(sunrise)
            let progress = min(max(currentInterval / totalInterval, 0), 1)

            return progressWidth * progress
        } else {
            // 밤: 지난 일출/일몰 → 현재 → 다음 일출
            let startTime: Date
            let endTime: Date

            // 오늘 일출이 아직 미래인지 확인
            if let todaySunrise = settingManager.todaySunrise, todaySunrise > now {
                // 오늘 일출 전 (새벽) → 어제 일몰 ~ 오늘 일출
                // 어제 일몰 = 오늘 일몰 - 24시간 (근사값)
                if let todaySunset = settingManager.todaySunset {
                    startTime = todaySunset.addingTimeInterval(-86400)
                } else {
                    return 0
                }
                endTime = todaySunrise
            } else {
                // 오늘 일출 이후 저녁 → 오늘 일몰 ~ 내일 일출
                guard let todaySunset = settingManager.todaySunset,
                      let tomorrowSunrise = settingManager.tomorrowSunrise else {
                    return 0
                }
                startTime = todaySunset
                endTime = tomorrowSunrise
            }

            let totalInterval = endTime.timeIntervalSince(startTime)
            let currentInterval = now.timeIntervalSince(startTime)
            let progress = min(max(currentInterval / totalInterval, 0), 1)

            return progressWidth * progress
        }
    }

    /// 정오/자정 마커 위치 계산 (0.0 ~ progressWidth)
    /// - Returns: 마커 위치 (nil이면 마커 표시 안 함)
    private func calculateNoonMidnightMarker(in progressWidth: CGFloat) -> (position: CGFloat, label: String)? {
        let calendar = Calendar.current
        let now = Date()

        // 정오(12:00) 또는 자정(00:00) Date 생성
        let targetHour = settingManager.isDaytime ? 12 : 0

        // 밤일 때 저녁 시간대 (일출 이후)인지 확인하여 내일 자정을 계산
        var baseDate = now
        if !settingManager.isDaytime {
            if let todaySunrise = settingManager.todaySunrise, todaySunrise <= now {
                // 오늘 일출 이후 저녁 → 내일 자정 사용
                baseDate = now.addingTimeInterval(86400) // 내일
            }
        }

        guard let noonOrMidnight = calendar.date(bySettingHour: targetHour, minute: 0, second: 0, of: baseDate) else {
            return nil
        }

        let startTime: Date
        let endTime: Date

        if settingManager.isDaytime {
            // 낮: 오늘 일출 ~ 오늘 일몰
            guard let sunrise = settingManager.todaySunrise,
                  let sunset = settingManager.todaySunset else {
                return nil
            }
            startTime = sunrise
            endTime = sunset

            // 정오가 일출~일몰 범위 밖이면 마커 표시 안 함
            guard noonOrMidnight >= startTime && noonOrMidnight <= endTime else {
                return nil
            }
        } else {
            // 밤: 지난 일출/일몰 ~ 다음 일출
            if let todaySunrise = settingManager.todaySunrise, todaySunrise > now {
                // 오늘 일출 전 (새벽) → 어제 일몰 ~ 오늘 일출
                if let todaySunset = settingManager.todaySunset {
                    startTime = todaySunset.addingTimeInterval(-86400)
                } else {
                    return nil
                }
                endTime = todaySunrise
            } else {
                // 오늘 일출 이후 저녁 → 오늘 일몰 ~ 내일 일출
                guard let todaySunset = settingManager.todaySunset,
                      let tomorrowSunrise = settingManager.tomorrowSunrise else {
                    return nil
                }
                startTime = todaySunset
                endTime = tomorrowSunrise
            }

            // 자정이 범위 밖이면 마커 표시 안 함
            guard noonOrMidnight >= startTime && noonOrMidnight <= endTime else {
                return nil
            }
        }

        // 마커 위치 계산
        let totalInterval = endTime.timeIntervalSince(startTime)
        let markerInterval = noonOrMidnight.timeIntervalSince(startTime)
        let markerProgress = markerInterval / totalInterval
        let markerPosition = progressWidth * CGFloat(markerProgress)

        let label = settingManager.isDaytime ? NSLocalizedString("weather.noon", comment: "Noon") : NSLocalizedString("weather.midnight", comment: "Midnight")
        return (position: markerPosition, label: label)
    }

    /// 시간 포맷팅 (HH:mm)
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 남은 시간 포맷팅 (HH:MM → HH시간 MM분)
    private func formatRemainingTime(_ timeString: String) -> String {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]) else {
            return timeString
        }

        if hours > 0 {
            return String(format: NSLocalizedString("weather.time.hours", comment: "hours and minutes"), hours, minutes)
        } else {
            return String(format: NSLocalizedString("weather.time.minutes", comment: "minutes"), minutes)
        }
    }

    // 성능 최적화: Static DateFormatter 재사용
    private static let chartTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH"
        return formatter
    }()

    private static let chartDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private func formatChartTime(_ date: Date) -> String {
        return Self.chartTimeFormatter.string(from: date)
    }

    private func formatChartDate(_ date: Date) -> String {
        return Self.chartDateFormatter.string(from: date)
    }

    private func formatUpdateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// WeatherElementType을 Identifiable로 확장
extension WeatherForecastView.WeatherElementType: Identifiable {
    var id: Self { self }
}

// MARK: - Diamond Shape (다이아몬드 마커용)

/// 다이아몬드 모양 Shape (정오/자정 마커용)
struct Diamond: SwiftUI.Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.midY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.midY)

        path.move(to: top)
        path.addLine(to: right)
        path.addLine(to: bottom)
        path.addLine(to: left)
        path.closeSubpath()

        return path
    }
}

#Preview {
    WeatherForecastView()
}
