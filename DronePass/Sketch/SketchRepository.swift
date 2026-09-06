//
//  SketchRepository.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 저장소 통합 관리 (로컬 + Firebase)
// 연관기능: 스케치 CRUD, 동기화

import Foundation
import Combine

/// 스케치 동기화 상태
enum SketchSyncStatus {
    case idle
    case syncing
    case completed
    case failed(Error)
}

/// 스케치 저장소 (로컬 + Firebase 통합)
@MainActor
final class SketchRepository: ObservableObject {
    static let shared = SketchRepository()

    @Published var syncStatus: SketchSyncStatus = .idle

    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false  // @MainActor로 자동 보호됨

    // Task 참조 (취소 가능)
    private var syncTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    // 중복 알림 전송 방지
    private var lastNotificationTime: Date = Date.distantPast
    private let notificationDebounceInterval: TimeInterval = 0.1

    // 편집 모드에서 삭제 대기 중인 스케치 ID (완료 시 Firebase에 동기화)
    private var pendingDeleteIds: Set<UUID> = []

    // 스케치 모드 중 변경된 스케치 ID 추적 (생성 또는 수정)
    private var modifiedSketchIds: Set<UUID> = []

    // 스케치 모드 시작 시 이미 존재하던 스케치 ID (Firebase에 있을 수 있는 스케치)
    private var existingSketchIdsOnEnter: Set<UUID> = []

    private init() {
        // 로그인 상태 변경 감지
        Publishers.CombineLatest(
            AppleLoginManager.shared.$isLogin,
            SettingManager.shared.$isCloudBackupEnabled
        )
        .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        .sink { [weak self] isLogin, isCloudBackupEnabled in
            if isLogin && isCloudBackupEnabled {
                self?.syncLocalToFirebase()
            }
        }
        .store(in: &cancellables)
    }

    // MARK: - Public Properties

    /// 현재 스케치 목록 (SketchFileStore에서 관리)
    var sketches: [SketchModel] {
        return SketchFileStore.shared.sketches
    }

    /// 활성 스케치 개수
    var activeSketchCount: Int {
        return SketchFileStore.shared.activeSketchCount
    }

    /// 총 생성된 스케치 개수 (누적)
    var totalSketchCount: Int {
        return SketchFileStore.shared.totalSketchCount
    }

    // MARK: - CRUD Operations

    /// 스케치 추가 (로컬에만 저장, Firebase 동기화는 completeAndSync() 호출 시)
    func addSketch(_ sketch: SketchModel) {
        var newSketch = sketch
        newSketch.updatedAt = Date()

        // 로컬에만 추가 (즉시 UI 반영)
        SketchFileStore.shared.addSketch(newSketch)

        // 변경된 스케치로 추적 (Firebase 동기화 시 업로드 대상)
        modifiedSketchIds.insert(newSketch.id)

        // 알림 전송
        sendSketchesDidChangeNotification()

        print("📝 스케치 로컬 저장: \(newSketch.id)")
    }

    /// 스케치 업데이트 (로컬에만 저장)
    func updateSketch(_ sketch: SketchModel) {
        var updatedSketch = sketch
        updatedSketch.updatedAt = Date()

        // 로컬 업데이트
        SketchFileStore.shared.updateSketch(updatedSketch)

        // 변경된 스케치로 추적 (Firebase 동기화 시 업로드 대상)
        modifiedSketchIds.insert(updatedSketch.id)

        // 알림 전송
        sendSketchesDidChangeNotification()

        print("📝 스케치 로컬 업데이트: \(updatedSketch.id)")
    }

    /// 스케치 삭제 (로컬에서만 삭제, Firebase 동기화는 완료 시 처리)
    func removeSketch(id: UUID) {
        // 1. 로컬에서 삭제
        SketchFileStore.shared.removeSketch(id: id)

        // 2. 기존에 있던 스케치만 삭제 대기에 추가 (Firebase에 있을 수 있음)
        //    이번 세션에서 새로 만든 스케치는 Firebase에 없으므로 삭제 요청 불필요
        if existingSketchIdsOnEnter.contains(id) {
            pendingDeleteIds.insert(id)
            print("📝 스케치 로컬 삭제 (Firebase 삭제 대기): \(id)")
        } else {
            print("📝 스케치 로컬 삭제 (새로 생성된 스케치, Firebase 동기화 불필요): \(id)")
        }

        // 3. 변경 추적에서 제거 (삭제될 스케치를 Firebase에 저장할 필요 없음)
        modifiedSketchIds.remove(id)

        // 삭제는 즉시 UI에 반영되어야 하므로 디바운싱 없이 알림 발송
        NotificationCenter.default.post(name: .sketchesDidChange, object: nil)
        lastNotificationTime = Date()
    }

