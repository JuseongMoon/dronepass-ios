//
//  WeatherInfoView.swift
//  DronePass
//
//  Created by 문주성 on 10/14/25.
//

import SwiftUI

/// 날씨 정보 설명 뷰
struct WeatherInfoView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var settingManager = SettingManager.shared
    @ObservedObject var weatherManager = WeatherManager.shared
    var scrollToElement: WeatherForecastView.WeatherElementType?

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // 날씨와 드론 비행 개요 섹션
                        weatherOverviewSection

                        // 날씨 요소별 설명 섹션
                        weatherElementsSection
                    }
                    .padding()
                }
                .onAppear {
                    // 선택된 요소가 있으면 해당 위치로 스크롤
                    if let element = scrollToElement {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(element, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("weatherInfo.navigation.title", comment: "Weather Information"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("appInfo.close", comment: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - 날씨 개요 섹션

    private var weatherOverviewSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("weatherInfo.section.importance", comment: "Weather & Drone Flight"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 16) {
                // 기본 설명
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("weatherInfo.importance.text1", comment: "Weather importance"))
                        .font(.body)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("weatherInfo.importance.bullet1", comment: "Consider weather factors"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("weatherInfo.importance.bullet2", comment: "Stop flight if weather deteriorates"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("weatherInfo.importance.bullet3", comment: "Check forecast before flight"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // 위치 정확도 경고 (GPS 미사용 시)
                if !weatherManager.isUsingGPS, let accuracy = weatherManager.locationAccuracy {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            Text(NSLocalizedString("weatherInfo.location.title", comment: "Location Accuracy Notice"))
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }

                        Text(String(format: NSLocalizedString("weatherInfo.location.wifi", comment: "Wi-Fi based location"), Int(accuracy)))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            Text(NSLocalizedString("weatherInfo.location.bullet1", comment: "Weather info may differ"))
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            Text(NSLocalizedString("weatherInfo.location.bullet2", comment: "Use device with cellular"))
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)

                    Divider()
                }

                // 안전 비행을 위한 조언
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("weatherInfo.safety.title", comment: "Tips for Safe Flight"))
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(NSLocalizedString("weatherInfo.safety.text", comment: "Weather monitoring needed"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("weatherInfo.safety.bullet1", comment: "Judge comprehensively"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("weatherInfo.safety.bullet2", comment: "Forecast may differ"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Text(NSLocalizedString("weatherInfo.safety.bullet3", comment: "Postpone if severe weather"))
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
        }
    }

    // MARK: - 날씨 요소별 설명 섹션

    private var weatherElementsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("weatherInfo.section.elements", comment: "Key Weather Elements"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(spacing: 12) {
                // 풍속 (드론 카테고리별 동적 생성)
                windSpeedCard
                    .id(WeatherForecastView.WeatherElementType.windSpeed)

                // 순간 풍속 증가량 (드론 카테고리별 동적 생성)
                gustDifferenceCard
                    .id(WeatherForecastView.WeatherElementType.gustDifference)

                // 강수량
                weatherElementCard(
                    icon: "cloud.rain.fill",
                    iconColor: .cyan,
                    title: NSLocalizedString("weatherInfo.precipitation.title", comment: "Precipitation"),
                    safeRange: NSLocalizedString("weatherInfo.precipitation.safeRange", comment: "0 mm (Dry)"),
                    elements: [
                        WeatherElement(
                            range: NSLocalizedString("weatherInfo.precipitation.rangeOnly", comment: "0 mm"),
                            level: .safe,
                            description: NSLocalizedString("weatherInfo.precipitation.safe.desc", comment: "Dry conditions"),
                            advice: NSLocalizedString("weatherInfo.precipitation.safe.advice", comment: "Normal flight possible")
                        ),
                        WeatherElement(
                            range: NSLocalizedString("weatherInfo.precipitation.caution.range", comment: "0.1-1.0 mm"),
                            level: .caution,
                            description: NSLocalizedString("weatherInfo.precipitation.caution.desc", comment: "Light rain"),
                            advice: NSLocalizedString("weatherInfo.precipitation.caution.advice", comment: "Avoid flight except waterproof")
                        ),
                        WeatherElement(
                            range: NSLocalizedString("weatherInfo.precipitation.danger.range", comment: "1.0 mm or more"),
                            level: .danger,
                            description: NSLocalizedString("weatherInfo.precipitation.danger.desc", comment: "Motor damage risk"),
                            advice: NSLocalizedString("weatherInfo.precipitation.danger.advice", comment: "Avoid flight")
                        )
                    ],
                    note: NSLocalizedString("weatherInfo.precipitation.note", comment: "Most drones not waterproof")
                )
                .id(WeatherForecastView.WeatherElementType.precipitation)

                // 가시거리
                weatherElementCard(
                    icon: "eye.fill",
                    iconColor: .indigo,
                    title: NSLocalizedString("weatherInfo.visibility.title", comment: "Visibility"),
                    safeRange: String(format: NSLocalizedString("weatherInfo.visibility.safeRange", comment: "km or more (Good)"), Int(WeatherThresholds.visibilityGood)),
                    elements: [
                        WeatherElement(
                            range: String(format: NSLocalizedString("weatherInfo.visibility.rangeOnly", comment: "km or more"), Int(WeatherThresholds.visibilityGood)),
                            level: .safe,
                            description: NSLocalizedString("weatherInfo.visibility.safe.desc", comment: "Very clear visibility"),
                            advice: NSLocalizedString("weatherInfo.visibility.safe.advice", comment: "Normal flight possible")
                        ),
                        WeatherElement(
                            range: String(format: NSLocalizedString("weatherInfo.visibility.caution.range", comment: "km range"), Int(WeatherThresholds.visibilityPoor), Int(WeatherThresholds.visibilityGood)),
                            level: .caution,
                            description: NSLocalizedString("weatherInfo.visibility.caution.desc", comment: "Limited visibility"),
                            advice: NSLocalizedString("weatherInfo.visibility.caution.advice", comment: "Short-range only")
                        ),
                        WeatherElement(
                            range: String(format: NSLocalizedString("weatherInfo.visibility.danger.range", comment: "Less than km"), Int(WeatherThresholds.visibilityPoor)),
                            level: .danger,
                            description: NSLocalizedString("weatherInfo.visibility.danger.desc", comment: "Cannot secure visibility"),
                            advice: NSLocalizedString("weatherInfo.visibility.danger.advice", comment: "Avoid flight")
                        )
                    ],
                    note: NSLocalizedString("weatherInfo.visibility.note", comment: "Essential for visual confirmation")
                )
                .id(WeatherForecastView.WeatherElementType.visibility)

                // 기온
                weatherElementCard(
                    icon: "thermometer.medium",
                    iconColor: .orange,
                    title: NSLocalizedString("weatherInfo.temperature.title", comment: "Temperature"),
                    safeRange: String(format: NSLocalizedString("weatherInfo.temperature.safeRange", comment: "Appropriate range"), Int(WeatherThresholds.temperatureHighCaution)),
                    elements: [
                        WeatherElement(
                            range: String(format: NSLocalizedString("weatherInfo.temperature.rangeOnly", comment: "Safe range"), Int(WeatherThresholds.temperatureHighCaution)),
                            level: .safe,
                            description: NSLocalizedString("weatherInfo.temperature.safe.desc", comment: "Normal battery range"),
                            advice: NSLocalizedString("weatherInfo.temperature.safe.advice", comment: "Normal flight possible")
                        ),
                        WeatherElement(
                            range: String(format: NSLocalizedString("weatherInfo.temperature.caution.range", comment: "Caution range"), Int(WeatherThresholds.temperatureLowCaution), Int(WeatherThresholds.temperatureHighCaution)),
                            level: .caution,
                            description: NSLocalizedString("weatherInfo.temperature.caution.desc", comment: "Reduced battery performance"),
                            advice: NSLocalizedString("weatherInfo.temperature.caution.advice", comment: "Reduced flight time")
                        ),
                        WeatherElement(
                            range: String(format: NSLocalizedString("weatherInfo.temperature.danger.range", comment: "Danger range"), Int(WeatherThresholds.temperatureLowCaution)),
                            level: .danger,
                            description: NSLocalizedString("weatherInfo.temperature.danger.desc", comment: "Rapid degradation"),
                            advice: NSLocalizedString("weatherInfo.temperature.danger.advice", comment: "Avoid flight")
                        )
                    ],
                    note: NSLocalizedString("weatherInfo.temperature.note", comment: "Batteries sensitive to temperature")
                )
                .id(WeatherForecastView.WeatherElementType.temperature)

                // 결로위험지수
                weatherElementCard(
                    icon: "drop.fill",
                    iconColor: .indigo,
                    title: NSLocalizedString("weatherInfo.cri.title", comment: "Condensation Risk Index"),
                    safeRange: NSLocalizedString("weatherInfo.cri.safeRange", comment: "1-39 (Safe)"),
                    elements: [
                        WeatherElement(
                            range: NSLocalizedString("weatherInfo.cri.rangeOnly", comment: "1-39"),
                            level: .safe,
                            description: NSLocalizedString("weatherInfo.cri.safe.desc", comment: "Air is dry"),
                            advice: NSLocalizedString("weatherInfo.cri.safe.advice", comment: "Normal flight possible")
                        ),
                        WeatherElement(
                            range: NSLocalizedString("weatherInfo.cri.caution.range", comment: "40-69"),
                            level: .caution,
                            description: NSLocalizedString("weatherInfo.cri.caution.desc", comment: "High moisture or temperature difference"),
                            advice: NSLocalizedString("weatherInfo.cri.caution.advice", comment: "Dew may form")
                        ),
                        WeatherElement(
                            range: NSLocalizedString("weatherInfo.cri.danger.range", comment: "70-100"),
                            level: .danger,
                            description: NSLocalizedString("weatherInfo.cri.danger.desc", comment: "Air nearly saturated"),
                            advice: NSLocalizedString("weatherInfo.cri.danger.advice", comment: "Water droplets form immediately")
                        )
                    ],
                    note: NSLocalizedString("weatherInfo.cri.note", comment: "CRI calculation formula")
                )
                .id(WeatherForecastView.WeatherElementType.cri)
            }
        }
    }

    // MARK: - Helper Views

    /// 풍속 카드 (드론 카테고리별 동적 생성)
    private var windSpeedCard: some View {
        let category = settingManager.selectedDroneCategory
        let thresholds = category.windSpeedThresholds

        return weatherElementCard(
            icon: "wind",
            iconColor: .blue,
            title: NSLocalizedString("weatherInfo.windSpeed.title", comment: "Wind Speed"),
            safeRange: String(format: NSLocalizedString("weatherInfo.windSpeed.safeRange", comment: "Safe range"), thresholds.caution),
            elements: [
                WeatherElement(
                    range: String(format: NSLocalizedString("weatherInfo.windSpeed.rangeOnly", comment: "Safe range"), thresholds.caution),
                    level: .safe,
                    description: NSLocalizedString("weatherInfo.windSpeed.safe.desc", comment: "Stable flight possible"),
                    advice: NSLocalizedString("weatherInfo.windSpeed.safe.advice", comment: "Normal flight possible")
                ),
                WeatherElement(
                    range: String(format: NSLocalizedString("weatherInfo.windSpeed.caution.range", comment: "Caution range"), thresholds.caution + 0.1, thresholds.danger - 0.1),
                    level: .caution,
                    description: NSLocalizedString("weatherInfo.windSpeed.caution.desc", comment: "Increased control difficulty"),
                    advice: NSLocalizedString("weatherInfo.windSpeed.caution.advice", comment: "Experienced pilots only")
                ),
                WeatherElement(
                    range: String(format: NSLocalizedString("weatherInfo.windSpeed.danger.range", comment: "Danger range"), thresholds.danger),
                    level: .danger,
                    description: NSLocalizedString("weatherInfo.windSpeed.danger.desc", comment: "Uncontrollable"),
                    advice: NSLocalizedString("weatherInfo.windSpeed.danger.advice", comment: "Avoid flight")
                )
            ],
            note: String(format: NSLocalizedString("weatherInfo.windSpeed.note", comment: "Wind speed importance"), category.rawValue, category.maxWindResistance, thresholds.danger),
            showCategorySelector: true
        )
    }

    /// 순간 풍속 증가량 카드 (드론 카테고리별 동적 생성)
    private var gustDifferenceCard: some View {
        let category = settingManager.selectedDroneCategory
        let thresholds = category.gustDifferenceThresholds

        return weatherElementCard(
            icon: "wind.snow",
            iconColor: .orange,
            title: NSLocalizedString("weatherInfo.gustDiff.title", comment: "Gust Difference"),
            safeRange: String(format: NSLocalizedString("weatherInfo.gustDiff.safeRange", comment: "Good range"), thresholds.caution),
            elements: [
                WeatherElement(
                    range: String(format: NSLocalizedString("weatherInfo.gustDiff.rangeOnly", comment: "Safe range"), thresholds.caution),
                    level: .safe,
                    description: NSLocalizedString("weatherInfo.gustDiff.safe.desc", comment: "Wind is stable"),
                    advice: NSLocalizedString("weatherInfo.gustDiff.safe.advice", comment: "All maneuvers safe")
                ),
                WeatherElement(
                    range: String(format: NSLocalizedString("weatherInfo.gustDiff.caution.range", comment: "Caution range"), thresholds.caution, thresholds.danger - 0.1),
                    level: .caution,
                    description: NSLocalizedString("weatherInfo.gustDiff.caution.desc", comment: "Unstable drone attitude"),
                    advice: NSLocalizedString("weatherInfo.gustDiff.caution.advice", comment: "Experienced pilots, low altitude")
                ),
                WeatherElement(
                    range: String(format: NSLocalizedString("weatherInfo.gustDiff.danger.range", comment: "Danger range"), thresholds.danger),
                    level: .danger,
                    description: NSLocalizedString("weatherInfo.gustDiff.danger.desc", comment: "High risk of attitude loss"),
                    advice: NSLocalizedString("weatherInfo.gustDiff.danger.advice", comment: "Stop flight immediately")
                )
            ],
            note: String(format: NSLocalizedString("weatherInfo.gustDiff.note", comment: "Gust difference calculation"), category.rawValue, thresholds.caution, thresholds.danger),
            showCategorySelector: true
        )
    }

    /// 드론 카테고리 선택 드롭다운
    private var droneCategorySelector: some View {
        Menu {
            ForEach(DroneCategory.allCases) { category in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settingManager.selectedDroneCategory = category
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
                                    .fontWeight(.semibold)
                            }
                        }

                        Text(category.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(settingManager.selectedDroneCategory.localizedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
        }
    }

    private func weatherElementCard(
        icon: String,
        iconColor: Color,
        title: String,
        safeRange: String,
        elements: [WeatherElement],
        note: String,
        showCategorySelector: Bool = false
    ) -> some View {
        VStack(spacing: 16) {
            // 헤더
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(String(format: NSLocalizedString("weatherInfo.element.safeRange", comment: "Safe Range"), safeRange))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 드론 카테고리 선택 드롭다운 (풍속 및 순간풍속증가량에만 표시)
                if showCategorySelector {
                    droneCategorySelector
                }
            }

            Divider()

            // 범위별 설명
            VStack(spacing: 12) {
                ForEach(elements) { element in
                    elementDetailRow(element: element)
                }
            }

            // 참고사항
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("weatherInfo.element.note", comment: "Note"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                FormattedNoteText(note: note)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    private func elementDetailRow(element: WeatherElement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 범위
            HStack {
                Circle()
                    .fill(element.level.color)
                    .frame(width: 8, height: 8)

                Text(element.range)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(element.level.color)

                Spacer()
            }

            // 설명
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(element.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 조언
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.caption)
                    .foregroundColor(element.level.textColor)
                Text(element.advice)
                    .font(.caption)
                    .foregroundColor(element.level.textColor)
                    .fontWeight(element.level == .danger ? .medium : .regular)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Types

struct WeatherElement: Identifiable {
    let id = UUID()
    let range: String
    let level: SafetyLevel
    let description: String
    let advice: String
}

enum SafetyLevel {
    case safe
    case caution
    case danger

    var color: Color {
        switch self {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        }
    }

    var textColor: Color {
        switch self {
        case .safe: return .secondary
        case .caution: return .orange
        case .danger: return .red
        }
    }
}

// MARK: - Formatted Note Text

/// note 텍스트를 파싱하여 bullet point를 자동으로 추가 및 들여쓰기 처리
struct FormattedNoteText: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(parseNoteLines(), id: \.offset) { line in
                renderLine(line.text)
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // 빈 줄
        if trimmed.isEmpty {
            Text("")
                .font(.caption)
        }
        // 이미 bullet이 있는 라인
        else if trimmed.hasPrefix("• ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(trimmed.dropFirst(2)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        // 번호나 특수 문자로 시작하는 라인 (①, ②, ⚠️ 등) - bullet 없이 그대로 표시
        else if trimmed.hasPrefix("①") || trimmed.hasPrefix("②") || trimmed.hasPrefix("③") ||
                trimmed.hasPrefix("④") || trimmed.hasPrefix("⑤") || trimmed.hasPrefix("⚠️") {
            Text(trimmed)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.semibold)
        }
        // 화살표(→)로 시작하는 라인 - bullet 없이 들여쓰기만
        else if trimmed.hasPrefix("→") {
            Text(trimmed)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 8)
        }
        // 나머지 일반 텍스트 라인 - bullet 추가
        else if !trimmed.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(trimmed)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func parseNoteLines() -> [(offset: Int, text: String)] {
        let lines = note.components(separatedBy: "\n")
        return lines.enumerated().map { ($0.offset, $0.element) }
    }
}

#Preview {
    WeatherInfoView()
}
