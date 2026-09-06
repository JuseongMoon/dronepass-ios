//
//  PlaceShapeStore.swift
//  DronePass
//
//  Created by 문주성 on 5/19/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class ShapeFileStore: ObservableObject {
    static let shared = ShapeFileStore()
    @Published var shapes: [ShapeModel] = [] {
        didSet {
            // 불변식: shapes는 id-unique. 어떤 경로(addShape/직접 설정/동기화 병합)로 설정되든
            // 중복 id를 제거한다(LWW: updatedAt 최신 유지). 재귀는 가드로 1회만 발생.
            let deduped = Self.dedupedById(shapes)
            if deduped.count != shapes.count { shapes = deduped }
        }
    }
    @Published var selectedShapeID: UUID? = nil

    /// id별로 updatedAt이 가장 최신인 1개만 유지(LWW), 첫 등장 순서 보존.
    static func dedupedById(_ input: [ShapeModel]) -> [ShapeModel] {
        var latest: [UUID: ShapeModel] = [:]
        for s in input {
            if let existing = latest[s.id] {
                if s.updatedAt >= existing.updatedAt { latest[s.id] = s }
            } else {
                latest[s.id] = s
            }
        }
        var seen = Set<UUID>()
        var out: [ShapeModel] = []
        out.reserveCapacity(latest.count)
        for s in input where seen.insert(s.id).inserted {
            out.append(latest[s.id]!)
        }
        return out
    }
    @Published var isSaving: Bool = false  // 저장 진행 상태
    @Published var lastError: ShapeFileError? = nil  // 마지막 에러

    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let shapesFileURL: URL
    private let backupFileURL: URL
    private let tempFileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let fileWriteQueue = DispatchQueue(label: "com.dronepass.filewrite", qos: .userInitiated)
    
    private init() {
        // ISO8601 날짜 형식 설정 (기존 JSON 호환성)
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        
        // Document 디렉토리 설정
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        shapesFileURL = documentsDirectory.appendingPathComponent("shapes.json")
        backupFileURL = documentsDirectory.appendingPathComponent("shapes_backup.json")
        tempFileURL = documentsDirectory.appendingPathComponent("shapes_temp.json")
        
        loadShapes()
    }
    
    public func loadShapes() {
        do {
            var loadedShapes: [ShapeModel] = []

            // 1. 메인 파일에서 로드 시도
            if fileManager.fileExists(atPath: shapesFileURL.path) {
                do {
                    let data = try Data(contentsOf: shapesFileURL)
                    let allShapes = try decoder.decode([ShapeModel].self, from: data)

                    // 삭제된 도형들을 필터링 (deletedAt이 nil인 도형들만)
                    loadedShapes = allShapes.filter { shape in
                        return shape.deletedAt == nil
                    }

                    // 중복 제거 (ID 기반)
                    let uniqueShapes = Array(Set(loadedShapes.map { $0.id })).compactMap { id in
                        loadedShapes.first { $0.id == id }
                    }

                    // 데이터 무결성 검증
                    if validateShapes(uniqueShapes) {
                        shapes = uniqueShapes
                        print("✅ 메인 파일에서 도형 데이터 로드 성공: \(shapes.count)개 (전체: \(allShapes.count)개, 삭제됨: \(allShapes.count - loadedShapes.count)개, 중복제거: \(loadedShapes.count - uniqueShapes.count)개)")

                        // 알림은 실제 데이터 변경시(추가/수정/삭제)에만 재생성
                        // 단순 로드/조회는 알림 재생성 불필요
                        return
                    } else {
                        print("⚠️ 메인 파일 데이터 무결성 검증 실패, 백업에서 복구 시도")
                    }
                } catch {
                    print("⚠️ 메인 파일 로드 실패: \(error), 백업에서 복구 시도")
                }
            }

            // 2. 백업 파일에서 로드 시도
            if fileManager.fileExists(atPath: backupFileURL.path) {
                do {
                    let backupData = try Data(contentsOf: backupFileURL)
                    let allBackupShapes = try decoder.decode([ShapeModel].self, from: backupData)

                    // 삭제된 도형들을 필터링 (deletedAt이 nil인 도형들만)
                    loadedShapes = allBackupShapes.filter { shape in
                        return shape.deletedAt == nil
                    }

                    // 중복 제거 (ID 기반)
                    let uniqueShapes = Array(Set(loadedShapes.map { $0.id })).compactMap { id in
                        loadedShapes.first { $0.id == id }
                    }

                    if validateShapes(uniqueShapes) {
                        shapes = uniqueShapes
                        print("✅ 백업 파일에서 도형 데이터 복구 성공: \(shapes.count)개 (전체: \(allBackupShapes.count)개, 삭제됨: \(allBackupShapes.count - loadedShapes.count)개, 중복제거: \(loadedShapes.count - uniqueShapes.count)개)")

                        // 메인 파일을 백업으로 복구
                        saveShapesSecurely()

                        // 알림은 실제 데이터 변경시(추가/수정/삭제)에만 재생성
                        // 백업 복구는 예외적으로 알림 재생성 필요
                        SettingManager.shared.scheduleEndDateAlarms(for: shapes)
                        return
                    } else {
                        print("❌ 백업 파일도 손상됨")
                    }
                } catch {
                    print("❌ 백업 파일 로드 실패: \(error)")
                }
            }

            // 3. 모든 파일이 실패하면 빈 배열로 시작
            shapes = []
            print("📁 파일이 없거나 손상되어 빈 배열로 시작")
            saveShapesSecurely()

        } catch {
            print("❌ 전체 로드 프로세스 실패: \(error)")
            shapes = []
        }
    }
    
    public func saveShapes() {
        saveShapesSecurely()
    }
    
    /// 안전한 도형 데이터 저장 (원자성 보장)
    private func saveShapesSecurely() {
        fileWriteQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 1. 현재 데이터를 임시 파일에 저장
                let data = try self.encoder.encode(self.shapes)
                try data.write(to: self.tempFileURL)
                
                // 2. 임시 파일 검증
                let verifyData = try Data(contentsOf: self.tempFileURL)
                let verifyShapes = try self.decoder.decode([ShapeModel].self, from: verifyData)
                
                if !self.validateShapes(verifyShapes) || verifyShapes.count != self.shapes.count {
                    throw ShapeFileError.dataCorruption
                }
                
                // 3. 기존 메인 파일을 백업으로 이동 (존재하는 경우)
                if self.fileManager.fileExists(atPath: self.shapesFileURL.path) {
                    // 기존 백업 삭제
                    if self.fileManager.fileExists(atPath: self.backupFileURL.path) {
                        try self.fileManager.removeItem(at: self.backupFileURL)
                    }
                    // 메인 파일을 백업으로 이동
                    try self.fileManager.moveItem(at: self.shapesFileURL, to: self.backupFileURL)
                }
                
                // 4. 임시 파일을 메인 파일로 이동
                try self.fileManager.moveItem(at: self.tempFileURL, to: self.shapesFileURL)
                
                print("💾 도형 데이터 안전 저장 성공: \(self.shapes.count)개")
                
            } catch {
                print("❌ 도형 데이터 저장 실패: \(error)")
                
                // 실패 시 임시 파일 정리
                if self.fileManager.fileExists(atPath: self.tempFileURL.path) {
                    try? self.fileManager.removeItem(at: self.tempFileURL)
                }
                
                // 백업에서 메인 파일 복구 시도
                self.restoreFromBackup()
            }
        }
    }
    
    /// 백업에서 메인 파일 복구
    private func restoreFromBackup() {
        do {
            if fileManager.fileExists(atPath: backupFileURL.path) &&
               !fileManager.fileExists(atPath: shapesFileURL.path) {
                try fileManager.copyItem(at: backupFileURL, to: shapesFileURL)
                print("✅ 백업에서 메인 파일 복구 완료")
            }
        } catch {
            print("❌ 백업 복구 실패: \(error)")
        }
    }
    
    /// 도형 데이터 무결성 검증
    private func validateShapes(_ shapes: [ShapeModel]) -> Bool {
        // 1. 기본 검증
        guard !shapes.isEmpty || self.shapes.isEmpty else { return true }
        
        // 2. 각 도형의 필수 필드 검증
        for shape in shapes {
            // ID 검증
            if shape.id.uuidString.isEmpty {
                return false
            }
            
            // 제목 검증
            if shape.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            
            // 좌표 검증
            if !isValidCoordinate(shape.baseCoordinate) {
                return false
            }
            
            // 도형 타입별 검증
            switch shape.shapeType {
            case .circle:
                if let radius = shape.radius, radius <= 0 {
                    return false
                }
            case .rectangle:
                if let secondCoord = shape.secondCoordinate,
                   !isValidCoordinate(secondCoord) {
                    return false
                }
            case .polygon:
                if let coords = shape.polygonCoordinates {
                    if coords.count < 3 || !coords.allSatisfy(isValidCoordinate) {
                        return false
                    }
                }
            case .polyline:
                if let coords = shape.polylineCoordinates {
                    if coords.count < 2 || !coords.allSatisfy(isValidCoordinate) {
                        return false
                    }
                }
            }
        }
        
        // 3. 중복 ID 검증
        let uniqueIds = Set(shapes.map { $0.id })
        if uniqueIds.count != shapes.count {
            return false
        }
        
        return true
    }
    
    /// 좌표 유효성 검증
    private func isValidCoordinate(_ coordinate: CoordinateManager) -> Bool {
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
    }
    
    public func addShape(_ shape: ShapeModel) {
        var s = shape
        s.updatedAt = Date()
        shapes.append(s)
        saveShapes()
        // NotificationCenter.default.post(name: .shapesDidChange, object: nil) // 중복 방지를 위해 제거
        
        // 로컬 변경 사항 추적
        UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
        print("✅ 도형 추가 완료 및 로컬 변경 추적 기록")
        
        // Firebase 백업은 ShapeRepository에서 처리하므로 여기서는 제거
    }
    
    public func removeShape(id: UUID) {
        // soft delete: 도형을 완전히 제거하지 않고 deletedAt 필드만 설정
        if let index = shapes.firstIndex(where: { $0.id == id }) {
            // 1. 메모리에서 도형을 완전히 제거 (UI 즉시 반영)
            shapes.remove(at: index)
            
            // 2. 파일에서 모든 도형을 로드하여 해당 도형에 deletedAt 설정
            do {
                if fileManager.fileExists(atPath: shapesFileURL.path) {
                    let data = try Data(contentsOf: shapesFileURL)
                    var allShapes = try decoder.decode([ShapeModel].self, from: data)
                    
                    // 해당 도형에 deletedAt 설정
                    if let fileIndex = allShapes.firstIndex(where: { $0.id == id }) {
                        let now = Date()
                        allShapes[fileIndex].deletedAt = now
                        allShapes[fileIndex].updatedAt = now
                        
                        // 파일에 직접 저장
                        let newData = try encoder.encode(allShapes)
                        try newData.write(to: shapesFileURL)
                        
                        print("✅ 로컬에서 도형 soft delete 완료: \(id)")
                    }
                }
            } catch {
                print("❌ 로컬 soft delete 실패: \(error)")
            }
            
            // 로컬 변경 사항 추적
            UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
            print("✅ 도형 삭제 완료 및 로컬 변경 추적 기록")
            
            // Firebase 백업은 ShapeRepository에서 처리하므로 여기서는 제거
        }
    }
    
    public func updateAllShapesColor(to newColor: String) {
        do {
            // 1. 파일에서 도형 전체 불러오기
            let data = try Data(contentsOf: shapesFileURL)
            var loadedShapes = try decoder.decode([ShapeModel].self, from: data)
            // 2. 모든 도형의 color 필드 변경
            for i in 0..<loadedShapes.count {
                loadedShapes[i].color = newColor
            }
            // 3. 파일에 저장
            let newData = try encoder.encode(loadedShapes)
            try newData.write(to: shapesFileURL)
            // 4. 메모리의 shapes도 동기화 (여기서 @Published가 UI에 반영)
            self.shapes = loadedShapes.filter { $0.deletedAt == nil }
            
            // 5. 로컬 변경 사항 추적
            UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
            print("✅ 모든 도형 색상 변경 완료 및 로컬 변경 추적 기록")
            
            // 6. UI 즉시 업데이트를 위한 알림 전송
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .shapesDidChange, object: nil)
                NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
            }
            
            // 실시간 백업이 활성화된 경우 Firebase에도 즉시 반영
            if AppleLoginManager.shared.isLogin && SettingManager.shared.isCloudBackupEnabled {
                Task {
                    do {
                        // 모든 활성 도형을 Firebase에 업로드
                        let activeShapes = loadedShapes.filter { $0.deletedAt == nil }
                        try await ShapeFirebaseStore.shared.saveShapes(activeShapes)
                        print("✅ 실시간 백업 성공: 모든 도형 색상 변경 (\(activeShapes.count)개)")
                        
                        // 백업 시간 업데이트
                        await MainActor.run {
                            UserDefaults.standard.set(Date(), forKey: "lastBackupTime")
                        }
                    } catch {
                        print("❌ 실시간 백업 실패: 모든 도형 색상 변경 - \(error.localizedDescription)")
                        // 백업 실패 시에도 로컬 데이터는 유지 (사용자 경험 보호)
                    }
                }
            } else {
                print("📝 실시간 백업 비활성화: 로그인 상태 또는 클라우드 백업 설정")
            }
        } catch {
            print("모든 도형 색상 일괄 변경 실패: \(error)")
        }
    }
    
    public func updateShape(_ shape: ShapeModel) {
        if let idx = shapes.firstIndex(where: { $0.id == shape.id }) {
            var newShapes = shapes
            var updated = shape
            updated.updatedAt = Date()
            newShapes[idx] = updated
            shapes = newShapes // 배열 자체를 새로 할당해야 @Published가 동작
            saveShapes()
            // NotificationCenter.default.post(name: .shapesDidChange, object: nil) // 중복 방지를 위해 제거
            
            // 로컬 변경 사항 추적
            UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
            print("✅ 도형 수정 완료 및 로컬 변경 추적 기록")
            
            // Firebase 백업은 ShapeRepository에서 처리하므로 여기서는 제거
        }
    }
    
    public func deleteExpiredShapes() {
        // 만료된 도형들을 찾아서 soft delete 수행
        let expiredShapes = shapes.filter { $0.isExpired }
        
        // 1. 메모리에서 만료된 도형들을 제거 (UI 즉시 반영)
        self.shapes = shapes.filter { !$0.isExpired }
        
        // 2. 파일에서 모든 도형을 로드하여 만료된 도형들에 deletedAt 설정
        do {
            if fileManager.fileExists(atPath: shapesFileURL.path) {
                let data = try Data(contentsOf: shapesFileURL)
                var allShapes = try decoder.decode([ShapeModel].self, from: data)
                
                // 만료된 도형들에 deletedAt 설정
                for expiredShape in expiredShapes {
                    if let fileIndex = allShapes.firstIndex(where: { $0.id == expiredShape.id }) {
                        let now = Date()
                        allShapes[fileIndex].deletedAt = now
                        allShapes[fileIndex].updatedAt = now
                        print("✅ 만료된 도형 soft delete 완료: \(expiredShape.id)")
                    }
                }
                
                // 파일에 저장
                let newData = try encoder.encode(allShapes)
                try newData.write(to: shapesFileURL)
                
                print("✅ 만료된 도형들 soft delete 완료: \(expiredShapes.count)개")
            }
        } catch {
            print("❌ 만료된 도형들 soft delete 실패: \(error)")
        }
        
        // 로컬 변경 사항 추적
        UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
        print("✅ 만료된 도형 삭제 완료 및 로컬 변경 추적 기록")
        
        // Firebase 백업은 ShapeRepository에서 처리하므로 여기서는 제거
    }
    
    
    public func clearAllData() {
        shapes.removeAll()
        saveShapes()
        // NotificationCenter.default.post(name: .shapesDidChange, object: nil) // 중복 방지를 위해 제거
        print("🗑️ 모든 데이터 삭제 완료")
        
        // 로컬 변경 사항 추적
        UserDefaults.standard.set(Date(), forKey: "lastLocalModificationTime")
        print("✅ 모든 데이터 삭제 완료 및 로컬 변경 추적 기록")
        
        // Firebase 백업은 ShapeRepository에서 처리하므로 여기서는 제거
    }
}