    /// 모든 스케치 삭제 (로컬에서만 삭제, Firebase 동기화는 완료 시 처리)
    func clearAllSketches() {
        let sketchIds = sketches.map { $0.id }
        let count = sketchIds.count

        // 1. 로컬에서 모두 삭제
        SketchFileStore.shared.clearAllSketches()

        // 2. 기존에 있던 스케치만 삭제 대기에 추가 (Firebase에 있을 수 있음)
        var firebaseDeleteCount = 0
        for id in sketchIds {
            if existingSketchIdsOnEnter.contains(id) {
                pendingDeleteIds.insert(id)
                firebaseDeleteCount += 1
            }
        }

        // 3. 변경 추적 초기화 (모두 삭제되므로)
        modifiedSketchIds.removeAll()

        // 삭제는 즉시 UI에 반영되어야 하므로 디바운싱 없이 알림 발송
        NotificationCenter.default.post(name: .sketchesDidChange, object: nil)
        lastNotificationTime = Date()

        print("📝 모든 스케치 로컬 삭제: \(count)개 (Firebase 삭제 대기: \(firebaseDeleteCount)개)")
    }

    // MARK: - Firebase 동기화 (완료 시 호출)

    /// 스케치 모드 완료 시 Firebase에 동기화
    /// - 현재 로컬에 저장된 모든 스케치를 Firebase에 업로드
    /// - 삭제 대기 중인 스케치를 Firebase에 soft delete
    func syncToFirebaseOnComplete() {
        guard shouldSyncToFirebase else {
            print("☁️ Firebase 동기화 비활성화 상태")
            // 대기 목록 초기화
            pendingDeleteIds.removeAll()
            return
        }

        let localSketches = SketchFileStore.shared.sketches
        let deleteIds = pendingDeleteIds

        // 스케치나 삭제 대기가 있으면 동기화
        if !localSketches.isEmpty || !deleteIds.isEmpty {
            syncLocalToFirebaseWithDeletes(deleteIds: deleteIds)
            print("☁️ 스케치 완료 - Firebase 동기화 시작: 저장 \(localSketches.count)개, 삭제 \(deleteIds.count)개")
        } else {
            print("☁️ 동기화할 스케치 없음")
        }

        // 대기 목록 초기화
        pendingDeleteIds.removeAll()
    }

    /// 스케치 편집 취소 시 대기 목록 초기화
    func cancelPendingChanges() {
        pendingDeleteIds.removeAll()
        print("📝 스케치 대기 변경사항 취소됨")
    }

    /// Undo 시 삭제 대기 ID 제거 (삭제 취소됨)
    func removePendingDeleteIds(_ ids: [UUID]) {
        for id in ids {
            pendingDeleteIds.remove(id)
        }
        print("📝 삭제 대기에서 제거: \(ids.count)개")
    }

    /// Redo 시 삭제 대기 ID 추가 (다시 삭제됨)
    /// 기존에 있던 스케치만 추가 (새로 생성된 스케치는 Firebase에 없으므로 제외)
    func addPendingDeleteIds(_ ids: [UUID]) {
        var addedCount = 0
        for id in ids {
            if existingSketchIdsOnEnter.contains(id) {
                pendingDeleteIds.insert(id)
                addedCount += 1
            }
            // 변경 추적에서도 제거
            modifiedSketchIds.remove(id)
        }
        print("📝 삭제 대기에 추가: \(addedCount)개 (전체 \(ids.count)개 중)")
    }

    /// 스케치 모드 시작 시 변경 추적 초기화
    func resetModifiedTracking() {
        modifiedSketchIds.removeAll()
        pendingDeleteIds.removeAll()
        // 현재 로컬에 존재하는 스케치 ID들을 기억 (Firebase에 있을 수 있는 스케치)
        existingSketchIdsOnEnter = Set(SketchFileStore.shared.sketches.map { $0.id })
        print("📝 스케치 변경 추적 초기화, 기존 스케치 \(existingSketchIdsOnEnter.count)개 기록")
    }

