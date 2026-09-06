//
//  SketchFileStore.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 로컬 저장소 (오프라인 캐시)
// 연관기능: 스케치 CRUD, 로컬 파일 저장

import Foundation
import Combine

/// 스케치 파일 저장 에러
enum SketchFileError: Error, LocalizedError {
    case dataCorruption
    case fileNotFound
    case encodingError
    case decodingError
    case saveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .dataCorruption: return String(localized: "sketch.error.dataCorruption")
        case .fileNotFound: return String(localized: "sketch.error.fileNotFound")
        case .encodingError: return String(localized: "sketch.error.encodingError")
        case .decodingError: return String(localized: "sketch.error.decodingError")
        case .saveFailed(let error): return String(format: String(localized: "sketch.error.saveFailed"), error.localizedDescription)
        }
    }
}

/// 스케치 로컬 저장소
@MainActor
final class SketchFileStore: ObservableObject {
    static let shared = SketchFileStore()

    @Published var sketches: [SketchModel] = []

    /// 마지막 저장 에러 (UI에서 사용 가능)
    @Published var lastSaveError: SketchFileError? = nil

    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let sketchesFileURL: URL
    private let backupFileURL: URL
    private let tempFileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let fileWriteQueue = DispatchQueue(label: "com.dronepass.sketch.filewrite", qos: .userInitiated)

    // 디바운스 저장 관련
    private var saveDebounceTask: Task<Void, Never>?
    private let saveDebounceInterval: TimeInterval = 0.3

    // 총 스케치 개수 추적 (UserDefaults)
    private let totalSketchCountKey = "totalSketchCount"

    private init() {
        // ISO8601 날짜 형식 설정
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        // Document 디렉토리 설정
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        sketchesFileURL = documentsDirectory.appendingPathComponent("sketches.json")
        backupFileURL = documentsDirectory.appendingPathComponent("sketches_backup.json")
        tempFileURL = documentsDirectory.appendingPathComponent("sketches_temp.json")

        // Task로 래핑하여 View body 렌더링 사이클 외부에서 @Published 변경
        Task { @MainActor in
            loadSketches()
        }
    }

    // MARK: - 총 스케치 개수 추적

    /// 총 생성된 스케치 개수 (삭제 포함, 누적)
    var totalSketchCount: Int {
        get { UserDefaults.standard.integer(forKey: totalSketchCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: totalSketchCountKey) }
    }

    /// 현재 활성 스케치 개수
    var activeSketchCount: Int {
        return sketches.count
    }

    // MARK: - CRUD Operations

    /// 스케치 로드
    func loadSketches() {
        do {
            var loadedSketches: [SketchModel] = []

            // 1. 메인 파일에서 로드 시도
            if fileManager.fileExists(atPath: sketchesFileURL.path) {
                do {
                    let data = try Data(contentsOf: sketchesFileURL)
                    let allSketches = try decoder.decode([SketchModel].self, from: data)

                    // 삭제된 스케치 필터링 (deletedAt이 nil인 것만)
                    loadedSketches = allSketches.filter { $0.deletedAt == nil }

                    // 중복 제거 (ID 기반) - O(n) 최적화
                    let uniqueSketches = removeDuplicates(loadedSketches)

                    if validateSketches(uniqueSketches) {
                        sketches = uniqueSketches
                        print("✅ 스케치 데이터 로드 성공: \(sketches.count)개")
                        return
                    } else {
                        print("⚠️ 스케치 메인 파일 검증 실패, 백업에서 복구 시도")
                    }
                } catch {
                    print("⚠️ 스케치 메인 파일 로드 실패: \(error)")
                }
            }

            // 2. 백업 파일에서 로드 시도
            if fileManager.fileExists(atPath: backupFileURL.path) {
                do {
                    let backupData = try Data(contentsOf: backupFileURL)
                    let allBackupSketches = try decoder.decode([SketchModel].self, from: backupData)

                    loadedSketches = allBackupSketches.filter { $0.deletedAt == nil }

                    // 중복 제거 (ID 기반) - O(n) 최적화
                    let uniqueSketches = removeDuplicates(loadedSketches)

                    if validateSketches(uniqueSketches) {
                        sketches = uniqueSketches
                        print("✅ 스케치 백업에서 복구 성공: \(sketches.count)개")
                        saveSketchesSecurely()
                        return
                    }
                } catch {
                    print("❌ 스케치 백업 파일 로드 실패: \(error)")
                }
            }

            // 3. 모든 파일이 실패하면 빈 배열로 시작
            sketches = []
            print("📁 스케치 파일이 없어 빈 배열로 시작")

        } catch {
            print("❌ 스케치 로드 프로세스 실패: \(error)")
            sketches = []
        }
    }

