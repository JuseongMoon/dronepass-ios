//
//  DroneRepository.swift
//  DronePass
//
//  Created by Claude on 2025-09-30.
//

// 역할: 드론 데이터 Repository 패턴 구현
// 연관기능: 로컬/Firebase 동기화, 오프라인 지원, 충돌 해결

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class DroneRepository: ObservableObject {
    static let shared = DroneRepository()

    // 데이터 소스
    private let firebaseStore = DroneFirebaseStore.shared
    private let localStore = DroneLocalStore.shared

    // 실시간 관찰자
    private var firebaseListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()

    // 동기화 상태
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?

    private init() {
        setupFirebaseListener()
    }

    // MARK: - 기본 CRUD

    func saveDrone(_ drone: DroneModel) async throws {
        // 1. 로컬 저장 (즉시 반영)
        try await localStore.save(drone)

        // 2. Firebase 저장 (백그라운드)
        if AuthManager.shared.isAuthenticated {
            Task {
                do {
                    try await firebaseStore.save(drone)
                } catch {
                    print("❌ 드론 Firebase 저장 실패: \(error)")
                    // TODO: 실패한 작업을 큐에 저장하여 나중에 재시도
                }
            }
        }
    }

    func loadDrones() async throws -> [DroneModel] {
        // 로그인되어 있으면 Firebase에서, 아니면 로컬에서 로드
        if AuthManager.shared.isAuthenticated {
            do {
                let firebaseDrones = try await firebaseStore.load()

                // Firebase 데이터를 로컬에 전체 교체 (오래된 데이터 제거)
                try await localStore.saveAll(firebaseDrones)

                await MainActor.run {
                    lastSyncTime = Date()
                }

                return firebaseDrones
            } catch {
                print("⚠️ Firebase 로드 실패, 로컬 데이터 사용: \(error)")
                return try await localStore.load()
            }
        } else {
            return try await localStore.load()
        }
    }

    func deleteDrone(id: String) async throws {
        // 1. 로컬 삭제
        try await localStore.delete(id: id)

        // 2. Firebase 삭제
        if AuthManager.shared.isAuthenticated {
            Task {
                do {
                    try await firebaseStore.delete(id: id)
                } catch {
                    print("❌ 드론 Firebase 삭제 실패: \(error)")
                }
            }
        }
    }

    // MARK: - 동기화

    func syncWithFirebase() async throws {
        guard AuthManager.shared.isAuthenticated else {
            print("🚁 로그인되지 않음, 동기화 건너뛰기")
            return
        }

        await MainActor.run {
            isSyncing = true
        }

        defer {
            Task { @MainActor in
                isSyncing = false
            }
        }

        do {
            // 1. Firebase에서 최신 데이터 가져오기
            let firebaseDrones = try await firebaseStore.load()
            let localDrones = try await localStore.load()

            // 2. 충돌 해결 (Last Write Wins 방식)
            let mergedDrones = mergeWithConflictResolution(
                localDrones: localDrones,
                firebaseDrones: firebaseDrones
            )

            // 3. 병합된 데이터를 양쪽에 저장
            try await firebaseStore.saveBatch(mergedDrones)
            try await localStore.saveAll(mergedDrones)

            await MainActor.run {
                lastSyncTime = Date()
            }

            print("🚁 드론 동기화 완료: \(mergedDrones.count)개")

        } catch {
            print("❌ 드론 동기화 실패: \(error)")
            throw error
        }
    }

    // MARK: - 실시간 동기화

    private func setupFirebaseListener() {
        // 로그인 상태 변경 감지
        AppleLoginManager.shared.$isLogin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLogin in
                if isLogin {
                    self?.startFirebaseListener()
                } else {
                    self?.stopFirebaseListener()
                }
            }
            .store(in: &cancellables)
    }

    private func startFirebaseListener() {
        guard AuthManager.shared.isAuthenticated else { return }

        // 🔧 중복 시작 방지: 이미 리스너가 활성화되어 있으면 스킵
        guard firebaseListener == nil else {
            print("⚠️ 드론 Firebase 리스너 이미 활성화됨 - 중복 시작 방지")
            return
        }

        firebaseListener = firebaseStore.observeChanges { [weak self] firebaseDrones in
            Task {
                await self?.handleFirebaseChanges(firebaseDrones)
            }
        }

        print("🚁 드론 Firebase 실시간 리스너 시작")
    }

    private func stopFirebaseListener() {
        firebaseListener?.remove()
        firebaseListener = nil
        print("🚁 드론 Firebase 실시간 리스너 중지")
    }

    @MainActor
    private func handleFirebaseChanges(_ firebaseDrones: [DroneModel]) async {
        do {
            let localDrones = try await localStore.load()

            // 색상 변경 감지
            let hasColorChange = detectColorChanges(
                localDrones: localDrones,
                firebaseDrones: firebaseDrones
            )

            // 충돌 해결
            let mergedDrones = mergeWithConflictResolution(
                localDrones: localDrones,
                firebaseDrones: firebaseDrones
            )

            // 로컬에 전체 교체 (오래된 데이터 제거)
            try await localStore.saveAll(mergedDrones)

            // DroneManager에 변경 알림
            NotificationCenter.default.post(
                name: .dronesDidChange,
                object: mergedDrones
            )

            // 색상 변경이 있으면 지도 오버레이 리로드 알림
            if hasColorChange {
                NotificationCenter.default.post(
                    name: Notification.Name("ReloadMapOverlays"),
                    object: nil
                )
                print("🎨 드론 색상 변경 감지 → 지도 오버레이 리로드")
            }

            lastSyncTime = Date()
            print("🚁 드론 실시간 동기화 완료: \(mergedDrones.count)개 (활성)")

        } catch {
            print("❌ 드론 실시간 동기화 처리 실패: \(error)")
        }
    }

    // MARK: - 충돌 해결

    /// 색상 변경 감지 헬퍼 함수
    private func detectColorChanges(
        localDrones: [DroneModel],
        firebaseDrones: [DroneModel]
    ) -> Bool {
        // 중복 id 방어: uniqueKeysWithValues는 중복 키에서 크래시하므로 마지막 값 우선으로 병합
        let localColorMap = Dictionary(localDrones.map { ($0.id, $0.color) }, uniquingKeysWith: { _, latest in latest })

        for firebaseDrone in firebaseDrones {
            if let localColor = localColorMap[firebaseDrone.id],
               localColor != firebaseDrone.color {
                return true
            }
        }

        return false
    }

    private func mergeWithConflictResolution(
        localDrones: [DroneModel],
        firebaseDrones: [DroneModel]
    ) -> [DroneModel] {
        var result: [String: DroneModel] = [:]

        // 1. 로컬 데이터 추가
        for drone in localDrones {
            result[drone.id] = drone
        }

        // 2. Firebase 데이터와 병합 (Last Write Wins)
        for firebaseDrone in firebaseDrones {
            if let localDrone = result[firebaseDrone.id] {
                // 충돌 해결: 더 최근 것 선택
                if firebaseDrone.updatedAt > localDrone.updatedAt {
                    result[firebaseDrone.id] = firebaseDrone
                }
            } else {
                result[firebaseDrone.id] = firebaseDrone
            }
        }

        return Array(result.values).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - 마이그레이션

    func migrateFromColorSystem() async throws {
        // 기존 색상 시스템에서 드론 시스템으로 마이그레이션
        let existingDrones = try await loadDrones()

        if existingDrones.isEmpty {
            // 초기 드론 생성
            let initialDrone = DroneModel.createDefault()
            try await saveDrone(initialDrone)
            print("🚁 초기 드론 생성 완료")
        }
    }

    // MARK: - 정리

    deinit {
        // deinit은 nonisolated이므로 리스너를 직접 제거
        firebaseListener?.remove()
        firebaseListener = nil
    }
}

