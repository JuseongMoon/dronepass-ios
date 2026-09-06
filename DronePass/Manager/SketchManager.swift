//
//  SketchManager.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 기능 총괄 매니저
// 연관기능: 스케치 모드 상태, 그리기 작업, Analytics

import Foundation
import Combine
import FirebaseAnalytics

/// Undo 가능한 액션 타입
enum UndoAction {
    case delete(sketches: [SketchModel])  // 삭제된 스케치들 (1개 또는 여러 개)
    case create(sketch: SketchModel)       // 생성된 스케치
}

/// 스케치 기능 총괄 매니저
@MainActor
final class SketchManager: ObservableObject {
    static let shared = SketchManager()

    // MARK: - 스케치 모드 상태

    /// 스케치 모드 활성화 여부
    @Published var isSketchModeActive: Bool = false

    /// 지우개 모드 활성화 여부
    @Published var isEraserModeActive: Bool = false

    /// 현재 선택된 색상 (hex)
    @Published var currentColor: String = "#FF0000"

    /// 현재 선 두께
    @Published var currentStrokeWidth: Double = 4.0

    /// 현재 투명도 (0.0 ~ 1.0)
    @Published var currentOpacity: Double = 1.0

    // MARK: - 그리기 상태

    /// 현재 그리는 중인 포인트들
    @Published var currentDrawingPoints: [CoordinateManager] = []

    /// 그리기 진행 중 여부
    @Published var isDrawing: Bool = false

    // MARK: - Undo/Redo 스택

    /// 실행된 액션들 (Undo 시 여기서 꺼냄)
    private var undoStack: [UndoAction] = []

    /// 취소된 액션들 (Redo 시 여기서 꺼냄)
    private var redoStack: [UndoAction] = []

    /// 실행취소 가능 여부
    @Published var canUndo: Bool = false

    /// 다시실행 가능 여부
    @Published var canRedo: Bool = false

    // MARK: - Private Properties

    /// 스케치 모드 진입 시간 (Analytics용)
    private var modeEnterTime: Date?

    /// 좌표 샘플링을 위한 마지막 포인트
    private var lastSampledPoint: CoordinateManager?

    /// 최소 샘플링 거리 (미터)
    private let minSamplingDistance: Double = 5.0