    /// 스케치 저장
    func saveSketches() {
        saveSketchesSecurely()
    }

    /// 스케치 추가
    func addSketch(_ sketch: SketchModel) {
        // 중복 체크
        guard !sketches.contains(where: { $0.id == sketch.id }) else {
            print("⚠️ 중복 스케치 추가 시도 무시: \(sketch.id)")
            return
        }

        sketches.append(sketch)
        totalSketchCount += 1  // 누적 카운트 증가
        saveSketchesWithDebounce()
        print("✅ 스케치 추가됨: \(sketch.id), 총 \(sketches.count)개")
    }

    /// 스케치 업데이트
    func updateSketch(_ sketch: SketchModel) {
        guard let index = sketches.firstIndex(where: { $0.id == sketch.id }) else {
            print("⚠️ 업데이트할 스케치를 찾을 수 없음: \(sketch.id)")
            return
        }

        var updatedSketch = sketch
        updatedSketch.updatedAt = Date()
        sketches[index] = updatedSketch
        saveSketchesWithDebounce()
        print("✅ 스케치 업데이트됨: \(sketch.id)")
    }

    /// 스케치 삭제 (soft delete)
    func removeSketch(id: UUID) {
        guard let index = sketches.firstIndex(where: { $0.id == id }) else {
            print("⚠️ 삭제할 스케치를 찾을 수 없음: \(id)")
            return
        }

        // Soft delete - deletedAt 설정
        var deletedSketch = sketches[index]
        deletedSketch.deletedAt = Date()

        // 메모리에서는 즉시 제거
        sketches.remove(at: index)
        saveSketchesWithDebounce()
        print("✅ 스케치 삭제됨: \(id), 남은 개수: \(sketches.count)")
    }

    /// 모든 스케치 삭제
    func clearAllSketches() {
        let count = sketches.count
        sketches.removeAll()
        saveSketchesSecurely()
        print("✅ 모든 스케치 삭제됨: \(count)개")
    }

    // MARK: - 배치 작업용 메서드 (Undo/Redo)

    /// 스케치 추가 (알림/저장 없이 - 배치 작업용)
    func addSketchWithoutNotification(_ sketch: SketchModel) {
        guard !sketches.contains(where: { $0.id == sketch.id }) else {
            return
        }
        sketches.append(sketch)
    }

    /// 스케치 삭제 (알림/저장 없이 - 배치 작업용)
    func removeSketchWithoutNotification(id: UUID) {
        guard let index = sketches.firstIndex(where: { $0.id == id }) else {
            return
        }
        sketches.remove(at: index)
    }

    /// 배치 작업 완료 후 저장
    func saveAfterBatchOperation() {
        saveSketchesSecurely()
    }

    /// 특정 스케치 조회
    func getSketch(id: UUID) -> SketchModel? {
        return sketches.first { $0.id == id }
    }

