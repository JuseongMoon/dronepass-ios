//
//  ShapeEditViewModel.swift
//  DronePass
//
//  Created by 문주성 on 7/22/25.
//

import Foundation
import Combine
import SwiftUI

struct ShapeCreationDateRange: Equatable {
    let startDate: Date
    let endDate: Date
}

func normalizedShapeCreationDateRange(
    startDate: Date,
    endDate: Date,
    isDateOnly: Bool,
    now: Date,
    calendar: Calendar = .current,
    fallbackDuration: TimeInterval = 60 * 60
) -> ShapeCreationDateRange {
    if isDateOnly {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let endOfDay: (Date) -> Date = { date in
            let startOfDay = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)?
                .addingTimeInterval(-1) ?? date
        }
        let normalizedStartDayEnd = endOfDay(startDate)
        let normalizedEndDate = endOfDay(endDate)

        if normalizedStartDayEnd < now && normalizedEndDate < now {
            let todayStart = calendar.startOfDay(for: now)
            return ShapeCreationDateRange(
                startDate: todayStart,
                endDate: endOfDay(now)
            )
        }

        return ShapeCreationDateRange(
            startDate: normalizedStartDate,
            endDate: max(normalizedEndDate, normalizedStartDayEnd)
        )
    }

    guard endDate <= now || endDate < startDate else {
        return ShapeCreationDateRange(startDate: startDate, endDate: endDate)
    }

    let fallbackEndDate = now.addingTimeInterval(fallbackDuration)
    return ShapeCreationDateRange(
        startDate: startDate,
        endDate: max(startDate, fallbackEndDate)
    )
}

@MainActor
final class ShapeEditViewModel: ObservableObject {
    // 입력값 상태
    @Published var title: String = ""
    @Published var address: String = ""
    @Published var radius: String = ""
    @Published var height: String = ""
    @Published var memo: String = ""
    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()
    @Published var isDateOnly: Bool = false
    @Published var coordinateText: String = ""
    @Published var coordinate: CoordinateManager?
    @Published var selectedDroneId: String? = nil
    @Published var showingAlert: Bool = false
    @Published var alertMessage: String = ""

    // 초기값 추적
    private var initialTitle: String = ""
    private var initialAddress: String = ""
    private var initialRadius: String = ""
    private var initialHeight: String = ""
    private var initialMemo: String = ""
    private var initialCoordinate: CoordinateManager?
    private var initialSelectedDroneId: String? = nil

    // 외부 의존성
    private let store = ShapeRepository.shared
    var onAdd: ((ShapeModel) -> Void)?
    var originalShape: ShapeModel?

    // 복제 모드 플래그
    var isDuplicateMode: Bool = false

    // 편집 충돌 해결을 위한 실시간 관찰자 (편집 모드에서만 사용)
    private var shapeObserver: ShapeRealtimeObserver?

    // UserDefaults 키
    private let dateOnlyKey = "isDateOnlyMode"
    private let lastStartDateKey = "lastStartDate"
    private let lastEndDateKey = "lastEndDate"
    private let lastSelectedDroneIdKey = "lastSelectedDroneId"
    private let lastRadiusKey = "lastRadius"
    private let lastHeightKey = "lastHeight"

    private var isCreationOperation: Bool {
        (originalShape?.title.isEmpty ?? true) || isDuplicateMode
    }

    // MARK: - 초기화
    init(coordinate: CoordinateManager?, onAdd: ((ShapeModel) -> Void)? = nil, originalShape: ShapeModel? = nil, isDuplicateMode: Bool = false) {
        self.coordinate = coordinate
        self.onAdd = onAdd
        self.originalShape = originalShape
        self.isDuplicateMode = isDuplicateMode
        if let shape = originalShape {
            self.title = shape.title
            self.address = shape.address ?? ""
            self.radius = shape.radius != nil ? String(format: "%.0f", shape.radius!) : ""
            self.height = shape.height != nil ? String(format: "%.0f", shape.height!) : ""
            self.memo = shape.memo ?? ""
            self.startDate = shape.flightStartDate
            self.endDate = shape.flightEndDate ?? Date()
            self.coordinateText = coordinate?.formattedCoordinate ?? ""
            self.initialTitle = shape.title
            self.initialAddress = shape.address ?? ""
            self.initialRadius = shape.radius != nil ? String(format: "%.0f", shape.radius!) : ""
            self.initialHeight = shape.height != nil ? String(format: "%.0f", shape.height!) : ""
            self.initialMemo = shape.memo ?? ""
            self.initialCoordinate = coordinate
        } else {
            self.coordinateText = coordinate?.formattedCoordinate ?? ""
            self.initialCoordinate = coordinate
        }
        let isOriginalShapeTitleEmpty: Bool = (originalShape?.title.isEmpty ?? false)
        if isOriginalShapeTitleEmpty {
            self.address = originalShape?.address ?? ""
            self.initialAddress = originalShape?.address ?? ""
        }
        
        // 편집 모드인 경우 실시간 관찰자 설정 (복제 모드는 제외)
        if let shape = originalShape, !isDuplicateMode {
            self.shapeObserver = ShapeRealtimeObserver(shape: shape)
            self.shapeObserver?.startEditing()
        }
    }

