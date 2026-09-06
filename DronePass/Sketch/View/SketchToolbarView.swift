//
//  SketchToolbarView.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 모드 하단 플로팅 도구 카드
// 연관기능: 색상 선택, 선 두께, 삭제, 완료

import SwiftUI

// MARK: - 색상 그라데이션 슬라이더

struct ColorGradientSlider: View {
    @Binding var selectedColor: String
    @State private var sliderPosition: CGFloat = 0.5

    // HSB 색상환 기반 그라데이션 (빨강 → 주황 → 노랑 → 초록 → 청록 → 파랑 → 보라 → 분홍 → 빨강)
    private var hueColors: [Color] {
        stride(from: 0.0, through: 1.0, by: 0.1).map { hue in
            Color(hue: hue, saturation: 0.85, brightness: 0.9)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 그라데이션 배경
                LinearGradient(colors: hueColors, startPoint: .leading, endPoint: .trailing)
                    .cornerRadius(15)

                // 슬라이더 thumb
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .fill(Color(hex: selectedColor) ?? .red)
                            .frame(width: 20, height: 20)
                    )
                    .position(x: 14 + sliderPosition * (geo.size.width - 28), y: geo.size.height / 2)
                    .allowsHitTesting(false) // thumb 터치 비활성화 (ZStack에서 처리)
            }
            .contentShape(Rectangle()) // 전체 영역 터치 가능
            .gesture(
                DragGesture(minimumDistance: 0) // 탭도 드래그로 인식
                    .onChanged { value in
                        let newPos = max(0, min(1, (value.location.x - 14) / (geo.size.width - 28)))
                        sliderPosition = newPos
                        selectedColor = hueToHex(hue: newPos)
                    }
            )
        }
        .frame(height: 30)
        .onAppear {
            sliderPosition = hexToHue(hex: selectedColor)
        }
        .onChange(of: selectedColor) { _, newColor in
            // 외부에서 색상이 변경되면 슬라이더 위치 업데이트
            let newPosition = hexToHue(hex: newColor)
            if abs(sliderPosition - newPosition) > 0.05 {
                sliderPosition = newPosition
            }
        }
    }

    // Hue (0~1) → Hex 문자열
    private func hueToHex(hue: CGFloat) -> String {
        let uiColor = UIColor(hue: hue, saturation: 0.85, brightness: 0.9, alpha: 1.0)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)

        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // Hex 문자열 → Hue (0~1)
    private func hexToHue(hex: String) -> CGFloat {
        guard let uiColor = UIColor(hex: hex) else { return 0 }

        var hue: CGFloat = 0
        uiColor.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)

        return hue
    }
}

// MARK: - 투명도 그라데이션 슬라이더

struct OpacityGradientSlider: View {
    @Binding var selectedOpacity: Double
    var selectedColor: String
    @State private var sliderPosition: CGFloat = 1.0

    // 투명도 그라데이션 색상 (투명 → 불투명)
    private var opacityColors: [Color] {
        let baseColor = Color(hex: selectedColor) ?? .red
        return [
            baseColor.opacity(0.1),
            baseColor.opacity(0.25),
            baseColor.opacity(0.5),
            baseColor.opacity(0.75),
            baseColor.opacity(1.0)
        ]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 체크무늬 배경 (투명도 표현용)
                CheckerboardPattern()
                    .cornerRadius(15)

                // 그라데이션 배경
                LinearGradient(colors: opacityColors, startPoint: .leading, endPoint: .trailing)
                    .cornerRadius(15)

                // 슬라이더 thumb
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .fill((Color(hex: selectedColor) ?? .red).opacity(selectedOpacity))
                            .frame(width: 20, height: 20)
                    )
                    .position(x: 14 + sliderPosition * (geo.size.width - 28), y: geo.size.height / 2)
                    .allowsHitTesting(false) // thumb 터치 비활성화 (ZStack에서 처리)
            }
            .contentShape(Rectangle()) // 전체 영역 터치 가능
            .gesture(
                DragGesture(minimumDistance: 0) // 탭도 드래그로 인식
                    .onChanged { value in
                        let newPos = max(0, min(1, (value.location.x - 14) / (geo.size.width - 28)))
                        sliderPosition = newPos
                        // 최소 투명도 0.1, 최대 1.0
                        selectedOpacity = 0.1 + (newPos * 0.9)
                    }
            )
        }
        .frame(height: 30)
        .onAppear {
            // 투명도를 슬라이더 위치로 변환 (0.1~1.0 → 0~1)
            sliderPosition = (selectedOpacity - 0.1) / 0.9
        }
        .onChange(of: selectedOpacity) { _, newOpacity in
            let newPosition = (newOpacity - 0.1) / 0.9
            if abs(sliderPosition - newPosition) > 0.05 {
                sliderPosition = newPosition
            }
        }
    }
}

