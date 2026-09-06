//
//  DroneManager.swift
//  DronePass
//
//  Created by Claude on 2025-09-30.
//

// 역할: 드론 관리 핵심 로직
// 연관기능: 드론 CRUD, 색상 관리, Firebase 동기화, 기본 드론 설정

import Foundation
import Combine

// MARK: - Enums

/// 드론 삭제 시 연결된 도형 처리 방법
public enum ShapeHandlingOption {
    case reassignToDrone(String)  // 특정 드론에 재연결 (드론 ID)
    case deleteAll                 // 모두 삭제
}

/// 드론 관련 에러
public enum DroneError: LocalizedError {
    case cannotDeleteLastDrone
    case targetDroneNotFound
    case noDroneAvailable
    case saveFailed(underlying: Error)
    case loadFailed(underlying: Error)
    case duplicateName

    public var errorDescription: String? {
        switch self {
        case .cannotDeleteLastDrone:
            return "마지막 드론은 삭제할 수 없습니다."
        case .targetDroneNotFound:
            return "대상 드론을 찾을 수 없습니다."
        case .noDroneAvailable:
            return "사용 가능한 드론이 없습니다."
        case .saveFailed(let error):
            return "드론 저장 실패: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "드론 불러오기 실패: \(error.localizedDescription)"
        case .duplicateName:
            return "동일한 이름의 드론이 이미 존재합니다."
        }
    }
}

// MARK: - DroneManager

@MainActor
public final class DroneManager: ObservableObject {
    public static let shared = DroneManager()

    // MARK: - Published Properties
    @Published public var drones: [DroneModel] = []
    @Published public var selectedDroneId: String? = nil
    @Published public var selectedDroneIds: Set<String> = []
    @Published public var highlightedDroneIds: Set<String> = []
    @Published public var hasCompletedInitialLoad = false  // 초기 로드 완료 플래그
    @Published public var lastError: DroneError? = nil  // 마지막 발생 에러