    // MARK: - 비즈니스 로직
    func setupInitialValues() {
        isDateOnly = UserDefaults.standard.bool(forKey: dateOnlyKey)

        if let shape = originalShape, !shape.title.isEmpty {
            // 기존 도형 편집: 도형에 연결된 드론 ID 사용
            selectedDroneId = shape.droneId

            // 하이브리드 호환성: droneId가 없으면 첫 번째 드론 사용
            if selectedDroneId == nil {
                selectedDroneId = DroneManager.shared.activeDrones.first?.id
            }
        } else {
            // 새 도형 생성: 이전 설정값 불러오기

            // 1. 드론: 저장된 드론 ID → 현재 선택된 드론 → 첫 번째 드론 순서로 선택
            if let lastDroneId = UserDefaults.standard.string(forKey: lastSelectedDroneIdKey),
               DroneManager.shared.getDrone(by: lastDroneId) != nil {
                selectedDroneId = lastDroneId
            } else {
                selectedDroneId = DroneManager.shared.selectedDroneId ?? DroneManager.shared.activeDrones.first?.id
            }

            // 2. 반경: 저장된 값 불러오기
            if let lastRadius = UserDefaults.standard.string(forKey: lastRadiusKey), !lastRadius.isEmpty {
                radius = lastRadius
            }

            // 3. 고도: 저장된 값 불러오기
            if let lastHeight = UserDefaults.standard.string(forKey: lastHeightKey), !lastHeight.isEmpty {
                height = lastHeight
            }

            // 4. 시작일: 저장된 값 불러오기
            if let lastStart = UserDefaults.standard.object(forKey: lastStartDateKey) as? Date {
                startDate = lastStart
            } else {
                startDate = Date()
            }

            // 5. 종료일: 저장된 값 불러오기
            if let lastEnd = UserDefaults.standard.object(forKey: lastEndDateKey) as? Date {
                endDate = lastEnd
            } else {
                endDate = Date()
            }
        }

        if let coord = coordinate {
            self.coordinateText = coord.formattedCoordinate
        }

        normalizeCreationDates()

        // 초기값 저장
        initialSelectedDroneId = selectedDroneId

        print("🚁 ShapeEditViewModel: 드론 선택 초기화 - \(selectedDroneId ?? "nil")")
    }

    func updateDates() {
        if isDateOnly {
            let calendar = Calendar.current
            var startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
            startComponents.hour = 0
            startComponents.minute = 0
            if let newStart = calendar.date(from: startComponents) {
                startDate = newStart
            }
            var endComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
            endComponents.hour = 23
            endComponents.minute = 59
            if let newEnd = calendar.date(from: endComponents) {
                endDate = newEnd
            }
        }

        normalizeCreationDates()
    }

    func hasChanges() -> Bool {
        return title != initialTitle ||
               address != initialAddress ||
               radius != initialRadius ||
               height != initialHeight ||
               memo != initialMemo ||
               coordinate != initialCoordinate ||
               selectedDroneId != initialSelectedDroneId
    }

