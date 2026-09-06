//
//  MainFloatingButtonView.swift
//  DronePass
//
//  Created by 문주성 on 10/16/25.
//

import SwiftUI
import NMapsMap

/// 메인 화면의 모든 플로팅 버튼을 관리하는 컴포넌트
struct MainFloatingButtonView: View {
    // MARK: - Properties

    @ObservedObject var droneManager: DroneManager
    @ObservedObject var kpIndexManager: KPIndexManager
    @ObservedObject var weatherManager: WeatherManager
    @ObservedObject var settingManager: SettingManager
    @ObservedObject var flightZoneManager: FlightZoneOverlayManager

    let geometry: GeometryProxy
    let mapView: NMFMapView?
    let dropdownTopPadding: CGFloat

    // Bindings for actions
    @Binding var showWeatherInfoSheet: Bool
    @Binding var showKPForecastSheet: Bool
    let onCreateShape: (CoordinateManager) -> Void
    @Binding var isSketchModeActive: Bool

    // 스케치 관련
    @ObservedObject var sketchFileStore = SketchFileStore.shared

    // MARK: - Padding Constants

    private let floatingUITrailingPaddingForIPhone: CGFloat = 12
    private let floatingUITrailingPaddingForOtherDevices: CGFloat = 20

    private var floatingUITrailingPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone
            ? floatingUITrailingPaddingForIPhone
            : floatingUITrailingPaddingForOtherDevices
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. 상단 드론 선택 드롭다운
            droneDropdownView

            // 2. 좌측 하단 VWorld 레이어 선택 버튼 (한국 특화 기능 활성화 시에만 표시)
            if settingManager.isKoreaFeaturesEnabled {
                leftBottomButtonsView
            }

            // 3-5. 우측 하단 날씨/KP 박스들
            rightBottomButtonsView