extension ShapeFileStore {
    /// 저장된 모든 도형의 색상을 새로운 색상(hex)으로 변경하고 저장/갱신

    /// 특정 id의 도형을 반환
    func getShape(id: UUID) -> ShapeModel? {
        return shapes.first(where: { $0.id == id })
    }
    
    /// 삭제된 도형을 포함한 모든 도형 데이터를 파일에서 직접 로드
    func getAllShapesIncludingDeleted() -> [ShapeModel] {
        do {
            if fileManager.fileExists(atPath: shapesFileURL.path) {
                let data = try Data(contentsOf: shapesFileURL)
                let allShapes = try decoder.decode([ShapeModel].self, from: data)
                print("📁 파일에서 모든 도형 로드: \(allShapes.count)개 (삭제된 도형 포함)")
                return allShapes
            } else {
                print("📁 도형 데이터 파일이 없습니다.")
                return []
            }
        } catch {
            print("❌ 삭제된 도형 포함 전체 데이터 로드 실패: \(error)")
            return []
        }
    }
}

// MARK: - ShapeFile Error
enum ShapeFileError: LocalizedError {
    case dataCorruption
    case fileAccessDenied
    case diskSpaceInsufficient
    case saveFailed(underlying: Error)
    case loadFailed(underlying: Error)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .dataCorruption:
            return "데이터가 손상되었습니다."
        case .fileAccessDenied:
            return "파일 접근이 거부되었습니다."
        case .diskSpaceInsufficient:
            return "디스크 공간이 부족합니다."
        case .saveFailed(let error):
            return "저장 실패: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "불러오기 실패: \(error.localizedDescription)"
        case .encodingFailed:
            return "데이터 인코딩에 실패했습니다."
        case .decodingFailed:
            return "데이터 디코딩에 실패했습니다."
        }
    }
}

// MARK: - ShapeStoreProtocol Implementation
extension ShapeFileStore: ShapeStoreProtocol {
    typealias ShapeType = ShapeModel
    
    func loadShapes() async throws -> [ShapeModel] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: self.shapes)
            }
        }
    }
    
    func saveShapes(_ shapes: [ShapeModel]) async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.shapes = shapes
                self.saveShapesSecurely()
                continuation.resume()
            }
        }
    }
    
    func addShape(_ shape: ShapeModel) async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.addShape(shape)
                continuation.resume()
            }
        }
    }
    
    func removeShape(id: UUID) async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.removeShape(id: id)
                continuation.resume()
            }
        }
    }
    
    func updateShape(_ shape: ShapeModel) async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.updateShape(shape)
                continuation.resume()
            }
        }
    }
    
    func deleteExpiredShapes() async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.deleteExpiredShapes()
                continuation.resume()
            }
        }
    }
}