// MARK: - 체크무늬 패턴 (투명도 배경)

struct CheckerboardPattern: View {
    let squareSize: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let columns = Int(ceil(size.width / squareSize))
                let rows = Int(ceil(size.height / squareSize))

                for row in 0..<rows {
                    for col in 0..<columns {
                        let isLight = (row + col) % 2 == 0
                        let rect = CGRect(
                            x: CGFloat(col) * squareSize,
                            y: CGFloat(row) * squareSize,
                            width: squareSize,
                            height: squareSize
                        )
                        context.fill(
                            Path(rect),
                            with: .color(isLight ? .white : Color.gray.opacity(0.3))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 펜 굵기 버튼 (아이폰 메모 스타일)

struct PenStrokeButton: View {
    let width: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 선택 시 검은 배경 원
                Circle()
                    .fill(isSelected ? Color.black : Color.clear)
                    .frame(width: 44, height: 44)

                // 기울어진 선 (단색)
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(isSelected ? Color.white : Color.gray)
                    .frame(width: width, height: 30)
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 펜 선택 팝오버 (미사용 - PenPickerCard로 대체)

struct PenPickerPopover: View {
    @ObservedObject var sketchManager: SketchManager

    let strokeWidths: [CGFloat] = [2, 4, 6, 8, 10]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(strokeWidths, id: \.self) { width in
                    PenStrokeButton(
                        width: width,
                        isSelected: sketchManager.currentStrokeWidth == Double(width)
                    ) {
                        sketchManager.setStrokeWidth(Double(width))
                    }
                }
            }

            Divider()

            ColorGradientSlider(selectedColor: Binding(
                get: { sketchManager.currentColor },
                set: { sketchManager.setColor($0) }
            ))
            .padding(.horizontal, 12)
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

// MARK: - 메인 스케치 툴바

struct SketchToolbarView: View {
    @ObservedObject var sketchManager = SketchManager.shared
    @ObservedObject var sketchFileStore = SketchFileStore.shared

    @State private var showPenPicker = false
    @State private var showDeleteConfirmation = false

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 펜 선택 카드 (툴바 위에 표시)
            if showPenPicker {
                PenPickerCard(sketchManager: sketchManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            }

            // 메인 툴바
            HStack(spacing: 12) {
                // 펜 버튼 (현재 굵기/색상 표시, 탭하면 카드 열기)
                Button(action: {
                    if sketchManager.isEraserModeActive {
                        // 지우개 모드 → 펜 모드로 전환
                        sketchManager.toggleEraserMode()
                    } else {
                        // 펜 모드에서 탭 → 카드 열기/닫기
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPenPicker.toggle()
                        }
                    }
                }) {
                    ZStack {
                        // 기울어진 선으로 현재 펜 표시
                        RoundedRectangle(cornerRadius: sketchManager.currentStrokeWidth / 2)
                            .fill(Color(hex: sketchManager.currentColor) ?? .red)
                            .frame(
                                width: max(3, sketchManager.currentStrokeWidth),
                                height: 20
                            )
                            .rotationEffect(.degrees(-45))
                    }
                    .frame(width: 32, height: 32)
                    .background(!sketchManager.isEraserModeActive ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                }

                // 지우개 버튼
                Button(action: {
                    if !sketchManager.isEraserModeActive {
                        sketchManager.toggleEraserMode()
                    }
                    // 지우개 선택 시 펜 카드 닫기
                    if showPenPicker {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPenPicker = false
                        }
                    }
                }) {
                    Image(systemName: "eraser")
                        .font(.system(size: 18))
                        .foregroundColor(sketchManager.isEraserModeActive ? .orange : .gray)
                        .frame(width: 32, height: 32)
                        .background(sketchManager.isEraserModeActive ? Color.orange.opacity(0.15) : Color.clear)
                        .cornerRadius(8)
                }

                // 실행취소 버튼
                Button(action: {
                    sketchManager.undo()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18))
                        .foregroundColor(sketchManager.canUndo ? .primary : .gray.opacity(0.4))
                        .frame(width: 32, height: 32)
                }
                .disabled(!sketchManager.canUndo)

                // 다시실행 버튼
                Button(action: {
                    sketchManager.redo()
                }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 18))
                        .foregroundColor(sketchManager.canRedo ? .primary : .gray.opacity(0.4))
                        .frame(width: 32, height: 32)
                }
                .disabled(!sketchManager.canRedo)

                Divider()
                    .frame(height: 24)

                // 전체 삭제 버튼 (뱃지 포함)
                Button(action: {
                    if sketchFileStore.activeSketchCount > 0 {
                        showDeleteConfirmation = true
                    }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(sketchFileStore.activeSketchCount > 0 ? .red : .gray)
                            .frame(width: 32, height: 32)

                        // 스케치 개수 뱃지
                        if sketchFileStore.activeSketchCount > 0 {
                            Text("\(sketchFileStore.activeSketchCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .disabled(sketchFileStore.activeSketchCount == 0)
                .alert(String(localized: "sketch.alert.deleteAll.title"), isPresented: $showDeleteConfirmation) {
                    Button(String(localized: "common.cancel"), role: .cancel) {}
                    Button(String(localized: "common.delete"), role: .destructive) {
                        sketchManager.deleteAllSketches()
                    }
                } message: {
                    Text(String(format: String(localized: "sketch.alert.deleteAll.message"), sketchFileStore.activeSketchCount))
                }

                // 완료 버튼
                Button(action: onComplete) {
                    Text(String(localized: "sketch.button.done"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .shadow(radius: 10, x: 0, y: 5)
        }
    }
}

// MARK: - 펜 선택 카드 (아이폰 메모 스타일)

struct PenPickerCard: View {
    @ObservedObject var sketchManager: SketchManager

    let strokeWidths: [CGFloat] = [2, 4, 6, 8, 10]

    // 펜 버튼 크기 및 간격
    private let buttonSize: CGFloat = 44
    private let buttonSpacing: CGFloat = 4

    // 카드 내부 너비 계산 (펜 5개 + 간격 4개)
    private var contentWidth: CGFloat {
        (buttonSize * 5) + (buttonSpacing * 4)
    }

    var body: some View {
        VStack(spacing: 10) {
            // 굵기 선택
            HStack(spacing: buttonSpacing) {
                ForEach(strokeWidths, id: \.self) { width in
                    PenStrokeButton(
                        width: width,
                        isSelected: sketchManager.currentStrokeWidth == Double(width)
                    ) {
                        sketchManager.setStrokeWidth(Double(width))
                    }
                }
            }

            Divider()
                .frame(width: contentWidth)

            // 색상 선택 (그라데이션 슬라이더)
            ColorGradientSlider(selectedColor: Binding(
                get: { sketchManager.currentColor },
                set: { sketchManager.setColor($0) }
            ))
            .frame(width: contentWidth)

            Divider()
                .frame(width: contentWidth)

            // 투명도 선택 (그라데이션 슬라이더)
            OpacityGradientSlider(
                selectedOpacity: Binding(
                    get: { sketchManager.currentOpacity },
                    set: { sketchManager.setOpacity($0) }
                ),
                selectedColor: sketchManager.currentColor
            )
            .frame(width: contentWidth)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack {
            Spacer()
            SketchToolbarView(onComplete: {})
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
    }
}
