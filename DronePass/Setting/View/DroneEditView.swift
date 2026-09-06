//
//  DroneEditView.swift
//  DronePass
//
//  Created by 문주성 on 10/2/25.
//

import SwiftUI
import UIKit

struct DroneEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var droneManager = DroneManager.shared

    let drone: DroneModel?  // Optional로 변경: nil이면 추가 모드

    @State private var droneName: String = ""
    @State private var selectedColor: PaletteColor = .blue
    @State private var serialNumber: String = ""
    @State private var takeoffWeight: String = ""
    @State private var size: String = ""
    @State private var memo: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""

    // 추가 모드인지 확인
    private var isAddMode: Bool {
        drone == nil
    }

    // 텍스트 너비 계산
    private func textWidth(_ text: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 17)
        let attributes = [NSAttributedString.Key.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size.width
    }

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("drone.edit.name.placeholder", comment: "Drone name"), text: $droneName)
                    .onChange(of: droneName) { oldValue, newValue in
                        let maxWidth: CGFloat = 210
                        if textWidth(newValue) > maxWidth {
                            droneName = oldValue
                        }
                    }
            } header: {
                Text(NSLocalizedString("drone.edit.section.basic", comment: "Basic Information"))
            } footer: {
                Text(NSLocalizedString("drone.edit.section.basic.footer", comment: "Please keep it within one line"))
                    .font(.caption)
            }

            Section {
                ColorPickerGrid(selectedColor: $selectedColor)
            } header: {
                Text(NSLocalizedString("drone.detail.color", comment: "Color"))
            }

            Section {
                TextField(NSLocalizedString("drone.edit.serial.placeholder", comment: "Enter serial number (optional)"), text: $serialNumber)
            } header: {
                Text(NSLocalizedString("drone.edit.section.serial", comment: "Serial Number"))
            } footer: {
                Text(NSLocalizedString("drone.edit.section.serial.footer", comment: "Enter your drone's manufacturing or serial number"))
                    .font(.caption)
            }

            Section {
                TextField(NSLocalizedString("drone.edit.weight.placeholder", comment: "e.g., 249g"), text: $takeoffWeight)
                TextField(NSLocalizedString("drone.edit.size.placeholder", comment: "e.g., 140×140×55mm"), text: $size)
            } header: {
                Text(NSLocalizedString("drone.edit.section.specs", comment: "Specifications"))
            } footer: {
                Text(NSLocalizedString("drone.edit.section.specs.footer", comment: "Enter drone's takeoff weight and size"))
                    .font(.caption)
            }

            Section {
                TextEditor(text: $memo)
                    .frame(minHeight: 100)
            } header: {
                Text(NSLocalizedString("drone.edit.section.memo", comment: "Memo"))
            } footer: {
                Text(NSLocalizedString("drone.edit.section.memo.footer", comment: "Write notes about your drone freely"))
                    .font(.caption)
            }
        }
        .navigationTitle(isAddMode ? NSLocalizedString("drone.edit.title.add", comment: "Add New Drone") : NSLocalizedString("drone.edit.title.edit", comment: "Edit Drone"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("drone.edit.cancel", comment: "Cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isAddMode ? NSLocalizedString("drone.edit.add", comment: "Add") : NSLocalizedString("drone.edit.save", comment: "Save")) {
                    saveDrone()
                }
                .disabled(droneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            if let drone = drone {
                // 편집 모드: 기존 드론 데이터 로드
                droneName = drone.name
                selectedColor = drone.paletteColor ?? .blue
                serialNumber = drone.serialNumber ?? ""
                takeoffWeight = drone.takeoffWeight ?? ""
                size = drone.size ?? ""
                memo = drone.memo ?? ""
            } else {
                // 추가 모드: 기본값 설정
                droneName = String(format: NSLocalizedString("drone.edit.defaultName", comment: "Drone %d"), droneManager.activeDrones.count + 1)
                selectedColor = droneManager.suggestedNextColor()
            }
        }
        .alert(NSLocalizedString("drone.edit.alert.saveFailed", comment: "Save Failed"), isPresented: $showingAlert) {
            Button(NSLocalizedString("common.confirm", comment: "OK"), role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func saveDrone() {
        let trimmedName = droneName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            alertMessage = NSLocalizedString("drone.edit.alert.nameRequired", comment: "Please enter a drone name.")
            showingAlert = true
            return
        }

        guard !droneManager.isDuplicateName(trimmedName, excludingId: drone?.id) else {
            alertMessage = NSLocalizedString("drone.edit.alert.nameDuplicate", comment: "This drone name already exists.")
            showingAlert = true
            return
        }

        // 빈 문자열을 nil로 변환
        let finalSerialNumber = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : serialNumber
        let finalTakeoffWeight = takeoffWeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : takeoffWeight
        let finalSize = size.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : size
        let finalMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : memo

        if isAddMode {
            // 추가 모드: 새 드론 생성
            droneManager.addDrone(name: trimmedName, color: selectedColor)
            // 사양과 메모는 생성 후 업데이트
            if let newDrone = droneManager.activeDrones.last {
                droneManager.updateDrone(
                    id: newDrone.id,
                    serialNumber: finalSerialNumber,
                    takeoffWeight: finalTakeoffWeight,
                    size: finalSize,
                    memo: finalMemo
                )
            }
        } else {
            // 편집 모드: 기존 드론 업데이트
            droneManager.updateDrone(
                id: drone!.id,
                name: trimmedName,
                color: selectedColor.rawValue,
                serialNumber: finalSerialNumber,
                takeoffWeight: finalTakeoffWeight,
                size: finalSize,
                memo: finalMemo
            )
        }
        dismiss()
    }
}

#Preview {
    DroneEditView(drone: DroneModel.createDefault())
}
