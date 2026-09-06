//
//  ShapeEditView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//

import SwiftUI
import CoreLocation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// 동적으로 높이가 변하는 TextEditor
struct GrowingTextEditor: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var minHeight: CGFloat = 40
    var maxHeight: CGFloat = 300
    

    @State private var dynamicHeight: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($isFocused)
//                .frame(height: dynamicHeight)
//                .background(Color(UIColor.secondarySystemBackground))
//                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(UIColor.systemGray3))
                )
                .onChange(of: text) { recalculateHeight() }
                .onAppear {
                    recalculateHeight()
                }

            if text.isEmpty {
                Text(NSLocalizedString("shape.edit.memo.placeholder", comment: "Enter memo"))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
    }

    private func recalculateHeight() {
        let size = CGSize(width: 250, height: CGFloat.infinity) // 고정 폭 사용
        let attributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .body)]
        let estimatedHeight = NSString(string: text.isEmpty ? " " : text)
            .boundingRect(with: size, options: .usesLineFragmentOrigin, attributes: attributes, context: nil).height
        dynamicHeight = min(max(estimatedHeight + 28, minHeight), maxHeight)
    }
}

// 동적으로 높이가 변하는 AddressField
struct AddressField: View {
    let text: String
    let placeholder: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.gray)
                        .padding(.vertical, 8)
                } else {
                    Text(text)
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .background(Color(UIColor.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(UIColor.systemGray3))
            )
        }
        .buttonStyle(.plain)
    }
}

// 기본 정보 섹션
struct BasicInfoSection: View {
    @Binding var title: String
    @Binding var coordinateText: String
    @Binding var address: String
    @Binding var radius: String
    @Binding var height: String
    let onCoordinateTap: () -> Void
    let onAddressTap: () -> Void
    