// MARK: - 로컬 저장소

final class DroneLocalStore: DroneStoreProtocol {
    typealias DroneType = DroneModel

    static let shared = DroneLocalStore()

    private let userDefaultsKey = "localDrones"

    private init() {}

    func save(_ drone: DroneModel) async throws {
        var drones = try await load()

        // 기존 드론 업데이트 또는 새 드론 추가
        if let index = drones.firstIndex(where: { $0.id == drone.id }) {
            drones[index] = drone
        } else {
            drones.append(drone)
        }

        let data = try JSONEncoder().encode(drones)
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    func saveAll(_ drones: [DroneModel]) async throws {
        // 전체 드론 목록을 교체 (오래된 데이터 제거)
        let data = try JSONEncoder().encode(drones)
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        print("💾 로컬 드론 전체 저장: \(drones.count)개")
    }

    func load() async throws -> [DroneModel] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }

        return try JSONDecoder().decode([DroneModel].self, from: data)
    }

    func delete(id: String) async throws {
        var drones = try await load()
        drones.removeAll { $0.id == id }

        let data = try JSONEncoder().encode(drones)
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    func observeChanges(onChange: @escaping ([DroneModel]) -> Void) -> ListenerRegistration? {
        // 로컬 저장소는 실시간 관찰 지원 안함
        return nil
    }
}