            // 6. 플러스 버튼
            plusButtonView
        }
    }

    // MARK: - View Components

    /// 상단 드론 선택 드롭다운
    private var droneDropdownView: some View {
        VStack {
            HStack {
                Spacer()
                DroneSelectionDropdown(droneManager: droneManager)
                    .padding(.trailing, 16)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, geometry.safeAreaInsets.top + dropdownTopPadding)
    }

    /// 좌측 하단 VWorld 드론 구역 레이어 선택 버튼
    private var leftBottomButtonsView: some View {
        VStack {
            Spacer()
            HStack {
                FlightZoneLayerSelector(overlayManager: flightZoneManager)
                    .padding(.leading, floatingUITrailingPadding)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, geometry.safeAreaInsets.bottom + 100)
    }

    /// 우측 하단 날씨/KP 박스들
    private var rightBottomButtonsView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    // 스케치 버튼 (KP 위)
                    sketchButton

                    // KP 지수 버튼
                    kpIndexButton

                    // 날씨/풍향 아이콘 버튼
                    weatherWindIconButton

                }
                .padding(.trailing, floatingUITrailingPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, geometry.safeAreaInsets.bottom + 170)
    }

    /// 날씨/풍향 아이콘 버튼
    private var weatherWindIconButton: some View {
        Button(action: {
            showWeatherInfoSheet = true
        }) {
            VStack(spacing: 8) {
                // 첫 번째 줄: 날씨 + 풍향 아이콘 + 온도
                HStack(spacing: 8) {
                    // 왼쪽: 현재 날씨 아이콘
                    Image(systemName: weatherManager.precipitationIconName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.blue)

                    // 가운데: 풍향 아이콘 (회전)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.teal)
                        .rotationEffect(Angle(degrees: (weatherManager.windDirection ?? 0) + 180))

                    // 오른쪽: 온도
                    Text(weatherManager.temperatureString)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(weatherManager.temperatureColor)
                }

                // 두 번째 줄: 일출/일몰 아이콘 + 시간
                HStack(spacing: 8) {
                    Image(systemName: settingManager.sunEventIconName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.orange)

                    Text(settingManager.timeUntilNextSunEvent)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }


    /// KP 지수 버튼
    private var kpIndexButton: some View {
        Button(action: {
            showKPForecastSheet = true
        }) {
            HStack(alignment: .center, spacing: 4) {
                Text("KP")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(kpIndexManager.currentLevel.color)

                Text(kpIndexManager.currentKPString)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(kpIndexManager.currentLevel.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }

    /// 스케치 버튼 (크기 2/3로 축소)
    private var sketchButton: some View {
        Button(action: {
            isSketchModeActive = true
        }) {
            Image(systemName: "pencil.tip")
                .font(.system(size: 21, weight: .medium))
                .foregroundColor(Color.accentColor)
                .frame(width: 45, height: 45)
                .background(Color(UIColor.systemBackground))
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .accessibilityLabel("스케치 모드")
    }

    /// 플러스 버튼
    private var plusButtonView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    let center: NMGLatLng
                    if let mapView = mapView {
                        center = mapView.cameraPosition.target
                    } else {
                        center = NMGLatLng(lat: 37.5665, lng: 126.9780)
                    }
                    onCreateShape(CoordinateManager(latitude: center.lat, longitude: center.lng))
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .none))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 60, height: 60)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(radius: 6)
                        .accessibilityLabel(NSLocalizedString("mainView.newShape.add", comment: "Add New Shape"))
                }
                .padding(.trailing, floatingUITrailingPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, geometry.safeAreaInsets.bottom + 90)
    }
}

// MARK: - 드론 선택 드롭다운 컴포넌트

struct DroneSelectionDropdown: View {
    @ObservedObject var droneManager: DroneManager
    @State private var showingDropdown = false
    @State private var triggerHeight: CGFloat = 0

    var body: some View {
        // 트리거 버튼 영역만 (드롭다운 메뉴 제외)
        ZStack(alignment: .topTrailing) {
            // 선택된 드론들을 가나다순으로 정렬하여 버튼 생성
            if droneManager.selectedDrones.isEmpty {
                // 선택 없음: "드론 선택" 버튼
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "drone")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)

                        Text(NSLocalizedString("drone.select.title", comment: "Select Drone"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                    Spacer()
                        .frame(width: 40) // chevron 공간 확보
                }
            } else {
                // 선택된 드론들을 래핑 레이아웃으로 표시 (chevron 공간 예약: 32 + 8)
                WrappingHStack(alignment: .trailing, spacing: 8, lineSpacing: 4, firstLineReservedWidth: 40) {
                    ForEach(droneManager.selectedDrones) { drone in
                        Button(action: {
                            droneManager.toggleDroneHighlight(drone.id)
                        }) {
                            HStack(spacing: 6) {
                                // 드론 색상 원형
                                if let color = drone.paletteColor {
                                    Circle()
                                        .fill(Color(color.uiColor))
                                        .frame(width: 12, height: 12)
                                }

                                Text(drone.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        droneManager.isHighlightedDrone(drone.id)
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Chevron 원형 버튼 (항상 우측 상단에 고정)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingDropdown.toggle()
                }
            }) {
                Image(systemName: showingDropdown ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    triggerHeight = geo.size.height
                }
                .onChange(of: geo.size.height) { _, newHeight in
                    triggerHeight = newHeight
                }
            }
        )
        .overlay(alignment: .topTrailing) {
            // 드롭다운 메뉴 (독립적 overlay)
            if showingDropdown {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(droneManager.activeDrones) { drone in
                        Button(action: {
                            droneManager.toggleDroneSelection(drone.id)

                            // 체크 해제 시 강조 상태도 제거
                            if !droneManager.isSelectedDrone(drone.id) {
                                if droneManager.isHighlightedDrone(drone.id) {
                                    droneManager.toggleDroneHighlight(drone.id)
                                }
                            }
                            // 체크박스 방식이므로 드롭다운을 닫지 않음
                        }) {
                            HStack(spacing: 8) {
                                // 체크박스 아이콘
                                Image(systemName: droneManager.isSelectedDrone(drone.id)
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(droneManager.isSelectedDrone(drone.id)
                                        ? .accentColor
                                        : .gray)

                                // 드론 색상 원형 표시
                                if let color = drone.paletteColor {
                                    Circle()
                                        .fill(Color(color.uiColor))
                                        .frame(width: 12, height: 12)
                                } else {
                                    Circle()
                                        .fill(Color.gray)
                                        .frame(width: 12, height: 12)
                                }

                                Text(drone.name)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if drone.id != droneManager.activeDrones.last?.id {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .offset(y: triggerHeight + 4)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
            }
        }
    }
}

// MARK: - 래핑 HStack (여러 줄 지원)

struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let firstLineReservedWidth: CGFloat
    let content: Content

    init(alignment: HorizontalAlignment = .leading, spacing: CGFloat = 8, lineSpacing: CGFloat = 8, firstLineReservedWidth: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.firstLineReservedWidth = firstLineReservedWidth
        self.content = content()
    }

    var body: some View {
        FlowLayout(spacing: spacing, lineSpacing: lineSpacing, firstLineReservedWidth: firstLineReservedWidth) {
            content
        }
    }
}

// MARK: - FlowLayout (드론 선택 드롭다운 자동 줄바꿈 레이아웃)

struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var firstLineReservedWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let proposalWidth = proposal.replacingUnspecifiedDimensions().width

        // 1단계: 각 줄에 들어갈 항목들을 그룹화
        var lines: [[(index: Int, size: CGSize)]] = [[]]
        var currentLineWidth: CGFloat = 0
        var currentLineIndex = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)

            // 첫 줄은 예약된 공간을 제외한 너비 사용
            let availableWidth = currentLineIndex == 0 ? proposalWidth - firstLineReservedWidth : proposalWidth

            if currentLineWidth + size.width > availableWidth && currentLineWidth > 0 {
                // 다음 줄로 이동
                currentLineIndex += 1
                lines.append([])
                currentLineWidth = 0
            }

            lines[currentLineIndex].append((index: index, size: size))
            currentLineWidth += size.width + spacing
        }

        // 2단계: 각 줄을 우측 정렬로 배치 (줄 내부는 왼쪽부터)
        var positions: [CGPoint] = Array(repeating: .zero, count: subviews.count)
        var currentY: CGFloat = 0
        let maxWidth: CGFloat = proposalWidth

        // 각 줄을 배치 (각 줄은 proposalWidth 기준으로 우측 정렬, 줄 내부는 왼쪽부터)
        for (lineIndex, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }

            // 현재 줄의 전체 너비 계산
            let lineWidth = line.map { $0.size.width }.reduce(0, +) + CGFloat(line.count - 1) * spacing

            // 현재 줄의 최대 높이 계산
            let lineHeight = line.map { $0.size.height }.max() ?? 0

            // 줄의 시작 x 위치 (proposalWidth 기준 우측 정렬)
            // 첫 줄은 예약된 공간을 제외
            let availableWidth = lineIndex == 0 ? proposalWidth - firstLineReservedWidth : proposalWidth
            var currentX = availableWidth - lineWidth

            for item in line {
                positions[item.index] = CGPoint(x: currentX, y: currentY)
                currentX += item.size.width + spacing
            }

            currentY += lineHeight + lineSpacing
        }

        let totalHeight = currentY - lineSpacing
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