    // MARK: - Private Properties
    private let repository = DroneRepository.shared
    private let selectedDroneKey = "selectedDroneId"
    private let selectedDroneIdsKey = "selectedDroneIds"
    private let highlightedDroneIdsKey = "highlightedDroneIds"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// 활성 드론들 (삭제되지 않은, 이름 가나다순 정렬)
    public var activeDrones: [DroneModel] {
        return drones.filter { !$0.isDeleted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 현재 선택된 드론
    public var selectedDrone: DroneModel? {
        guard let selectedId = selectedDroneId else { return nil }
        return activeDrones.first { $0.id == selectedId }
    }


    /// 선택된 드론들 (체크박스 방식, 이름 가나다순 정렬)
    public var selectedDrones: [DroneModel] {
        return activeDrones.filter { selectedDroneIds.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 선택된 드론 이름들을 문자열로 반환
    public var selectedDroneNamesText: String {
        let names = selectedDrones.map { $0.name }
        if names.isEmpty {
            return "드론 선택"
        } else if names.count == 1 {
            return names.first!
        } else if names.count <= 2 {
            return names.joined(separator: ", ")
        } else {
            return "\(names.count)개 드론 선택"
        }
    }

    // MARK: - Initialization

    private init() {
        // 1. 기본 드론을 즉시 생성 (비동기 로딩 전)
        // 앱 시작 즉시 최소 1개의 드론이 있도록 보장
        let defaultDrone = DroneModel.createDefault()
        drones = [defaultDrone]
        selectedDroneId = defaultDrone.id
        selectedDroneIds = Set([defaultDrone.id])

        // 주의: 임시 드론 상태를 UserDefaults에 저장하지 않음!
        // 실제 드론 로드 후 loadSelectedDrones()에서 이전 선택 상태가 복원됨

        print("🚁 임시 기본 드론 즉시 생성 및 선택: \(defaultDrone.name)")

        // 2. 비동기 초기화 순서 보장 (실제 데이터로 교체)
        Task {
            await loadDrones()
            await MainActor.run {
                loadSelectedDrones()  // 먼저 저장된 선택 복원
                setupInitialDroneIfNeeded()  // 그 다음 초기 드론 설정
            }

            // 레거시 도형 자동 마이그레이션 (1회만 실행)
            await migrateLegacyShapesIfNeeded()
        }
        setupRepositoryObserver()
    }

    // MARK: - Core CRUD Operations

    /// 새 드론 추가
    public func addDrone(name: String, color: PaletteColor) -> DroneModel {
        let isFirstDrone = activeDrones.isEmpty

        let newDrone = DroneModel(
            name: name,
            color: color.rawValue
        )

        drones.append(newDrone)

        // Repository에 저장 (비동기, 에러 시 lastError 설정)
        Task {
            do {
                try await repository.saveDrone(newDrone)
            } catch {
                self.lastError = .saveFailed(underlying: error)
                print("❌ 드론 추가 저장 실패: \(error)")
            }
        }

        // 첫 번째 드론이면 자동으로 선택
        if isFirstDrone {
            selectDrone(newDrone.id)
        }

        // 새 드론을 체크박스 선택에 자동으로 추가
        selectedDroneIds.insert(newDrone.id)
        saveSelectedDrones()

        // 지도 업데이트 알림 (드론 필터 변경)
        NotificationCenter.default.post(name: .droneFilterChanged, object: nil)

        print("🚁 새 드론 추가: \(name) (\(color.rawValue))")
        return newDrone
    }

    /// 새 드론 추가 (async throws 버전 - 저장 완료까지 대기)
    public func addDroneAsync(name: String, color: PaletteColor) async throws -> DroneModel {
        let isFirstDrone = activeDrones.isEmpty

        let newDrone = DroneModel(
            name: name,
            color: color.rawValue
        )

        drones.append(newDrone)

        // Repository에 저장 (에러 시 롤백)
        do {
            try await repository.saveDrone(newDrone)
        } catch {
            // 롤백: 메모리에서 제거
            drones.removeAll { $0.id == newDrone.id }
            self.lastError = .saveFailed(underlying: error)
            throw DroneError.saveFailed(underlying: error)
        }

        // 첫 번째 드론이면 자동으로 선택
        if isFirstDrone {
            selectDrone(newDrone.id)
        }

        // 새 드론을 체크박스 선택에 자동으로 추가
        selectedDroneIds.insert(newDrone.id)
        saveSelectedDrones()

        // 지도 업데이트 알림 (드론 필터 변경)
        NotificationCenter.default.post(name: .droneFilterChanged, object: nil)

        print("🚁 새 드론 추가 완료: \(name) (\(color.rawValue))")
        return newDrone
    }

    /// 드론 정보 업데이트
    public func updateDrone(id: String, name: String? = nil, color: String? = nil, serialNumber: String? = nil, takeoffWeight: String? = nil, size: String? = nil, memo: String? = nil) {
        guard let index = drones.firstIndex(where: { $0.id == id }) else { return }

        drones[index].update(name: name, color: color, serialNumber: serialNumber, takeoffWeight: takeoffWeight, size: size, memo: memo)

        // Repository에 저장 (비동기, 에러 시 lastError 설정)
        Task {
            do {
                try await repository.saveDrone(drones[index])
            } catch {
                self.lastError = .saveFailed(underlying: error)
                print("❌ 드론 업데이트 저장 실패: \(error)")
            }
        }

        print("🚁 드론 업데이트: \(drones[index].name)")

        // 색상 변경 알림 (지도 리로드용)
        if color != nil {
            NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
        }
    }

    /// 드론 정보 업데이트 (async throws 버전 - 저장 완료까지 대기)
    public func updateDroneAsync(id: String, name: String? = nil, color: String? = nil, serialNumber: String? = nil, takeoffWeight: String? = nil, size: String? = nil, memo: String? = nil) async throws {
        guard let index = drones.firstIndex(where: { $0.id == id }) else { return }

        // 롤백용 백업
        let backup = drones[index]

        drones[index].update(name: name, color: color, serialNumber: serialNumber, takeoffWeight: takeoffWeight, size: size, memo: memo)

        // Repository에 저장 (에러 시 롤백)
        do {
            try await repository.saveDrone(drones[index])
        } catch {
            // 롤백
            drones[index] = backup
            self.lastError = .saveFailed(underlying: error)
            throw DroneError.saveFailed(underlying: error)
        }

        print("🚁 드론 업데이트 완료: \(drones[index].name)")

        // 색상 변경 알림 (지도 리로드용)
        if color != nil {
            NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
        }
    }

    /// 드론 삭제 (소프트 삭제)
    /// - Parameters:
    ///   - id: 삭제할 드론 ID
    ///   - shapeHandling: 연결된 도형 처리 방법 (.reassignToDrone(String), .deleteAll)
    public func deleteDrone(id: String, shapeHandling: ShapeHandlingOption) async throws {
        guard let index = drones.firstIndex(where: { $0.id == id }) else { return }

        // 마지막 드론은 삭제 불가
        guard activeDrones.count > 1 else {
            throw DroneError.cannotDeleteLastDrone
        }

        // 1단계: 연결된 도형 처리
        switch shapeHandling {
        case .reassignToDrone(let targetDroneId):
            try await reassignShapesToDrone(from: id, to: targetDroneId)
        case .deleteAll:
            try await deleteAllShapes(for: id)
        }

        // 2단계: 드론 삭제 (@Published 속성은 메인 스레드에서 수정)
        let droneName = await MainActor.run { () -> String in
            drones[index].softDelete()
            return drones[index].name
        }

        try await repository.saveDrone(drones[index])

        print("🚁 드론 삭제: \(droneName)")

        // 선택된 드론 업데이트 및 알림 (메인 스레드에서 실행)
        await MainActor.run {
            if selectedDroneId == id {
                selectDrone(activeDrones.first?.id)
            }

            // 지도 및 저장 목록 새로고침
            NotificationCenter.default.post(name: .shapesDidChange, object: nil)
            NotificationCenter.default.post(name: .droneFilterChanged, object: nil)
        }
    }

    /// 드론 복원
    func restoreDrone(id: String) {
        guard let index = drones.firstIndex(where: { $0.id == id }) else { return }

        drones[index].restore()
        saveDrones()

        print("🚁 드론 복원: \(drones[index].name)")
    }

    // MARK: - Selection Management

    /// 드론 선택
    public func selectDrone(_ droneId: String?) {
        selectedDroneId = droneId
        UserDefaults.standard.set(droneId, forKey: selectedDroneKey)

        if let droneId = droneId, let drone = getDrone(by: droneId) {
            print("🎯 드론 선택: \(drone.name)")
        }

        // 선택 변경 알림 (지도 필터링용)
        NotificationCenter.default.post(name: .droneSelectionChanged, object: droneId)
    }

    /// 다음 드론으로 선택 변경
    func selectNextDrone() {
        let activeDrones = self.activeDrones
        guard activeDrones.count > 1 else { return }

        if let currentId = selectedDroneId,
           let currentIndex = activeDrones.firstIndex(where: { $0.id == currentId }) {
            let nextIndex = (currentIndex + 1) % activeDrones.count
            selectDrone(activeDrones[nextIndex].id)
        } else {
            selectDrone(activeDrones.first?.id)
        }
    }

    // MARK: - Checkbox Selection Methods

    /// 드론 선택/해제 토글 (체크박스 방식)
    public func toggleDroneSelection(_ droneId: String) {
        if selectedDroneIds.contains(droneId) {
            selectedDroneIds.remove(droneId)
        } else {
            selectedDroneIds.insert(droneId)
        }

        // 선택 상태 저장
        saveSelectedDrones()

        // 지도 업데이트 알림
        NotificationCenter.default.post(name: .droneFilterChanged, object: nil)
        print("🎯 드론 선택 변경: \(selectedDroneNamesText)")
    }

    /// 특정 드론이 선택되었는지 확인
    public func isSelectedDrone(_ droneId: String) -> Bool {
        return selectedDroneIds.contains(droneId)
    }

    /// 모든 드론 선택
    public func selectAllDrones() {
        selectedDroneIds = Set(activeDrones.map { $0.id })
        saveSelectedDrones()
        NotificationCenter.default.post(name: .droneFilterChanged, object: nil)
        print("🎯 모든 드론 선택: \(selectedDroneNamesText)")
    }

    /// 모든 드론 선택 해제
    public func deselectAllDrones() {
        selectedDroneIds.removeAll()
        saveSelectedDrones()
        NotificationCenter.default.post(name: .droneFilterChanged, object: nil)
        print("🎯 모든 드론 선택 해제")
    }

    // MARK: - Highlight Methods

    /// 드론 버튼 강조 토글
    public func toggleDroneHighlight(_ droneId: String) {
        if highlightedDroneIds.contains(droneId) {
            highlightedDroneIds.remove(droneId)
            print("🎨 드론 강조 해제: \(getDrone(by: droneId)?.name ?? droneId)")
        } else {
            highlightedDroneIds.insert(droneId)
            print("🎨 드론 강조 설정: \(getDrone(by: droneId)?.name ?? droneId)")
        }

        NotificationCenter.default.post(name: .droneHighlightChanged, object: nil)
    }

    /// 드론이 강조 상태인지 확인
    public func isHighlightedDrone(_ droneId: String) -> Bool {
        return highlightedDroneIds.contains(droneId)
    }

    // MARK: - Helper Methods

    /// ID로 드론 찾기
    public func getDrone(by id: String, includeDeleted: Bool = false) -> DroneModel? {
        if includeDeleted {
            return drones.first { $0.id == id }
        } else {
            return activeDrones.first { $0.id == id }
        }
    }

    /// 드론 이름 중복 체크
    func isDuplicateName(_ name: String, excludingId: String? = nil) -> Bool {
        return activeDrones.contains { drone in
            drone.name.lowercased() == name.lowercased() && drone.id != excludingId
        }
    }

    // MARK: - Shape Management

    /// 특정 드론에 연결된 도형 개수 반환
    public func getShapeCount(for droneId: String) -> Int {
        let shapes = ShapeFileStore.shared.shapes
        return shapes.filter { $0.droneId == droneId }.count
    }

    /// 특정 드론에 연결된 도형 목록 반환
    public func getShapes(for droneId: String) -> [ShapeModel] {
        return ShapeFileStore.shared.shapes.filter { $0.droneId == droneId }
    }

    /// 특정 드론의 모든 도형을 다른 드론에 재연결
    public func reassignShapesToDrone(from sourceDroneId: String, to targetDroneId: String) async throws {
        let shapes = getShapes(for: sourceDroneId)

        // 도형이 없으면 처리할 게 없으므로 조기 리턴
        guard !shapes.isEmpty else {
            print("🔄 재연결할 도형이 없습니다")
            return
        }

        // 대상 드론 존재 확인
        guard getDrone(by: targetDroneId) != nil else {
            throw DroneError.targetDroneNotFound
        }

        let repository = ShapeRepository.shared

        for var shape in shapes {
            shape.connectToDrone(targetDroneId)
            try await repository.updateShape(shape)
        }

        print("🔄 \(shapes.count)개 도형을 '\(getDrone(by: targetDroneId)?.name ?? "Unknown")' 드론으로 재연결")
    }

    /// 특정 드론의 모든 도형 삭제
    public func deleteAllShapes(for droneId: String) async throws {
        let shapes = getShapes(for: droneId)

        // 도형이 없으면 처리할 게 없으므로 조기 리턴
        guard !shapes.isEmpty else {
            print("🗑️ 삭제할 도형이 없습니다")
            return
        }

        let repository = ShapeRepository.shared

        for shape in shapes {
            try await repository.removeShape(id: shape.id)
        }

        print("🗑️ \(shapes.count)개 도형 삭제 완료")
    }

    /// 레거시 도형들을 첫 번째 드론에 명시적으로 연결
    public func migrateLegacyShapes() async throws {
        guard let firstDroneId = activeDrones.first?.id else {
            throw DroneError.noDroneAvailable
        }

        let shapes = ShapeFileStore.shared.shapes
        let legacyShapes = shapes.filter { $0.droneId == nil }

        guard !legacyShapes.isEmpty else {
            print("📦 마이그레이션할 레거시 도형이 없습니다")
            return
        }

        let repository = ShapeRepository.shared

        for var shape in legacyShapes {
            shape.connectToDrone(firstDroneId)
            try await repository.updateShape(shape)
        }

        print("📦 \(legacyShapes.count)개 레거시 도형을 '\(activeDrones.first?.name ?? "Unknown")' 드론에 연결 완료")
    }

    /// 사용 가능한 다음 색상 추천 (회색 제외)
    public func suggestedNextColor() -> PaletteColor {
        let usedColors = Set(activeDrones.compactMap { $0.paletteColor })
        // 회색을 제외한 사용 가능한 색상 필터링
        let availableColors = PaletteColor.allCases.filter { $0 != .gray && !usedColors.contains($0) }
        // 모든 색상이 사용된 경우에도 회색 제외한 색상 중에서 랜덤 선택
        return availableColors.first ?? PaletteColor.allCases.filter { $0 != .gray }.randomElement() ?? .blue
    }


    // MARK: - Data Persistence & Sync

    private func loadDrones() async {
        do {
            let loadedDrones = try await repository.loadDrones()
            await MainActor.run {
                self.drones = loadedDrones
                print("📁 드론 데이터 로드 완료 (\(self.activeDrones.count)개)")
            }
        } catch {
            print("❌ 드론 데이터 로드 실패: \(error)")
        }
    }

    /// 계정 전환 시 호출: 이전 계정의 로컬 드론을 비우고 새 계정의 Firebase 드론을 로드한다.
    /// (Firebase 데이터는 건드리지 않는다. `repository.loadDrones()`가 Firebase 우선으로 로컬을 전체 교체.)
    public func reloadForAccountSwitch() async {
        print("🚁 계정 전환 → 드론 초기화 및 새 계정 드론 로드")

        // 1. 메모리/선택 상태 초기화 (이전 계정 드론 제거)
        await MainActor.run {
            self.drones = []
            self.selectedDroneId = nil
            self.selectedDroneIds = []
        }

        // 2. 로컬 드론 저장소 비우기 (이전 계정 드론이 머지/잔존하지 않도록)
        try? await DroneLocalStore.shared.saveAll([])

        // 3. 새 계정의 Firebase 드론 로드 (Firebase 우선 → 로컬 + self.drones 갱신)
        await loadDrones()

        // 4. 새 계정에 드론이 없으면 기본 드론 생성 + 전체 선택
        setupInitialDroneIfNeeded()
    }

    private func setupRepositoryObserver() {
        // Repository 동기화 변경 감지
        NotificationCenter.default.addObserver(
            forName: .dronesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let updatedDrones = notification.object as? [DroneModel] {
                self?.drones = updatedDrones
                print("🔄 드론 실시간 동기화: \(updatedDrones.count)개 (활성)")
            }
        }
    }

    private func loadSelectedDrones() {
        // 단일 드론 선택 복원
        selectedDroneId = UserDefaults.standard.string(forKey: selectedDroneKey)

        // 선택된 드론이 없거나 유효하지 않으면 첫 번째 드론 선택
        if selectedDroneId == nil || getDrone(by: selectedDroneId!) == nil {
            selectDrone(activeDrones.first?.id)
        }

        // 다중 드론 선택 복원
        if let savedIds = UserDefaults.standard.array(forKey: selectedDroneIdsKey) as? [String] {
            selectedDroneIds = Set(savedIds)
            print("💾 저장된 드론 선택 복원: \(selectedDroneNamesText)")
        }
    }

    private func saveSelectedDrones() {
        let idsArray = Array(selectedDroneIds)
        UserDefaults.standard.set(idsArray, forKey: selectedDroneIdsKey)
    }

    private func saveHighlightedDrones() {
        let idsArray = Array(highlightedDroneIds)
        UserDefaults.standard.set(idsArray, forKey: highlightedDroneIdsKey)
    }

    /// 모든 드론 상태 저장 (앱 종료 시 호출)
    public func saveAllStates() {
        saveSelectedDrones()
        print("💾 드론 선택 상태 저장 완료")
    }

    private func setupInitialDroneIfNeeded() {
        // loadDrones() 완료 후 실행되므로 activeDrones는 정확한 상태
        if activeDrones.isEmpty {
            // 실제로 드론이 없을 때만 초기 드론 생성
            let initialDrone = DroneModel.createDefault()
            drones.append(initialDrone)

            // Repository에 저장
            Task {
                do {
                    try await repository.saveDrone(initialDrone)
                    print("🚁 초기 드론 생성 및 저장: \(initialDrone.name)")
                } catch {
                    print("❌ 초기 드론 저장 실패: \(error)")
                }
            }

            selectDrone(initialDrone.id)

            // ✅ 체크박스 선택에도 즉시 추가 (버전 업데이트 시 도형이 바로 보이도록)
            selectedDroneIds.insert(initialDrone.id)
            saveSelectedDrones()
            NotificationCenter.default.post(name: .droneFilterChanged, object: nil)
            print("✅ 초기 드론 자동 체크 완료")
        }

        // 초기화 시 모든 드론 선택 (체크박스 방식)
        if selectedDroneIds.isEmpty && !activeDrones.isEmpty {
            selectedDroneIds = Set(activeDrones.map { $0.id })
            saveSelectedDrones()  // 선택 상태 저장
            print("🎯 초기화: 모든 드론 선택 (\(selectedDroneNamesText))")

            // 지도 업데이트 알림 발송
            NotificationCenter.default.post(name: .droneFilterChanged, object: nil)
        }

        // 초기 로드 완료 플래그 설정
        hasCompletedInitialLoad = true
        print("✅ DroneManager 초기 로드 완료")

        // 초기 로드 완료 알림 발송 (MapViewModel이 오버레이 생성 시작)
        NotificationCenter.default.post(name: Notification.Name("DroneInitialLoadCompleted"), object: nil)

        // 초기 로드 완료 후 지도 업데이트 알림 (타이밍 이슈 해결)
        NotificationCenter.default.post(name: .droneFilterChanged, object: nil)

        // 오버레이 색상 업데이트 알림 (드론 색상이 올바르게 표시되도록)
        NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
    }

    /// 레거시 도형 마이그레이션이 필요한지 확인하고 실행
    private func migrateLegacyShapesIfNeeded() async {
        // 플래그 체크 대신, 실제로 droneId 없는 도형이 있는지 확인
        let shapes = ShapeFileStore.shared.shapes
        let legacyShapes = shapes.filter { $0.droneId == nil }

        guard !legacyShapes.isEmpty else {
            print("📦 마이그레이션할 레거시 도형 없음")
            return
        }

        print("📦 droneId 없는 도형 \(legacyShapes.count)개 발견 - 마이그레이션 시작")

        do {
            try await migrateLegacyShapes()
            print("✅ 레거시 도형 마이그레이션 완료")
        } catch {
            print("❌ 레거시 도형 마이그레이션 실패: \(error)")
        }
    }

    // MARK: - Migration Support

    /// 기존 색상 시스템에서 드론 시스템으로 마이그레이션
    func migrateFromColorSystem() {
        // ColorManager에서 현재 기본 색상 가져오기
        let currentColor = ColorManager.shared.defaultColor

        // 첫 번째 드론이 현재 색상과 다르면 업데이트
        if let firstDrone = activeDrones.first, firstDrone.color != currentColor.rawValue {
            updateDrone(id: firstDrone.id, color: currentColor.rawValue)
            print("🔄 색상 시스템에서 마이그레이션: \(currentColor.rawValue)")
        }
    }

    // MARK: - Internal Save Method

    private func saveDrones() {
        // Repository를 통해 모든 드론 저장
        Task {
            do {
                for drone in drones {
                    try await repository.saveDrone(drone)
                }
            } catch {
                print("❌ 드론 일괄 저장 실패: \(error)")
            }
        }
    }
}