//
//  DroneDetailView.swift
//  DronePass
//
//  Created by 문주성 on 10/2/25.
//

import SwiftUI

struct DroneDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var droneManager = DroneManager.shared

    let droneId: String

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingShapeHandlingSheet = false
    @State private var showingDroneSelectionSheet = false
    @State private var showingErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var connectedShapeCount: Int = 0
    @State private var selectedTargetDroneId: String?
    @State private var currentDrone: DroneModel?
    @State private var showCopyToast = false
    @State private var copyMessage = ""

    init(droneId: String) {
        self.droneId = droneId
        // init에서는 @State 초기화 불가, onAppear나 onChange에서 처리
    }

    var body: some View {
        Group {
            if let drone = currentDrone {
                droneDetailContent(drone: drone)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadDroneData()
        }
        .onChange(of: droneId) { oldValue, newValue in
            loadDroneData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dronesDidChange)) { _ in
            // Sheet 열려있을 때는 업데이트 무시 (iOS 버전 호환성)
            guard !showingEditSheet else { return }

            // 드론 업데이트 시 현재 드론 정보 갱신 (있으면)
            if let updated = droneManager.getDrone(by: droneId, includeDeleted: true) {
                currentDrone = updated
            }
            // 없어도 currentDrone 유지 (닫지 않음)
        }
    }

    private func loadDroneData() {
        currentDrone = droneManager.getDrone(by: droneId, includeDeleted: true)
        if currentDrone == nil {
            print("⚠️ 드론을 찾을 수 없음: \(droneId)")
        }
    }

    private func droneDetailContent(drone: DroneModel) -> some View {
        List {
            // 드론 이름 섹션
            Section {
                HStack {
                    Text(NSLocalizedString("drone.detail.name", comment: "Drone Name"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(drone.name)
                        .fontWeight(.medium)
                }
                .copyableText(drone.name, showToast: $showCopyToast, toastMessage: $copyMessage)
            }

            // 기본 정보 섹션
            Section {
                HStack {
                    Text(NSLocalizedString("drone.detail.color", comment: "Color"))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        if let color = drone.paletteColor {
                            Circle()
                                .fill(Color(color.uiColor))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                            Text(colorName(for: color))
                        }
                    }
                }
                .copyableText(
                    drone.paletteColor.map { colorName(for: $0) },
                    showToast: $showCopyToast,
                    toastMessage: $copyMessage
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("drone.detail.serial", comment: "Serial Number"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(drone.serialNumber ?? NSLocalizedString("drone.detail.serial.empty", comment: "Not entered"))
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .copyableText(drone.serialNumber, showToast: $showCopyToast, toastMessage: $copyMessage)
            } header: {
                Text(NSLocalizedString("drone.detail.section.basic", comment: "Basic Info"))
            }

            // 사양 섹션
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("drone.detail.weight", comment: "Takeoff Weight"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(drone.takeoffWeight ?? NSLocalizedString("drone.detail.serial.empty", comment: "Not entered"))
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .copyableText(drone.takeoffWeight, showToast: $showCopyToast, toastMessage: $copyMessage)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("drone.detail.size", comment: "Size"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(drone.size ?? NSLocalizedString("drone.detail.serial.empty", comment: "Not entered"))
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .copyableText(drone.size, showToast: $showCopyToast, toastMessage: $copyMessage)
            } header: {
                Text(NSLocalizedString("drone.detail.section.specs", comment: "Specifications"))
            }

            // 메모 섹션
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(drone.memo ?? NSLocalizedString("drone.detail.memo.empty", comment: "No memo"))
                        .font(.body)
                        .foregroundColor(drone.memo == nil ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .copyableText(drone.memo, showToast: $showCopyToast, toastMessage: $copyMessage)
            } header: {
                Text(NSLocalizedString("drone.detail.section.memo", comment: "Memo"))
            }
        }
        .navigationTitle(NSLocalizedString("drone.detail.title", comment: "Drone Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(NSLocalizedString("drone.detail.edit", comment: "Edit")) {
                        showingEditSheet = true
                    }

                    Button(NSLocalizedString("drone.detail.delete", comment: "Delete"), role: .destructive) {
                        handleDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet, onDismiss: {
            // Sheet 닫힐 때 드론 정보 갱신
            if let updated = droneManager.getDrone(by: droneId, includeDeleted: true) {
                currentDrone = updated
            }
        }) {
            if let currentDrone = currentDrone {
                NavigationStack {
                    DroneEditView(drone: currentDrone)
                }
            }
        }
        .confirmationDialog(
            NSLocalizedString("drone.detail.shapeHandling.title", comment: "Handle Connected Shapes"),
            isPresented: $showingShapeHandlingSheet,
            titleVisibility: .visible
        ) {
            Button(String(format: NSLocalizedString("drone.detail.shapeHandling.moveToOther", comment: "Move to another drone (%d)"), connectedShapeCount)) {
                showingDroneSelectionSheet = true
            }

            Button(String(format: NSLocalizedString("drone.detail.shapeHandling.deleteAll", comment: "Delete shapes too (%d)"), connectedShapeCount), role: .destructive) {
                deleteConfirmed(shapeHandling: .deleteAll)
            }

            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {
                connectedShapeCount = 0
            }
        } message: {
            Text(String(format: NSLocalizedString("drone.detail.shapeHandling.message", comment: "How would you like to handle %d shapes connected to '%@'?"), connectedShapeCount, drone.name))
        }
        .alert(NSLocalizedString("drone.detail.deleteAlert.title", comment: "Delete Drone"), isPresented: $showingDeleteAlert) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("drone.detail.delete", comment: "Delete"), role: .destructive) {
                deleteConfirmed(shapeHandling: .deleteAll)
            }
        } message: {
            Text(String(format: NSLocalizedString("drone.detail.deleteAlert.message", comment: "Are you sure you want to delete '%@'?"), drone.name))
        }
        .sheet(isPresented: $showingDroneSelectionSheet) {
            DroneSelectionSheet(
                availableDrones: droneManager.activeDrones.filter { $0.id != droneId },
                selectedDroneId: $selectedTargetDroneId,
                onConfirm: {
                    if let targetId = selectedTargetDroneId {
                        deleteConfirmed(shapeHandling: .reassignToDrone(targetId))
                    }
                },
                onCancel: {
                    connectedShapeCount = 0
                    selectedTargetDroneId = nil
                }
            )
        }
        .alert(NSLocalizedString("common.error", comment: "Error"), isPresented: $showingErrorAlert) {
            Button(NSLocalizedString("common.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .copyToast(showToast: $showCopyToast, message: copyMessage)
    }

    // MARK: - Private Methods

    private func handleDelete() {
        // 연결된 도형 개수 조회
        connectedShapeCount = droneManager.getShapeCount(for: droneId)

        if connectedShapeCount > 0 {
            // 도형이 있으면 처리 방법 선택 시트 표시
            showingShapeHandlingSheet = true
        } else {
            // 도형이 없으면 바로 삭제 확인 알림
            showingDeleteAlert = true
        }
    }

    private func deleteConfirmed(shapeHandling: ShapeHandlingOption) {
        Task {
            do {
                try await droneManager.deleteDrone(id: droneId, shapeHandling: shapeHandling)

                await MainActor.run {
                    connectedShapeCount = 0
                    print("✅ 드론 삭제 완료: \(currentDrone?.name ?? "")")
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    connectedShapeCount = 0
                    print("❌ 드론 삭제 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    private func colorName(for color: PaletteColor) -> String {
        return color.localizedName
    }
}

#Preview {
    NavigationView {
        DroneDetailView(droneId: DroneModel.createDefault().id)
    }
}
