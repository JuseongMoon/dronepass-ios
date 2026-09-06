//
//  SketchPointsCache.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 스무딩 포인트 LRU 캐시
// 연관기능: SketchModel → 렌더링 시 스무딩 포인트 캐싱

import Foundation

/// 스케치 스무딩 포인트 LRU 캐시
/// 메모리 효율성을 위해 최근 사용된 스케치의 스무딩 포인트만 캐싱
/// Thread-safe: NSLock 사용
final class SketchPointsCache {
    static let shared = SketchPointsCache()

    /// 동기화용 락
    private let lock = NSLock()

    /// 캐시 저장소: [스케치 ID: 스무딩된 포인트]
    private var cache: [UUID: [CoordinateManager]] = [:]

    /// 접근 순서 추적 (LRU 구현용)
    private var accessOrder: [UUID] = []

    /// 최대 캐시 크기 (100개 스케치)
    private let maxCacheSize = 100

    private init() {}

    // MARK: - Public Methods

    /// 스무딩된 포인트 조회 (캐시 또는 계산)
    /// - Parameter sketch: 원본 스케치
    /// - Returns: 스무딩된 좌표 배열
    func getSmoothedPoints(for sketch: SketchModel) -> [CoordinateManager] {
        // 포인트가 2개 미만이면 원본 반환 (스무딩 불필요)
        guard sketch.points.count >= 2 else { return sketch.points }

        lock.lock()
        defer { lock.unlock() }

        // 캐시에서 조회
        if let cached = cache[sketch.id] {
            updateAccessOrderUnsafe(sketch.id)
            return cached
        }

        // 캐시 미스: 스무딩 계산 후 캐싱
        let smoothed = SketchSmoothingAlgorithm.smoothUsingCatmullRom(sketch.points)
        setCacheUnsafe(sketch.id, points: smoothed)
        return smoothed
    }

    /// 특정 스케치의 캐시 무효화
    /// - Parameter id: 스케치 ID
    func invalidate(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: id)
        accessOrder.removeAll { $0 == id }
    }

    /// 전체 캐시 초기화
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        accessOrder.removeAll()
        print("🗑️ 스케치 포인트 캐시 전체 초기화")
    }

    /// 현재 캐시 크기
    var cacheSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    // MARK: - Private Methods (Lock 보유 상태에서 호출)

    /// 캐시에 저장 (LRU 제거 적용) - 락 보유 상태에서 호출
    private func setCacheUnsafe(_ id: UUID, points: [CoordinateManager]) {
        // 캐시 용량 초과 시 가장 오래된 항목 제거
        if cache.count >= maxCacheSize {
            evictLRUUnsafe()
        }

        cache[id] = points
        accessOrder.append(id)
    }

    /// 접근 순서 업데이트 (최근 사용으로 이동) - 락 보유 상태에서 호출
    private func updateAccessOrderUnsafe(_ id: UUID) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    /// 가장 오래된 캐시 항목 제거 (LRU) - 락 보유 상태에서 호출
    private func evictLRUUnsafe() {
        guard let oldest = accessOrder.first else { return }
        cache.removeValue(forKey: oldest)
        accessOrder.removeFirst()
    }
}
