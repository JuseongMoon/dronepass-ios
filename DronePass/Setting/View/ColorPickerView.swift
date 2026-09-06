//
//  ColorPickerView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//

import SwiftUI

struct ColorPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedColor: PaletteColor
    @State private var lastColorChangeTime: Date = Date.distantPast
    private let colorChangeDebounceInterval: TimeInterval = 0.5 // 500ms
    
    let onColorSelected: (PaletteColor) -> Void
    
    init(selected: PaletteColor, onColorSelected: @escaping (PaletteColor) -> Void) {
        // 현재 도형의 실제 색상을 가져와서 초기값으로 설정
        let currentShapeColor: PaletteColor
        if let firstShape = ShapeFileStore.shared.shapes.first,
           let color = PaletteColor.allCases.first(where: { $0.hex.lowercased() == firstShape.color.lowercased() }) {
            currentShapeColor = color
        } else {
            currentShapeColor = selected
        }
        
        self._selectedColor = State(initialValue: currentShapeColor)
        self.onColorSelected = onColorSelected
    }
    
    private var availableColors: [PaletteColor] {
        PaletteColor.allCases.filter { $0 != .gray }
    }
    
    // 색상명 표기
    private func colorName(for color: PaletteColor) -> String {
        return color.localizedName
    }
    
    var body: some View {
        List {
            ForEach(Array(availableColors.enumerated()), id: \.element) { idx, color in
                HStack {
                    Circle()
                        .fill(Color(color.uiColor))
                        .frame(width: 24, height: 24)
                    Text(colorName(for: color))
                        .font(idx == selectedColorIndex ? .headline : .body)
                    Spacer()
                    if color == selectedColor {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedColor = color
                    updateAllShapesColorIfNeeded(to: color)
                }
            }
        }
        .navigationTitle(NSLocalizedString("color.picker.title", comment: "Select Color"))
    }
    
    /// 중복 색상 변경 작업을 방지하는 디바운싱 업데이트
    private func updateAllShapesColorIfNeeded(to color: PaletteColor) {
        let now = Date()
        if now.timeIntervalSince(lastColorChangeTime) >= colorChangeDebounceInterval {
            // 전체 도형 색상 변경
            ShapeFileStore.shared.updateAllShapesColor(to: color.hex)
            
            // 로컬 변경 사항 추적
            UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
            print("✅ 도형 색상 변경 및 로컬 변경 추적 기록")
            
            // 색상 변경 시점 기록
            ColorManager.shared.recordColorChange()
            
            // 지도 오버레이 리로드 알림 전송
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
                NotificationCenter.default.post(name: .shapesDidChange, object: nil)
            }
            
            // Firebase 업데이트는 ShapeFileStore.updateAllShapesColor에서 처리됨
            
            ColorManager.shared.defaultColor = color
            onColorSelected(color)
            presentationMode.wrappedValue.dismiss()
            
            lastColorChangeTime = now
        } else {
            print("📝 색상 변경 디바운싱: 이전 변경으로부터 \(String(format: "%.3f", now.timeIntervalSince(lastColorChangeTime)))초 경과")
        }
    }

    private var selectedColorIndex: Int {
        availableColors.firstIndex(of: selectedColor) ?? 0
    }
}

#Preview {
    ColorPickerView(selected: .blue) { _ in }
}
