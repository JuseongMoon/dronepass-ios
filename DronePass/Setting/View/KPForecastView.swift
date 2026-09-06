//
//  KPForecastView.swift
//  DronePass
//
//  Created by Claude Code
//

import SwiftUI
import Charts

/// KP 지수 예보 뷰
struct KPForecastView: View {
    @ObservedObject var manager = KPIndexManager.shared
    @Environment(\.dismiss) var dismiss

    // 토스트 메시지 상태
    @State private var showToast = false
    @State private var toastMessage = ""

    // KP 정보 시트 표시 상태
    @State private var showKPInfo = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 현재 KP 지수 카드
                    currentKPCard

                    // 48시간 예보 그래프
                    forecastChart

                    // 27일 장기예보 그래프
                    longTermForecastChart
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("kp.navigation.title", comment: "KP Index Forecast"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showKPInfo = true
                    }) {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await manager.fetchKPData(forceRefresh: true, fetchGFZ: false, fetchNOAA: true)
                            // 새로고침 완료 후 토스트 메시지 표시
                            showToast = false
                            toastMessage = NSLocalizedString("weather.refresh", comment: "Refreshed")
                            showToast = true
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .toastMessage(isPresented: $showToast, message: $toastMessage)
            .sheet(isPresented: $showKPInfo) {
                KPInfoView()
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
            }
            .task {
                // 첫 실행시 NOAA 예보 데이터만 가져오기 (GFZ 현재 KP는 앱 시작 시 이미 받아옴)
                await manager.fetchKPData(forceRefresh: true, fetchGFZ: false, fetchNOAA: true)

                // 5분마다 NOAA 예보 데이터만 자동 새로고침
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(300)) // 5분 = 300초
                        if !Task.isCancelled {
                            await manager.fetchKPData(forceRefresh: true, fetchGFZ: false, fetchNOAA: true)
                            // 자동 새로고침 완료 후 토스트 메시지 표시
                            showToast = false
                            toastMessage = NSLocalizedString("weather.refresh", comment: "Refreshed")
                            showToast = true
                        }
                    } catch {
                        // Task 취소시 루프 종료
                        break
                    }
                }
            }
        }
    }

    // MARK: - 현재 KP 지수 카드

    private var currentKPCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("kp.section.current", comment: "Current KP Index"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                // KP 값
                VStack(spacing: 4) {
                    Text(manager.currentKPString)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(manager.currentLevel.color)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // 레벨 아이콘 + 텍스트
                    HStack(spacing: 6) {
                        Image(systemName: manager.currentLevel.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(manager.currentLevel.color)

                        Text(manager.currentLevel.localizedName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(manager.currentLevel.color)
                    }

                    // 설명
                    Text(levelDescription(for: manager.currentLevel))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 데이터 출처
                    HStack {
                        Spacer()
                        Link("Data: GFZ Potsdam", destination: URL(string: "https://kp.gfz.de/")!)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 10)
            }
            .padding()
            .background(manager.currentLevel.color.opacity(0.1))
            .cornerRadius(16)
        }
    }

    // MARK: - 예보 차트

    private var forecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("kp.section.forecast48", comment: "48-Hour Forecast"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("kp.forecast48.note", comment: "Based on current time"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(6)
            }

            if manager.isLoading {
                ProgressView()
                    .frame(height: 200)
            } else if let errorMessage = manager.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
            } else if manager.next48HoursForecast.isEmpty {
                Text(NSLocalizedString("kp.noData", comment: "No data available"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(manager.next48HoursForecast) { data in
                        // 영역 그래프
                        AreaMark(
                            x: .value("시간", data.date ?? Date()),
                            y: .value("KP", data.kp)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    KPLevel.level(from: data.kp).color.opacity(0.3),
                                    KPLevel.level(from: data.kp).color.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // 라인 그래프
                        LineMark(
                            x: .value("시간", data.date ?? Date()),
                            y: .value("KP", data.kp)
                        )
                        .foregroundStyle(KPLevel.level(from: data.kp).color)
                        .lineStyle(StrokeStyle(
                            lineWidth: 2,
                            dash: data.observationStatus == .predicted ? [5, 3] : []
                        ))

                        // 포인트 마크
                        PointMark(
                            x: .value("시간", data.date ?? Date()),
                            y: .value("KP", data.kp)
                        )
                        .foregroundStyle(KPLevel.level(from: data.kp).color)
                        .symbol {
                            Circle()
                                .fill(KPLevel.level(from: data.kp).color)
                                .frame(width: 6, height: 6)
                        }
                        .annotation(position: .top, alignment: .center) {
                            Text(String(format: "%.1f", data.kp))
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }

                    // 주의선 (G1 시작)
                    RuleMark(y: .value(NSLocalizedString("kp.chart.caution", comment: "Caution"), 5))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    // 위험선 (G3 시작)
                    RuleMark(y: .value(NSLocalizedString("kp.chart.danger", comment: "Danger"), 7))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    // 현재 시간 표시선
                    RuleMark(x: .value(NSLocalizedString("kp.chart.current", comment: "Current"), Date()))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 86400)
                .chartYScale(domain: 0...9)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: manager.next48HoursForecast.compactMap { $0.date }) { value in
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
                .padding(.bottom, 4)
            }

            // 범례
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.normal.color)
                            .frame(width: 16, height: 8)
                        Text("Normal (0-5)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g1.color)
                            .frame(width: 16, height: 8)
                        Text("G1 (5-6)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g2.color)
                            .frame(width: 16, height: 8)
                        Text("G2 (6-7)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g3.color)
                            .frame(width: 16, height: 8)
                        Text("G3 (7-8)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g4.color)
                            .frame(width: 16, height: 8)
                        Text("G4 (8-9)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g5.color)
                            .frame(width: 16, height: 8)
                        Text("G5 (≥9)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
            .padding(.leading, 23)

            // 데이터 출처
            HStack {
                Spacer()
                Link("Data: NOAA SWPC", destination: URL(string: "https://www.swpc.noaa.gov/products/noaa-planetary-k-index-forecast")!)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - 장기예보 차트 (27일)

    private var longTermForecastChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("kp.section.forecast27", comment: "Long-term Forecast (27 days)"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(NSLocalizedString("kp.forecast27.note", comment: "UTC time"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(6)
            }

            if manager.isLoading {
                ProgressView()
                    .frame(height: 200)
            } else if manager.longTermForecastData.isEmpty {
                Text(NSLocalizedString("kp.noData", comment: "No data available"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(manager.longTermForecastData) { data in
                        // 영역 그래프
                        AreaMark(
                            x: .value("날짜", data.date ?? Date()),
                            y: .value("KP", data.kp)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    KPLevel.level(from: data.kp).color.opacity(0.3),
                                    KPLevel.level(from: data.kp).color.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // 라인 그래프
                        LineMark(
                            x: .value("날짜", data.date ?? Date()),
                            y: .value("KP", data.kp)
                        )
                        .foregroundStyle(KPLevel.level(from: data.kp).color)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        // 포인트 마크
                        PointMark(
                            x: .value("날짜", data.date ?? Date()),
                            y: .value("KP", data.kp)
                        )
                        .foregroundStyle(KPLevel.level(from: data.kp).color)
                        .symbol {
                            Circle()
                                .fill(KPLevel.level(from: data.kp).color)
                                .frame(width: 6, height: 6)
                        }
                        .annotation(position: .top, alignment: .center) {
                            Text(String(format: "%.1f", data.kp))
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }

                    // 주의선 (G1 시작)
                    RuleMark(y: .value(NSLocalizedString("kp.chart.caution", comment: "Caution"), 5))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    // 위험선 (G3 시작)
                    RuleMark(y: .value(NSLocalizedString("kp.chart.danger", comment: "Danger"), 7))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    // 현재 시간 표시선 (UTC 기준, 12시간 후)
                    RuleMark(x: .value(NSLocalizedString("kp.chart.current", comment: "Current"), Date().addingTimeInterval(12 * 60 * 60)))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 786240) // 늘리면 X축의 간격이 줄어듦
                .chartYScale(domain: 0...9)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: manager.longTermForecastData.compactMap { $0.date }) { value in
                        AxisGridLine()
                        AxisValueLabel(collisionResolution: .disabled) {
                            if let date = value.as(Date.self) {
                                Text(formatChartDate(date))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .offset(x: -19)
                            }
                        }
                    }
                }
                .frame(height: 250)
                .padding(.bottom, 4)
            }

            // 범례
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.normal.color)
                            .frame(width: 16, height: 8)
                        Text("Normal (0-5)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g1.color)
                            .frame(width: 16, height: 8)
                        Text("G1 (5-6)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g2.color)
                            .frame(width: 16, height: 8)
                        Text("G2 (6-7)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g3.color)
                            .frame(width: 16, height: 8)
                        Text("G3 (7-8)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g4.color)
                            .frame(width: 16, height: 8)
                        Text("G4 (8-9)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KPLevel.g5.color)
                            .frame(width: 16, height: 8)
                        Text("G5 (≥9)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
            .padding(.leading, 23)

            // 데이터 출처
            HStack {
                Spacer()
                Link("Data: NOAA SWPC", destination: URL(string: "https://www.swpc.noaa.gov/products/27-day-outlook-107-cm-radio-flux-and-geomagnetic-indices")!)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Helper Methods

    private func levelDescription(for level: KPLevel) -> String {
        switch level {
        case .normal:
            return NSLocalizedString("kp.level.normal.desc", comment: "Low geomagnetic activity")
        case .g1:
            return NSLocalizedString("kp.level.g1.desc", comment: "Minor geomagnetic storm")
        case .g2:
            return NSLocalizedString("kp.level.g2.desc", comment: "Moderate geomagnetic storm")
        case .g3:
            return NSLocalizedString("kp.level.g3.desc", comment: "Strong geomagnetic storm")
        case .g4:
            return NSLocalizedString("kp.level.g4.desc", comment: "Severe geomagnetic storm")
        case .g5:
            return NSLocalizedString("kp.level.g5.desc", comment: "Extreme geomagnetic storm")
        }
    }

    private func formatChartTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    private func formatChartDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}

#Preview {
    KPForecastView()
}