    /// Undo/Redo에서 복원된 스케치 추적 (Firebase 동기화 대상에 추가)
    func trackModifiedSketch(id: UUID) {
        modifiedSketchIds.insert(id)
        print("📝 스케치 변경 추적에 추가: \(id)")
    }

    /// 진행 중인 동기화 취소
    func cancelPendingSync() {
        syncTask?.cancel()
        loadTask?.cancel()
        isSyncing = false
        syncStatus = .idle
        print("📝 동기화 취소됨")
    }

    /// 스케치 조회
    func getSketch(id: UUID) -> SketchModel? {
        return SketchFileStore.shared.getSketch(id: id)
    }

    /// 스케치 로드
    func loadSketches() {
        SketchFileStore.shared.loadSketches()

        // Firebase에서 동기화 (로그인 시)
        if shouldSyncToFirebase {
            syncFirebaseToLocal()
        }
    }

    // MARK: - Sync Operations

    /// Firebase에 동기화해야 하는지 확인
    private var shouldSyncToFirebase: Bool {
        return AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled
    }

    /// 로컬 -> Firebase 동기화 (삭제 포함)
    private func syncLocalToFirebaseWithDeletes(deleteIds: Set<UUID>) {
        guard !isSyncing else { return }

        // 기존 Task 취소
        syncTask?.cancel()

        isSyncing = true
        syncStatus = .syncing

        syncTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Task 취소 체크
                try Task.checkCancellation()

                // 1. 삭제 대기 스케치 처리
                if !deleteIds.isEmpty {
                    for id in deleteIds {
                        try Task.checkCancellation()
                        try await SketchFirebaseStore.shared.removeSketch(id: id)
                    }
                    print("☁️ Firebase 스케치 soft delete 완료: \(deleteIds.count)개")
                }

                try Task.checkCancellation()

                // 2. 변경된 스케치만 저장 (새로 생성 또는 수정된 것)
                let localSketches = SketchFileStore.shared.sketches
                let modifiedSketches = localSketches.filter { self.modifiedSketchIds.contains($0.id) }
                if !modifiedSketches.isEmpty {
                    try await SketchFirebaseStore.shared.saveSketches(modifiedSketches)
                    print("✅ 변경된 스케치 \(modifiedSketches.count)개를 Firebase에 동기화 완료")
                } else if deleteIds.isEmpty {
                    print("☁️ 변경된 스케치 없음, Firebase 동기화 스킵")
                }

                try Task.checkCancellation()

                // 동기화 완료 후 변경 추적 초기화
                self.modifiedSketchIds.removeAll()

                // 서버 메타데이터 업데이트 (변경이 있는 경우에만)
                if !modifiedSketches.isEmpty || !deleteIds.isEmpty {
                    try await SketchFirebaseStore.shared.updateServerMetadata()
                }

                // 로컬 변경 시간 기록 (자신의 변경으로 인한 동기화 방지)
                UserDefaults.standard.set(Date(), forKey: "lastLocalSketchModificationTime")

                self.syncStatus = .completed

                try? await Task.sleep(nanoseconds: 2_000_000_000)

                if !Task.isCancelled {
                    self.syncStatus = .idle
                }

            } catch is CancellationError {
                print("⚠️ Firebase 동기화 취소됨")
                self.syncStatus = .idle

            } catch {
                print("❌ 로컬 -> Firebase 동기화 실패: \(error)")

                self.syncStatus = .failed(error)

                try? await Task.sleep(nanoseconds: 3_000_000_000)

                if !Task.isCancelled {
                    self.syncStatus = .idle
                }
            }