    func saveShape(onComplete: @escaping () -> Void) {
        normalizeCreationDates()

        if coordinate == nil && address.isEmpty {
            alertMessage = String(localized: "shape.edit.error.coordinateRequired")
            showingAlert = true
            return
        }
        if radius.isEmpty {
            alertMessage = String(localized: "shape.edit.error.radiusRequired")
            showingAlert = true
            return
        }
        let addressToSave = address.isEmpty ? String(localized: "shape.edit.error.noAddress") : address
        guard let finalCoordinate = coordinate else {
            alertMessage = String(localized: "shape.edit.error.noCoordinate")
            showingAlert = true
            return
        }
        // 선택된 드론의 색상 사용 (하이브리드 호환성을 위해 color 필드도 설정)
        let selectedColor = selectedDroneId != nil ?
            DroneManager.shared.getDrone(by: selectedDroneId!)?.color ?? ColorManager.shared.defaultColor.rawValue :
            ColorManager.shared.defaultColor.rawValue

        let defaultTitle = NSLocalizedString("shape.edit.defaultTitle", comment: "New Shape")
        print("💾 도형 저장 시작:")
        print("  - 제목: \(title.isEmpty ? defaultTitle : title)")
        print("  - 드론 ID: \(selectedDroneId ?? "nil")")
        print("  - 색상: \(selectedColor)")

        let newShape = ShapeModel(
            id: isDuplicateMode ? UUID() : (originalShape?.id ?? UUID()),
            title: title.isEmpty ? defaultTitle : title,
            shapeType: .circle,
            baseCoordinate: finalCoordinate,
            radius: Double(radius) ?? 0,
            height: height.isEmpty ? nil : Double(height),
            memo: memo.isEmpty ? nil : memo,
            address: addressToSave,
            createdAt: isDuplicateMode ? Date() : (originalShape?.createdAt ?? Date()),
            deletedAt: originalShape?.deletedAt,
            flightStartDate: startDate,
            flightEndDate: endDate,
            color: selectedColor,
            droneId: selectedDroneId
        )

        // 다음 도형 생성을 위해 현재 설정값 저장
        UserDefaults.standard.set(selectedDroneId, forKey: lastSelectedDroneIdKey)
        UserDefaults.standard.set(radius, forKey: lastRadiusKey)
        UserDefaults.standard.set(height, forKey: lastHeightKey)
        UserDefaults.standard.set(startDate, forKey: lastStartDateKey)
        UserDefaults.standard.set(endDate, forKey: lastEndDateKey)
        if isCreationOperation {
            Task {
                do {
                    try await store.addShape(newShape)
                    await MainActor.run {
                        onAdd?(newShape)

                        // 새 도형 생성 시 저장탭 열기 + 자동 스크롤
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenSavedTabNotification"),
                            object: newShape.id
                        )

                        // 지도에서 도형 선택 및 이동
                        let moveData = SavedTableListView.MoveToShapeData(
                            coordinate: newShape.baseCoordinate,
                            radius: newShape.radius ?? 100.0,
                            shapeID: newShape.id
                        )
                        NotificationCenter.default.post(
                            name: SavedTableListView.moveToShapeNotification,
                            object: moveData
                        )

                        onComplete()
                    }
                } catch {
                    await MainActor.run {
                        alertMessage = "도형 추가 중 오류가 발생했습니다: \(error.localizedDescription)"
                        showingAlert = true
                    }
                }
            }
        } else {
            // 편집 모드 - 충돌 해결 후 저장
            Task {
                do {
                    let finalShape: ShapeModel
                    
                    // 편집 충돌 해결
                    if let observer = shapeObserver {
                        // 편집한 필드들을 관찰자에게 알림
                        trackEditedFields(observer: observer)
                        
                        // 충돌 해결 후 최종 도형 생성
                        finalShape = try await observer.resolveConflictsAndSave(editedShape: newShape)
                        
                        // 편집 모드 종료
                        observer.stopEditing()
                    } else {
                        finalShape = newShape
                    }
                    
                    // 최종 도형 저장
                    try await store.updateShape(finalShape)
                    
                    await MainActor.run {
                        onAdd?(finalShape)
                        onComplete()
                    }
                } catch {
                    await MainActor.run {
                        alertMessage = "도형 수정 중 오류가 발생했습니다: \(error.localizedDescription)"
                        showingAlert = true
                    }
                }
            }
        }
    }

    private func normalizeCreationDates(now: Date = Date()) {
        guard isCreationOperation else { return }

        let normalizedDates = normalizedShapeCreationDateRange(
            startDate: startDate,
            endDate: endDate,
            isDateOnly: isDateOnly,
            now: now
        )
        startDate = normalizedDates.startDate
        endDate = normalizedDates.endDate
    }
    
    /// 편집한 필드들을 추적하여 관찰자에게 알림
    private func trackEditedFields(observer: ShapeRealtimeObserver) {
        // 각 필드가 초기값과 다른지 확인하여 편집된 필드 추적
        if title != initialTitle {
            observer.finishEditingField("title")
        }

        if address != initialAddress {
            observer.finishEditingField("address")
        }

        if radius != initialRadius {
            observer.finishEditingField("radius")
        }

        if height != initialHeight {
            observer.finishEditingField("height")
        }

        if memo != initialMemo {
            observer.finishEditingField("memo")
        }

        if let currentCoord = coordinate, let initialCoord = initialCoordinate {
            if currentCoord.latitude != initialCoord.latitude || currentCoord.longitude != initialCoord.longitude {
                observer.finishEditingField("coordinates")
            }
        } else if coordinate != initialCoordinate {
            observer.finishEditingField("coordinates")
        }

        // 날짜 필드들 (원본 데이터와 비교)
        if let originalShape = originalShape {
            if startDate != originalShape.flightStartDate {
                observer.finishEditingField("flightStartDate")
            }

            if endDate != (originalShape.flightEndDate ?? Date()) {
                observer.finishEditingField("flightEndDate")
            }
        }

        // 드론 ID 변경 추적
        if selectedDroneId != initialSelectedDroneId {
            observer.finishEditingField("droneId")
            print("🚁 드론 변경 감지: \(initialSelectedDroneId ?? "nil") → \(selectedDroneId ?? "nil")")
        }
    }
    
    deinit {
        // 뷰모델이 해제될 때 편집 모드 종료
        // deinit은 nonisolated이므로 Task로 MainActor에서 실행
        let observer = shapeObserver
        Task { @MainActor in
            observer?.stopEditing()
        }
    }
}