    /// 공간 인덱싱 (BoundingBox 기반) - 지우개 최적화용
    private var sketchBoundingBoxes: [UUID: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)] = [:]

    // MARK: - UserDefaults 키
    private let sketchColorKey = "sketchCurrentColor"
    private let sketchStrokeWidthKey = "sketchCurrentStrokeWidth"
    private let sketchOpacityKey = "sketchCurrentOpacity"

    private init() {
        loadSettings()
    }

    /// 저장된 설정값 로드
    private func loadSettings() {
        if let savedColor = UserDefaults.standard.string(forKey: sketchColorKey) {
            currentColor = savedColor
        }
        let savedWidth = UserDefaults.standard.double(forKey: sketchStrokeWidthKey)
        if savedWidth > 0 {
            currentStrokeWidth = savedWidth
        }
        let savedOpacity = UserDefaults.standard.double(forKey: sketchOpacityKey)
        if savedOpacity > 0 {
            currentOpacity = savedOpacity
        }
    }

    // MARK: - Mode Control

    /// 스케치 모드 진입
    func enterSketchMode() {
        guard !isSketchModeActive else { return }

        isSketchModeActive = true
        modeEnterTime = Date()
        currentDrawingPoints = []
        isDrawing = false

        // Undo/Redo 스택 초기화 및 상태 업데이트
        resetUndoRedoStacks()

        // 스케치 변경 추적 초기화 (새 세션 시작)
        SketchRepository.shared.resetModifiedTracking()

        // 공간 인덱스 초기화
        updateSpatialIndex()

        // Analytics 이벤트
        logSketchModeEnter()

        print("✏️ 스케치 모드 진입")
    }

    /// 스케치 모드 종료
    func exitSketchMode() {
        guard isSketchModeActive else { return }

        // 진행 중인 그리기가 있으면 저장
        if !currentDrawingPoints.isEmpty {
            finishDrawing()
        }

        isSketchModeActive = false

        // 완료 시 Firebase에 동기화
        SketchRepository.shared.syncToFirebaseOnComplete()

        // Analytics 이벤트
        if let enterTime = modeEnterTime {
            let duration = Date().timeIntervalSince(enterTime)
            logSketchModeExit(duration: duration)
        }

        modeEnterTime = nil
        currentDrawingPoints = []
        isDrawing = false

        // 공간 인덱스 정리
        sketchBoundingBoxes.removeAll()

        print("✏️ 스케치 모드 종료")
    }

    // MARK: - Drawing Operations

    /// 그리기 시작
    func startDrawing(at point: CoordinateManager) {
        currentDrawingPoints = [point]
        lastSampledPoint = point
        isDrawing = true

        print("🖊️ 그리기 시작: \(point.latitude), \(point.longitude)")
    }

    /// 그리기 계속 (터치 이동)
    func continueDrawing(to point: CoordinateManager) {
        guard isDrawing else { return }

        // 좌표 샘플링: 일정 거리 이상 이동 시에만 추가
        if shouldSamplePoint(point) {
            currentDrawingPoints.append(point)
            lastSampledPoint = point
        }
    }

    /// 그리기 종료 및 저장
    func finishDrawing() {
        guard isDrawing && currentDrawingPoints.count >= 2 else {
            // 포인트가 부족하면 저장하지 않음
            currentDrawingPoints = []
            isDrawing = false
            return
        }

        // 스무딩된 포인트 생성 (렌더링용 캐싱) - 포인트 개수에 따라 동적 세그먼트 적용
        let smoothedPoints = SketchSmoothingAlgorithm.smoothUsingCatmullRom(currentDrawingPoints)

        // 새 스케치 생성 (원본 포인트로 저장, 스무딩 포인트는 캐싱)
        let newSketch = SketchModel(
            points: currentDrawingPoints,       // 원본 포인트 (Firebase/로컬 저장용)
            color: currentColor,
            strokeWidth: currentStrokeWidth,
            opacity: currentOpacity,
            smoothedPoints: smoothedPoints      // 렌더링용 캐시 (저장 안 됨)
        )

        // 저장
        SketchRepository.shared.addSketch(newSketch)

        // 공간 인덱스에 추가 (증분 업데이트)
        addToSpatialIndex(newSketch)

        // 새 액션 수행 시 redo 스택 초기화 (일반적인 Undo/Redo 동작)
        redoStack.removeAll()

        // 생성 액션으로 undo 스택에 저장 (undo 시 삭제 가능)
        undoStack.append(.create(sketch: newSketch))
        updateUndoRedoState()

        // Analytics 이벤트
        logSketchCreated()

        print("✅ 스케치 저장 완료: \(currentDrawingPoints.count)개 포인트 (원본), 렌더링: \(smoothedPoints.count)개 포인트")

        // 상태 초기화
        currentDrawingPoints = []
        lastSampledPoint = nil
        isDrawing = false
    }

    /// 현재 그리기 취소
    func cancelDrawing() {
        currentDrawingPoints = []
        lastSampledPoint = nil
        isDrawing = false

        print("❌ 그리기 취소됨")
    }

    // MARK: - Color & Style

    /// 색상 변경
    func setColor(_ color: String) {
        currentColor = color
        UserDefaults.standard.set(color, forKey: sketchColorKey)
        print("🎨 스케치 색상 변경: \(color)")
    }

    /// 선 두께 변경
    func setStrokeWidth(_ width: Double) {
        currentStrokeWidth = max(1.0, min(20.0, width))
        UserDefaults.standard.set(currentStrokeWidth, forKey: sketchStrokeWidthKey)
        print("━ 스케치 두께 변경: \(currentStrokeWidth)")
    }

    /// 투명도 변경
    func setOpacity(_ opacity: Double) {
        currentOpacity = max(0.1, min(1.0, opacity))
        UserDefaults.standard.set(currentOpacity, forKey: sketchOpacityKey)
        print("◐ 스케치 투명도 변경: \(currentOpacity)")
    }

    // MARK: - Undo/Redo Operations

    /// 실행취소 (마지막 액션 취소)
    func undo() {
        guard let action = undoStack.popLast() else { return }

        // 취소한 액션을 redoStack에 저장
        redoStack.append(action)

        switch action {
        case .create(let sketch):
            // 그리기 취소 → 스케치 삭제
            SketchRepository.shared.removeSketch(id: sketch.id)
            // 공간 인덱스에서 제거 (증분 업데이트)
            removeFromSpatialIndex(id: sketch.id)
            print("↩️ 그리기 취소: \(sketch.id)")

        case .delete(let sketches):
            // 삭제 취소 → 스케치 복원 (알림/저장 없이 배치 처리)
            for sketch in sketches {
                SketchFileStore.shared.addSketchWithoutNotification(sketch)
                // 공간 인덱스에 추가 (증분 업데이트)
                addToSpatialIndex(sketch)
            }
            // 배치 완료 후 한 번만 저장
            SketchFileStore.shared.saveAfterBatchOperation()
            // pendingDeleteIds에서 제거 (Firebase 삭제 방지)
            SketchRepository.shared.removePendingDeleteIds(sketches.map { $0.id })

            // 복원된 스케치를 modifiedSketchIds에 추가 (Firebase 동기화 대상)
            for sketch in sketches {
                SketchRepository.shared.trackModifiedSketch(id: sketch.id)
            }

            // 모든 복원 완료 후 한 번만 알림 전송
            NotificationCenter.default.post(name: .sketchesDidChange, object: nil)
            print("↩️ 삭제 취소: \(sketches.count)개 복원")
        }

        updateUndoRedoState()
    }

    /// 다시실행 (취소한 액션 다시 실행)
    func redo() {
        guard let action = redoStack.popLast() else { return }

        // 다시 실행한 액션을 undoStack에 저장
        undoStack.append(action)

        switch action {
        case .create(let sketch):
            // 그리기 다시 실행 → 스케치 추가
            SketchRepository.shared.addSketch(sketch)
            // 공간 인덱스에 추가 (증분 업데이트)
            addToSpatialIndex(sketch)
            print("↪️ 그리기 다시: \(sketch.id)")

        case .delete(let sketches):
            // 삭제 다시 실행 (알림/저장 없이 배치 처리)
            for sketch in sketches {
                SketchFileStore.shared.removeSketchWithoutNotification(id: sketch.id)
                // 공간 인덱스에서 제거 (증분 업데이트)
                removeFromSpatialIndex(id: sketch.id)
            }
            // 배치 완료 후 한 번만 저장
            SketchFileStore.shared.saveAfterBatchOperation()
            // pendingDeleteIds에 다시 추가 (Firebase 삭제 예약)
            SketchRepository.shared.addPendingDeleteIds(sketches.map { $0.id })
            // 모든 삭제 완료 후 한 번만 알림 전송
            NotificationCenter.default.post(name: .sketchesDidChange, object: nil)
            print("↪️ 삭제 다시: \(sketches.count)개 삭제")
        }

        updateUndoRedoState()
    }

    /// Undo/Redo 상태 업데이트
    private func updateUndoRedoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// 스케치 모드 진입 시 Undo/Redo 스택 초기화
    private func resetUndoRedoStacks() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoRedoState()
    }

    // MARK: - Eraser Mode

    /// 지우개 모드 토글
    func toggleEraserMode() {
        isEraserModeActive.toggle()
        print("🧹 지우개 모드: \(isEraserModeActive ? "활성" : "비활성")")
    }

    /// 터치 좌표에서 가장 가까운 스케치 삭제
    /// - Returns: 삭제 성공 여부
    func deleteSketchAtPoint(_ point: CoordinateManager) -> Bool {
        let tolerance: Double = 30.0 // 미터

        // 1단계: BoundingBox로 후보 필터링 (O(n) but 대부분 걸러짐)
        let candidates = getCandidateSketches(near: point, tolerance: tolerance)

        guard !candidates.isEmpty else {
            print("🧹 삭제할 스케치 없음 (BoundingBox 필터)")
            return false
        }

        // 2단계: 후보 내에서 정밀 거리 계산
        var closestSketchId: UUID?
        var closestDistance: Double = .greatestFiniteMagnitude

        for sketch in candidates {
            let distance = minDistanceToSketch(point: point, sketch: sketch)
            if distance < closestDistance && distance <= tolerance {
                closestDistance = distance
                closestSketchId = sketch.id
            }
        }

        // 스케치 삭제
        if let sketchId = closestSketchId {
            deleteSketch(id: sketchId)
            print("🧹 터치로 스케치 삭제: \(sketchId)")
            return true
        }

        print("🧹 삭제할 스케치 없음 (터치 위치에 스케치 없음)")
        return false
    }

    /// 터치 좌표와 스케치 간 최소 거리 계산 (미터)
    /// - 점 대 선분 거리로 계산하여 선 중간 터치도 정확하게 감지
    private func minDistanceToSketch(point: CoordinateManager, sketch: SketchModel) -> Double {
        var minDistance: Double = .greatestFiniteMagnitude
        let points = sketch.points

        // 점이 1개뿐인 경우: 점 대 점 거리
        if points.count == 1 {
            return DistanceCalculator.haversine(from: point, to: points[0])
        }

        // 연속된 점들 사이의 선분과의 거리 계산
        for i in 0..<(points.count - 1) {
            let distance = DistanceCalculator.toSegment(
                point: point,
                segmentStart: points[i],
                segmentEnd: points[i + 1]
            )
            minDistance = min(minDistance, distance)
        }

        return minDistance
    }

    // MARK: - Sketch Management

    /// 특정 스케치 삭제
    func deleteSketch(id: UUID) {
        // 삭제 전 스케치를 undoStack에 액션으로 저장
        if let sketchToDelete = SketchRepository.shared.getSketch(id: id) {
            // 새 액션 수행 시 redo 스택 초기화
            redoStack.removeAll()
            undoStack.append(.delete(sketches: [sketchToDelete]))
        }

        SketchRepository.shared.removeSketch(id: id)
        // 공간 인덱스에서 제거 (증분 업데이트)
        removeFromSpatialIndex(id: id)
        updateUndoRedoState()

        // Analytics 이벤트
        logSketchDeleted()

        print("🗑️ 스케치 삭제됨: \(id)")
    }

    /// 모든 스케치 삭제
    func deleteAllSketches() {
        let allSketches = SketchFileStore.shared.sketches
        let count = allSketches.count

        guard count > 0 else { return }

        // 새 액션 수행 시 redo 스택 초기화
        redoStack.removeAll()

        // 모든 스케치를 하나의 액션으로 undoStack에 저장 (Undo 한 번으로 전체 복구)
        undoStack.append(.delete(sketches: allSketches))

        SketchRepository.shared.clearAllSketches()
        // 공간 인덱스 전체 초기화 (모든 스케치 삭제)
        sketchBoundingBoxes.removeAll()
        updateUndoRedoState()

        // Analytics 이벤트
        Analytics.logEvent("sketch_all_cleared", parameters: [
            "deleted_count": count
        ])

        print("🗑️ 모든 스케치 삭제됨: \(count)개")
    }

    // MARK: - Private Methods

    /// 좌표 샘플링 여부 결정 (최적화 버전)
    private func shouldSamplePoint(_ point: CoordinateManager) -> Bool {
        guard let lastPoint = lastSampledPoint else {
            return true
        }

        // 빠른 근사 거리 사용 (DistanceCalculator 활용)
        let distance = DistanceCalculator.fastApprox(from: lastPoint, to: point)
        return distance >= minSamplingDistance
    }

    // MARK: - Spatial Indexing

    /// 공간 인덱스 전체 업데이트 (스케치 모드 진입 시 호출)
    func updateSpatialIndex() {
        sketchBoundingBoxes.removeAll()
        for sketch in SketchFileStore.shared.sketches {
            sketchBoundingBoxes[sketch.id] = calculateBoundingBox(for: sketch)
        }
        print("🗺️ 공간 인덱스 전체 업데이트: \(sketchBoundingBoxes.count)개 스케치")
    }

    /// 공간 인덱스에 스케치 추가 (증분 업데이트)
    func addToSpatialIndex(_ sketch: SketchModel) {
        sketchBoundingBoxes[sketch.id] = calculateBoundingBox(for: sketch)
    }

    /// 공간 인덱스에서 스케치 제거 (증분 업데이트)
    func removeFromSpatialIndex(id: UUID) {
        sketchBoundingBoxes.removeValue(forKey: id)
    }

    /// 스케치의 BoundingBox 계산
    private func calculateBoundingBox(for sketch: SketchModel) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        guard !sketch.points.isEmpty else {
            return (0, 0, 0, 0)
        }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for point in sketch.points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        return (minLat, maxLat, minLon, maxLon)
    }

    /// 특정 좌표 주변의 스케치 후보 필터링 (tolerance 반경 내)
    private func getCandidateSketches(near point: CoordinateManager, tolerance: Double) -> [SketchModel] {
        // tolerance를 대략적인 위도/경도 차이로 변환 (1도 = 약 111km)
        let latTolerance = tolerance / 111000.0
        let lonTolerance = tolerance / (111000.0 * cos(point.latitude * .pi / 180))

        let sketches = SketchFileStore.shared.sketches

        return sketches.filter { sketch in
            guard let bbox = sketchBoundingBoxes[sketch.id] else {
                // 인덱스에 없으면 후보에 포함 (안전한 fallback)
                return true
            }

            // BoundingBox + tolerance 범위 내에 있는지 확인
            let expandedMinLat = bbox.minLat - latTolerance
            let expandedMaxLat = bbox.maxLat + latTolerance
            let expandedMinLon = bbox.minLon - lonTolerance
            let expandedMaxLon = bbox.maxLon + lonTolerance

            return point.latitude >= expandedMinLat &&
                   point.latitude <= expandedMaxLat &&
                   point.longitude >= expandedMinLon &&
                   point.longitude <= expandedMaxLon
        }
    }

    // MARK: - Analytics

    /// 스케치 모드 진입 이벤트
    private func logSketchModeEnter() {
        Analytics.logEvent("sketch_mode_enter", parameters: nil)
    }

    /// 스케치 모드 종료 이벤트
    private func logSketchModeExit(duration: TimeInterval) {
        Analytics.logEvent("sketch_mode_exit", parameters: [
            "duration_seconds": Int(duration)
        ])
    }

    /// 스케치 생성 이벤트
    private func logSketchCreated() {
        Analytics.logEvent("sketch_created", parameters: [
            "total_count": SketchRepository.shared.totalSketchCount,
            "active_count": SketchRepository.shared.activeSketchCount
        ])
    }

    /// 스케치 삭제 이벤트
    private func logSketchDeleted() {
        Analytics.logEvent("sketch_deleted", parameters: [
            "active_count": SketchRepository.shared.activeSketchCount
        ])
    }
}
