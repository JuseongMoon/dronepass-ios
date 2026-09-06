//
//  FlightZoneLayerSelector.swift
//  DronePass
//
//  드론 비행 구역 레이어 선택 UI (지도 플로팅 버튼)
//

import SwiftUI

/// 지도 위에 표시되는 드론 구역 레이어 선택 플로팅 버튼
struct FlightZoneLayerSelector: View {

    @ObservedObject var overlayManager: FlightZoneOverlayManager

    /// 레이어 선택 시트 표시 여부
    @State private var showLayerSheet = false

    /// 전체 토글 애니메이션
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            // 플로팅 버튼
            Button(action: {
                showLayerSheet = true
                HapticManager.shared.impact(style: .light)
            }) {
                VStack(spacing: 4) {
                    Image(systemName: overlayManager.visibleLayerCount > 0 ? "map.fill" : "map")
                        .font(.system(size: 22))
                        .foregroundColor(overlayManager.visibleLayerCount > 0 ? .blue : .gray)

                    if overlayManager.visibleLayerCount > 0 {
                        Text("\(overlayManager.visibleLayerCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                .frame(width: 50, height: 50)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
        }
        .sheet(isPresented: $showLayerSheet) {
            LayerSelectionSheet(overlayManager: overlayManager)
        }
        .onChange(of: overlayManager.visibleLayerCount) { _ in
            // 레이어 개수 변경 시 애니메이션
            withAnimation {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    isAnimating = false
                }
            }
        }
    }
}

/// 레이어 선택 시트
struct LayerSelectionSheet: View {

    @ObservedObject var overlayManager: FlightZoneOverlayManager

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 법적 책임 회피 안내 배너
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)

                    Text(NSLocalizedString("vworld.disclaimer.legalNotice", comment: "Legal disclaimer for VWorld data"))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // 통계 헤더
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("vworld.layer.selected", comment: "Selected Layers"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(overlayManager.visibleLayerCount) / \(FlightZoneLayer.allCases.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(NSLocalizedString("vworld.zone.displayed", comment: "Displayed Zones"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(overlayManager.overlayCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))

                // 전체 선택/해제 버튼
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await overlayManager.showAllLayers()
                        }
                        HapticManager.shared.impact(style: .medium)
                    }) {
                        Label(NSLocalizedString("vworld.button.selectAll", comment: "Select All"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        Task {
                            await overlayManager.hideAllLayers()
                        }
                        HapticManager.shared.impact(style: .medium)
                    }) {
                        Label(NSLocalizedString("vworld.button.deselectAll", comment: "Deselect All"), systemImage: "xmark.circle.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                    }
                }
                .padding()

                Divider()

                // 레이어 목록
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(FlightZoneLayer.allCases.sorted(by: { $0.displayName < $1.displayName }), id: \.id) { layer in
                            LayerRow(
                                layer: layer,
                                isSelected: overlayManager.isLayerVisible(layer),
                                onToggle: {
                                    Task {
                                        await overlayManager.toggleLayer(layer)
                                    }
                                    HapticManager.shared.impact(style: .light)
                                }
                            )
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("vworld.title.flightZones", comment: "Drone Flight Zones"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("vworld.button.done", comment: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 개별 레이어 행
struct LayerRow: View {

    let layer: FlightZoneLayer
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 체크박스
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 30)

                // 색상 표시
                RoundedRectangle(cornerRadius: 4)
                    .fill(layer.overlayColor)
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(layer.borderUIColor), lineWidth: 2)
                    )

                // 구역명
                Text(layer.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Haptic Manager

/// 햅틱 피드백 관리 (기존 프로젝트에 없을 경우 추가)
class HapticManager {
    static let shared = HapticManager()

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - Preview

#Preview {
    let manager = FlightZoneOverlayManager()
    return FlightZoneLayerSelector(overlayManager: manager)
}