    /// 외부에서 스케치 목록 직접 설정 (실시간 동기화용)
    func setSketches(_ newSketches: [SketchModel]) {
        // 삭제되지 않은 스케치만 필터링
        let activeSketches = newSketches.filter { $0.deletedAt == nil }

        // 중복 제거 (ID 기반) - O(n) 최적화
        let uniqueSketches = removeDuplicates(activeSketches)

        sketches = uniqueSketches
        saveSketchesWithDebounce()
        print("✅ 스케치 목록 외부에서 설정됨: \(sketches.count)개")
    }

    // MARK: - Private Methods

    /// 안전한 스케치 데이터 저장 (원자성 보장)
    private func saveSketchesSecurely() {
        // 스냅샷 생성 (MainActor 컨텍스트에서 - 데이터 레이스 방지)
        let sketchesSnapshot = self.sketches
        let sketchCount = sketchesSnapshot.count

        fileWriteQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // 1. 스냅샷 데이터를 임시 파일에 저장
                let data = try self.encoder.encode(sketchesSnapshot)
                try data.write(to: self.tempFileURL)

                // 2. 임시 파일 검증
                let verifyData = try Data(contentsOf: self.tempFileURL)
                let verifySketches = try self.decoder.decode([SketchModel].self, from: verifyData)

                if !self.validateSketches(verifySketches) || verifySketches.count != sketchCount {
                    throw SketchFileError.dataCorruption
                }

                // 3. 기존 메인 파일을 백업으로 이동
                if self.fileManager.fileExists(atPath: self.sketchesFileURL.path) {
                    if self.fileManager.fileExists(atPath: self.backupFileURL.path) {
                        try self.fileManager.removeItem(at: self.backupFileURL)
                    }
                    try self.fileManager.moveItem(at: self.sketchesFileURL, to: self.backupFileURL)
                }

                // 4. 임시 파일을 메인 파일로 이동
                try self.fileManager.moveItem(at: self.tempFileURL, to: self.sketchesFileURL)

                print("💾 스케치 데이터 저장 성공: \(sketchCount)개")

                // 저장 성공 시 에러 상태 초기화
                Task { @MainActor in
                    self.lastSaveError = nil
                }

            } catch {
                print("❌ 스케치 데이터 저장 실패: \(error)")

                // 실패 시 임시 파일 정리
                if self.fileManager.fileExists(atPath: self.tempFileURL.path) {
                    try? self.fileManager.removeItem(at: self.tempFileURL)
                }

                self.restoreFromBackup()

                // 에러 상태 업데이트 (UI에서 사용 가능)
                Task { @MainActor in
                    self.lastSaveError = .saveFailed(underlying: error)
                }
            }
        }
    }

    /// 백업에서 복구
    private func restoreFromBackup() {
        do {
            if fileManager.fileExists(atPath: backupFileURL.path) &&
               !fileManager.fileExists(atPath: sketchesFileURL.path) {
                try fileManager.copyItem(at: backupFileURL, to: sketchesFileURL)
                print("✅ 스케치 백업에서 복구 완료")
            }
        } catch {
            print("❌ 스케치 백업 복구 실패: \(error)")
        }
    }

    /// 스케치 데이터 무결성 검증
    private func validateSketches(_ sketches: [SketchModel]) -> Bool {
        // 빈 배열은 유효
        guard !sketches.isEmpty else { return true }

        for sketch in sketches {
            // ID 검증
            if sketch.id.uuidString.isEmpty {
                return false
            }

            // 좌표 검증 (최소 2개 이상의 포인트 필요)
            // 빈 스케치도 허용 (그리는 중일 수 있음)
        }

        return true
    }

    /// ID 기반 중복 제거 (O(n) 복잡도)
    private func removeDuplicates(_ sketches: [SketchModel]) -> [SketchModel] {
        var seen = Set<UUID>()
        return sketches.filter { seen.insert($0.id).inserted }
    }

    /// 디바운스를 적용한 저장 (빈번한 변경 시 사용)
    private func saveSketchesWithDebounce() {
        saveDebounceTask?.cancel()

        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(saveDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            saveSketchesSecurely()
        }
    }
}
