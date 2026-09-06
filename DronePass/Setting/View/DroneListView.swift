//
//  DroneListView.swift
//  DronePass
//
//  Created by Claude on 2025-09-30.
//

// 역할: 드론 관리 화면 (CRUD)
// 연관기능: 드론 추가, 편집, 삭제, 색상 변경, 기본 드론 설정

import SwiftUI
import UIKit

// MARK: - Helper Types

struct DroneIdWrapper: Identifiable {
    let id: String
}

struct DroneListView: View {
    @ObservedObject private var droneManager = DroneManager.shared
    @State private var showingAddDroneSheet = false
    @State private var selectedDroneForDetail: DroneIdWrapper?

    var body: some View {
        List {
            // 현재 드론 목록
            Section {
                ForEach(droneManager.activeDrones) { drone in
                    DroneRowView(drone: drone)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDroneForDetail = DroneIdWrapper(id: drone.id)
                        }
                }
            } header: {
                Text(NSLocalizedString("drone.list.section.my", comment: "My Drones"))
            } footer: {
                if droneManager.activeDrones.isEmpty {
                    Text(NSLocalizedString("drone.list.empty", comment: "No drones registered."))
                        .foregroundColor(.secondary)
                }
            }

            // 드론 추가 버튼
            Section {
                Button(action: {
                    showingAddDroneSheet = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(NSLocalizedString("drone.list.addNew", comment: "Add New Drone"))
                            .foregroundColor(.primary)
                    }
                }
            }

            // 정보 섹션
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("drone.list.usage.colorCustomization", comment: "• Each drone can have a unique color"))
                    Text(NSLocalizedString("drone.list.usage.lastDrone", comment: "• Cannot delete the last remaining drone"))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text(NSLocalizedString("drone.list.section.usage", comment: "How to Use"))
            }
        }
        .navigationTitle(NSLocalizedString("drone.list.title", comment: "Manage Drones"))
        .sheet(isPresented: $showingAddDroneSheet) {
            NavigationStack {
                DroneEditView(drone: nil)
            }
        }
        .sheet(item: $selectedDroneForDetail) { wrapper in
            NavigationStack {
                DroneDetailView(droneId: wrapper.id)
            }
        }
    }
}

// MARK: - 드론 행 뷰

struct DroneRowView: View {
    let drone: DroneModel

    var body: some View {
        HStack {
            // 드론 색상 원형
            if let color = drone.paletteColor {
                Circle()
                    .fill(Color(color.uiColor))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(drone.name)
                    .font(.system(size: 16, weight: .medium))
            }

            Spacer()
        }
    }
}

// MARK: - 색상 선택 그리드

struct ColorPickerGrid: View {
    @Binding var selectedColor: PaletteColor

    // 회색 제외한 색상 목록
    private var availableColors: [PaletteColor] {
        PaletteColor.allCases.filter { $0 != .gray }
    }

    // 색상명 표기
    private func colorName(for color: PaletteColor) -> String {
        return color.localizedName
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(availableColors, id: \.self) { color in
                HStack {
                    Circle()
                        .fill(Color(color.uiColor))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )

                    Text(colorName(for: color))
                        .font(.body)

                    Spacer()

                    if color == selectedColor {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedColor = color
                }

                if color != availableColors.last {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
    }
}

// MARK: - 드론 선택 시트

struct DroneSelectionSheet: View {
    let availableDrones: [DroneModel]
    @Binding var selectedDroneId: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(availableDrones) { drone in
                        HStack {
                            // 드론 색상 원형
                            if let color = drone.paletteColor {
                                Circle()
                                    .fill(Color(color.uiColor))
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                    )
                            }

                            Text(drone.name)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedDroneId == drone.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDroneId = drone.id
                        }
                    }
                } header: {
                    Text(NSLocalizedString("drone.select.moveShape", comment: "Select drone to move shape"))
                }
            }
            .navigationTitle(NSLocalizedString("drone.select.title", comment: "Select Drone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("drone.edit.cancel", comment: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("drone.select.confirm", comment: "Confirm")) {
                        dismiss()
                        onConfirm()
                    }
                    .disabled(selectedDroneId == nil)
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        DroneListView()
    }
}