            self.isSyncing = false
        }
    }

    /// 로컬 -> Firebase 동기화 (기존 호환성 유지)
    private func syncLocalToFirebase() {
        syncLocalToFirebaseWithDeletes(deleteIds: [])
    }

    /// Firebase -> 로컬 동기화
    private func syncFirebaseToLocal() {
        guard !isSyncing else { return }

        // 기존 Task 취소
        loadTask?.cancel()

        isSyncing = true

        loadTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                try Task.checkCancellation()

                let firebaseSketches = try await SketchFirebaseStore.shared.loadSketches()

                try Task.checkCancellation()

                let localSketches = SketchFileStore.shared.sketches

                // Firebase에만 있는 스케치를 로컬에 추가
                let localIds = Set(localSketches.map { $0.id })
                let sketchesToDownload = firebaseSketches.filter { !localIds.contains($0.id) }

                for sketch in sketchesToDownload {
                    try Task.checkCancellation()
                    SketchFileStore.shared.addSketch(sketch)
                }

                if !sketchesToDownload.isEmpty {
                    print("✅ Firebase 스케치 \(sketchesToDownload.count)개를 로컬에 동기화 완료")
                    sendSketchesDidChangeNotification()
                }

            } catch is CancellationError {
                print("⚠️ Firebase 로드 취소됨")

            } catch {
                print("❌ Firebase -> 로컬 동기화 실패: \(error)")
            }

            self.isSyncing = false
        }
    }

    // MARK: - 실시간 동기화

    /// 원격 변경사항 적용 (RealtimeSyncManager에서 호출)
    func applyRemoteChanges(_ remoteSketches: [SketchModel]) {
        let currentLocalSketches = SketchFileStore.shared.sketches
        let localIds = Set(currentLocalSketches.map { $0.id })

        // Firebase에만 있는 스케치를 로컬에 추가 (삭제 대기 중인 스케치 제외)
        let sketchesToAdd = remoteSketches.filter { sketch in
            !localIds.contains(sketch.id) &&
            sketch.deletedAt == nil &&
            !pendingDeleteIds.contains(sketch.id)
        }

        var mutatedLocal = currentLocalSketches

        if !sketchesToAdd.isEmpty {
            mutatedLocal.append(contentsOf: sketchesToAdd)
            print("✅ 스케치 실시간 동기화: 추가된 스케치 \(sketchesToAdd.count)개 병합")
        }

        // 서버에서 동일 ID 스케치는 서버 데이터로 덮어쓰기 (Last-Writer-Wins)
        // 중복 id 방어: uniqueKeysWithValues는 중복 키에서 크래시하므로 마지막 값 우선으로 병합
        let serverById = Dictionary(remoteSketches.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var overwriteCount = 0
        for i in 0..<mutatedLocal.count {
            if let serverSketch = serverById[mutatedLocal[i].id] {
                // 삭제 대기 중인 스케치는 덮어쓰지 않음
                if pendingDeleteIds.contains(serverSketch.id) {
                    continue
                }
                // 서버에서 삭제된 스케치가 아니고 데이터가 다른 경우 덮어쓰기
                if serverSketch.deletedAt == nil && mutatedLocal[i] != serverSketch {
                    mutatedLocal[i] = serverSketch
                    overwriteCount += 1
                }
            }
        }
        if overwriteCount > 0 {
            print("🔁 스케치 실시간 동기화: 서버 값으로 기존 스케치 덮어쓰기 \(overwriteCount)개")
        }

        // 서버에서 삭제된 스케치(soft delete 처리된 문서)는 로컬에서도 제거
        let deletedServerIds = remoteSketches.filter { $0.deletedAt != nil }.map { $0.id }
        if !deletedServerIds.isEmpty {
            let beforeCount = mutatedLocal.count
            mutatedLocal.removeAll { deletedServerIds.contains($0.id) }
            let removed = beforeCount - mutatedLocal.count
            if removed > 0 {
                print("🗑️ 스케치 실시간 동기화: 서버에서 삭제된 스케치 로컬 제거 \(removed)개")
            }
        }

        // 로컬에 저장
        SketchFileStore.shared.setSketches(mutatedLocal)

        // UI 업데이트 알림
        sendSketchesDidChangeNotification()

        print("✅ 스케치 실시간 동기화 완료: 총 \(mutatedLocal.count)개")
    }

    // MARK: - Notification

    /// 스케치 변경 알림 전송 (디바운싱)
    private func sendSketchesDidChangeNotification() {
        let now = Date()
        if now.timeIntervalSince(lastNotificationTime) >= notificationDebounceInterval {
            NotificationCenter.default.post(name: .sketchesDidChange, object: nil)
            lastNotificationTime = now
            print("🔄 sketchesDidChange 알림 전송")
        }
    }
}

// MARK: - Notification Name Extension
extension Notification.Name {
    static let sketchesDidChange = Notification.Name("sketchesDidChange")
}