    var body: some View {
        Section {
            // 제목
            HStack {
                Text(NSLocalizedString("shape.edit.title", comment: "Title"))
                    .bold()
                TextField(NSLocalizedString("shape.edit.title.placeholder", comment: "Enter title"), text: $title)
                    .multilineTextAlignment(.trailing)
            }
            .frame(height: 30)
            
            // 좌표
            Button(action: onCoordinateTap) {
                HStack {
                    Text(NSLocalizedString("shape.edit.coordinate", comment: "Coordinates"))
                        .bold()
                        .foregroundColor(.primary)
                    Spacer()
                    Text(coordinateText.isEmpty ? NSLocalizedString("shape.edit.coordinate.placeholder", comment: "Enter coordinates") : coordinateText)
                        .foregroundColor(coordinateText.isEmpty ? .gray : .primary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .frame(height: 30)
            
            // 주소
            Button(action: onAddressTap) {
                HStack {
                    Text(NSLocalizedString("shape.edit.address", comment: "Address"))
                        .bold()
                        .foregroundColor(.primary)
                    Spacer()
                    Text(address.isEmpty ? NSLocalizedString("shape.edit.address.placeholder", comment: "Search address") : address)
                        .foregroundColor(address.isEmpty ? .gray : .primary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .frame(height: 30)
            
            // 반경
            HStack {
                Text(NSLocalizedString("shape.edit.radius", comment: "Radius (m)"))
                    .bold()
                TextField(NSLocalizedString("shape.edit.radius.placeholder", comment: "Enter radius"), text: $radius)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: radius) { oldVal, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            radius = filtered
                        }
                    }
            }
            .frame(height: 30)

            // 고도 (드론 비행 고도)
            HStack {
                Text(NSLocalizedString("shape.edit.altitude", comment: "Altitude (m)"))
                    .bold()
                TextField(NSLocalizedString("shape.edit.altitude.placeholder", comment: "Enter altitude"), text: $height)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: height) { oldVal, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            height = filtered
                        }
                    }
            }
            .frame(height: 30)
        }
    }
}

// 날짜 섹션
struct DateSection: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var isDateOnly: Bool
    @Binding var showingStartDatePicker: Bool
    @Binding var showingEndDatePicker: Bool
    let isIPhone12: Bool
    let dateFormatterDateOnly: DateFormatter
    let dateFormatterDateTime: DateFormatter
    let dateOnlyKey: String
    let onDateOnlyChange: () -> Void
    
    var body: some View {
        Section {
            // 시작일
            Group {
                if isIPhone12 {
                    Button(action: { showingStartDatePicker = true }) {
                        HStack {
                            Text(NSLocalizedString("shape.edit.startDate", comment: "Start Date"))
                                .bold()
                                .foregroundColor(.primary)
                            Spacer()
                            Text(startDate, formatter: isDateOnly ? dateFormatterDateOnly : dateFormatterDateTime)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(height: 30)
                    .sheet(isPresented: $showingStartDatePicker) {
                        DateTimeSelectionView(selectedDate: $startDate, isDateOnly: isDateOnly, title: NSLocalizedString("shape.edit.startDate.select", comment: "Select Start Date"))
                    }
                    .onChange(of: startDate) { oldValue, newValue in
                        if endDate < newValue {
                            endDate = newValue
                        }
                    }
                } else {
                    DatePicker(String(localized: "shape.edit.startDate"), selection: $startDate, displayedComponents: isDateOnly ? .date : [.date, .hourAndMinute])
                        .onChange(of: startDate) { oldValue, newValue in
                            if endDate < newValue {
                                endDate = newValue
                            }
                        }
                        .frame(height: 30)
                        .bold()
                }
            }

            
            // 종료일
            Group {
                if isIPhone12 {
                    Button(action: { showingEndDatePicker = true }) {
                        HStack {
                            Text(NSLocalizedString("shape.edit.endDate", comment: "End Date"))
                                .bold()
                                .foregroundColor(.primary)
                            Spacer()
                            Text(endDate, formatter: isDateOnly ? dateFormatterDateOnly : dateFormatterDateTime)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(height: 30)
                    .sheet(isPresented: $showingEndDatePicker) {
                        DateTimeSelectionView(selectedDate: $endDate, isDateOnly: isDateOnly, title: NSLocalizedString("shape.edit.endDate.select", comment: "Select End Date"))
                    }
                } else {
                    DatePicker(String(localized: "shape.edit.endDate"), selection: $endDate, in: startDate..., displayedComponents: isDateOnly ? .date : [.date, .hourAndMinute])
                        .frame(height: 30)
                        .bold()
                }
            }

            
            // 날짜 설정
            Toggle(NSLocalizedString("shape.edit.dayMode", comment: "Day mode"), isOn: $isDateOnly)
                .onChange(of: isDateOnly) { newValue in
                    UserDefaults.standard.set(newValue, forKey: dateOnlyKey)
                    onDateOnlyChange()
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        #if canImport(UIKit)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                    }
                )
                .frame(height: 30)
                .bold()
        }
    }
}

// 드론 선택 섹션
struct DroneSelectionSection: View {
    @ObservedObject var droneManager: DroneManager
    @Binding var selectedDroneId: String?

    // 선택된 드론 객체 계산
    private var selectedDrone: DroneModel? {
        guard let selectedId = selectedDroneId else { return nil }
        return droneManager.getDrone(by: selectedId)
    }

    var body: some View {
        Section {
            HStack {
                Text(NSLocalizedString("shape.edit.drone", comment: "Select Drone"))
                    .bold()

                Spacer()

                Menu {
                    ForEach(droneManager.activeDrones) { drone in
                        Button(action: {
                            selectedDroneId = drone.id
                            print("🚁 드론 선택됨: \(drone.name)")
                        }) {
                            HStack {
                                // 드론 색상 원형 표시
                                if let color = drone.paletteColor {
                                    Circle()
                                        .fill(Color(color.uiColor))
                                        .frame(width: 12, height: 12)
                                }

                                Text(drone.name)

                                // 선택된 드론 체크마크
                                if selectedDroneId == drone.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        // 선택된 드론 색상 표시
                        if let drone = selectedDrone, let color = drone.paletteColor {
                            Circle()
                                .fill(Color(color.uiColor))
                                .frame(width: 12, height: 12)
                        } else {
                            // 기본 아이콘 (선택된 드론이 없을 때)
                            Image(systemName: "drone")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }

                        Text(selectedDrone?.name ?? NSLocalizedString("shape.edit.drone.placeholder", comment: "Select drone"))
                            .foregroundColor(selectedDrone != nil ? .primary : .secondary)

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.borderless)
            }
            .frame(height: 30)
        }
    }
}

// 메모 섹션
struct MemoSection: View {
    @Binding var memo: String
    
    var body: some View {
        Section {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("shape.edit.memo", comment: "Memo"))
                    .bold()
                TextEditor(text: $memo)
                    .frame(minHeight: 170)
                    .overlay(
                        Group {
                            if memo.isEmpty {
                                Text(NSLocalizedString("shape.edit.memo.placeholder", comment: "Enter memo"))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                            }
                        },
                        alignment: .topLeading
                    )
            }
        }
    }
}

struct ShapeEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ShapeEditViewModel
    @ObservedObject private var droneManager = DroneManager.shared
    @FocusState private var isFocused: Bool
    @State private var showingStartDatePicker = false
    @State private var showingEndDatePicker = false
    @State private var showingCoordinateInput = false
    @State private var showingAddressSearch = false
    @State private var showingCancelAlert = false
    @State private var selectedDetent: PresentationDetent = .large

    init(coordinate: CoordinateManager?, onAdd: ((ShapeModel) -> Void)? = nil, originalShape: ShapeModel? = nil, isDuplicateMode: Bool = false) {
        _viewModel = StateObject(wrappedValue: ShapeEditViewModel(coordinate: coordinate, onAdd: onAdd, originalShape: originalShape, isDuplicateMode: isDuplicateMode))
    }
    
    var body: some View {
        NavigationView {
            Form {
                DroneSelectionSection(
                    droneManager: droneManager,
                    selectedDroneId: $viewModel.selectedDroneId
                )
                BasicInfoSection(
                    title: $viewModel.title,
                    coordinateText: $viewModel.coordinateText,
                    address: $viewModel.address,
                    radius: $viewModel.radius,
                    height: $viewModel.height,
                    onCoordinateTap: { showingCoordinateInput = true },
                    onAddressTap: { showingAddressSearch = true }
                )
                DateSection(
                    startDate: $viewModel.startDate,
                    endDate: $viewModel.endDate,
                    isDateOnly: $viewModel.isDateOnly,
                    showingStartDatePicker: $showingStartDatePicker,
                    showingEndDatePicker: $showingEndDatePicker,
                    isIPhone12: false, // 기본값으로 false 설정
                    dateFormatterDateOnly: {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .none
                        return formatter
                    }(),
                    dateFormatterDateTime: {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .short
                        return formatter
                    }(),
                    dateOnlyKey: "isDateOnlyMode",
                    onDateOnlyChange: { viewModel.updateDates() }
                )
                MemoSection(memo: $viewModel.memo)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("shape.edit.navigation.cancel", comment: "Cancel")) {
                        if viewModel.hasChanges() {
                            showingCancelAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("shape.edit.navigation.save", comment: "Save")) {
                        viewModel.saveShape {
                            dismiss()
                        }
                    }
                }
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .alert(String(localized: "shape.edit.alert.unsaved.title"), isPresented: $showingCancelAlert) {
                Button(String(localized: "common.cancel"), role: .cancel) { }
                Button(String(localized: "common.close"), role: .destructive) {
                    dismiss()
                }
            } message: {
                Text(String(localized: "shape.edit.alert.unsaved.message"))
            }
            .alert(String(localized: "shape.edit.alert.error.title"), isPresented: $viewModel.showingAlert) {
                Button(String(localized: "common.confirm"), role: .cancel) { }
            } message: {
                Text(viewModel.alertMessage)
            }
            .sheet(isPresented: $showingAddressSearch) {
                SearchAddressView(
                    onSelectAddress: { address in
                        viewModel.address = address.jibunAddress
                        if let coordinate = address.coordinate {
                            viewModel.coordinate = CoordinateManager(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            viewModel.coordinateText = viewModel.coordinate?.formattedCoordinate ?? ""
                        }
                    }
                )
                .interactiveDismissDisabled()
                .presentationDragIndicator(.visible)
                .presentationDetents([.fraction(0.85)])
                .presentationContentInteraction(.scrolls)
            }
            .sheet(isPresented: $showingCoordinateInput) {
                CoordinateView(
                    onSelectCoordinate: { newCoordinate, newAddress in
                        viewModel.coordinate = newCoordinate
                        viewModel.coordinateText = newCoordinate.formattedCoordinate
                        viewModel.address = newAddress
                    }
                )
                .interactiveDismissDisabled()
                .presentationDragIndicator(.visible)
                .presentationDetents([.fraction(0.85)])
                .presentationContentInteraction(.scrolls)
            }
            .onAppear {
                viewModel.setupInitialValues()
                print("🚁 ShapeEditView 나타남: 선택된 드론 ID = \(viewModel.selectedDroneId ?? "nil")")
            }
        }
    }
}

#Preview {
    ShapeEditView(
        coordinate: CoordinateManager(latitude: 0, longitude: 0),
        onAdd: { _ in }
    )
}

