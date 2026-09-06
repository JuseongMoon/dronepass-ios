//
//  VWorldAPIManager.swift
//  DronePass
//
//  VWorld API 통신 관리
//

import Foundation
import CoreLocation
import Combine

/// VWorld API를 사용한 드론 비행 구역 정보 관리
final class VWorldAPIManager: ObservableObject {
    static let shared = VWorldAPIManager()

    // MARK: - Published Properties

    /// 로딩 상태
    @Published var isLoading: Bool = false

    /// 에러 메시지
    @Published var errorMessage: String?

    /// 마지막 업데이트 시간
    @Published var lastUpdateTime: Date?

    /// 현재 로드된 구역 데이터
    @Published var loadedZones: [FlightZoneLayer: [DroneZoneFeature]] = [:]

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    /// 캐시 (같은 bbox+layer 조합을 재요청하지 않도록)
    private var cache: [String: [DroneZoneFeature]] = [:]

    /// 캐시 만료 시간 (15분)
    private let cacheExpirationInterval: TimeInterval = 15 * 60

    /// 캐시 생성 시간 기록
    private var cacheTimestamps: [String: Date] = [:]

    /// 캐시 최대 개수 (메모리 제한)
    /// 🔧 메모리 최적화: 100개 → 50개로 축소 (화면 밖 오버레이 제거로 캐시 의존도 감소)
    private let maxCacheSize: Int = 50

    /// Debounce 타이머 (지도 이동 시 너무 자주 호출 방지)
    private var debounceTimer: Timer?

    /// 캐시 정리 타이머
    private var cacheCleanupTimer: Timer?

    private init() {
        print("✅ VWorldAPIManager 초기화")

        // 🔧 메모리 최적화: 5분마다 만료된 캐시 자동 정리
        startCacheCleanupTimer()
    }

    deinit {
        // 타이머 정리
        debounceTimer?.invalidate()
        cacheCleanupTimer?.invalidate()
        print("♻️ VWorldAPIManager 메모리 해제")
    }

    // MARK: - Public Methods

    /// 특정 레이어의 드론 구역 데이터 가져오기
    /// - Parameters:
    ///   - layer: 가져올 레이어 타입
    ///   - bbox: Bounding Box (minLon, minLat, maxLon, maxLat) - WGS84
    ///   - forceRefresh: 캐시 무시하고 강제 새로고침
    @MainActor
    func fetchFlightZones(
        layer: FlightZoneLayer,
        bbox: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double),
        forceRefresh: Bool = false
    ) async throws -> [DroneZoneFeature] {

        // 캐시 키 생성
        let cacheKey = "\(layer.rawValue)_\(bbox.minLon)_\(bbox.minLat)_\(bbox.maxLon)_\(bbox.maxLat)"

        // 캐시 확인 (만료되지 않았고, 강제 새로고침이 아닌 경우)
        if !forceRefresh,
           let cached = cache[cacheKey],
           let timestamp = cacheTimestamps[cacheKey],
           Date().timeIntervalSince(timestamp) < cacheExpirationInterval {
            print("📦 VWorld 캐시 사용: \(layer.displayName)")
            return cached
        }

        // BBOX 문자열 생성 (WGS84 좌표 그대로 사용: minLon,minLat,maxLon,maxLat)
        let bboxString = "\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat)"

        // WFS 요청 파라미터 생성
        let wfsRequest = VWorldWFSRequest(typename: layer.rawValue, bbox: bboxString)

        // URL 생성
        var components = URLComponents(string: VWorldAPIConfig.baseURL)
        components?.queryItems = wfsRequest.toQueryItems()

        guard let url = components?.url else {
            throw VWorldAPIError.invalidURL
        }

        print("🌐 VWorld API 요청: \(layer.displayName)")
        print("   URL: \(url.absoluteString)")

        // API 호출
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // HTTP 응답 확인
            if let httpResponse = response as? HTTPURLResponse {
                print("   응답 코드: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 429 {
                    throw VWorldAPIError.rateLimitExceeded
                } else if httpResponse.statusCode != 200 {
                    throw VWorldAPIError.networkError(
                        NSError(domain: "VWorld", code: httpResponse.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                    )
                }
            }

            // 🔍 응답 데이터 로깅 (디버깅용)
            if let responseString = String(data: data, encoding: .utf8) {
                let preview = String(responseString.prefix(500))  // 처음 500자만
                print("   📥 API 응답 미리보기:")
                print(preview)
                print("   ---")

                // HTML/XML 오류 확인
                if responseString.contains("<!DOCTYPE") || responseString.contains("<html") {
                    print("   ⚠️ VWorld API가 HTML 페이지를 반환했습니다 (인증 오류 가능성)")
                    print("   → API 키가 활성화되지 않았거나 권한이 없을 수 있습니다")
                } else if responseString.contains("<?xml") {
                    print("   ⚠️ VWorld API가 XML을 반환했습니다 (OGC 오류 메시지 가능성)")
                    if responseString.contains("ExceptionReport") {
                        print("   → OGC WFS 예외 발생 - XML 내용을 확인하세요")
                    }
                }
            }

            // JSON 파싱
            let decoder = JSONDecoder()
            let featureCollection = try decoder.decode(GeoJSONFeatureCollection.self, from: data)

            // DroneZoneFeature로 변환
            let features = featureCollection.features.map { geoFeature in
                DroneZoneFeature(from: geoFeature, layer: layer)
            }

            print("   ✅ \(features.count)개 구역 로드됨")

            // 🔧 메모리 최적화: 캐시 저장 전 크기 체크
            saveToCacheWithSizeLimit(key: cacheKey, features: features)

            // 로드된 데이터 업데이트
            loadedZones[layer] = features
            lastUpdateTime = Date()

            return features

        } catch let error as DecodingError {
            print("   ❌ JSON 파싱 오류: \(error)")
            throw VWorldAPIError.decodingError(error)
        } catch {
            print("   ❌ 네트워크 오류: \(error.localizedDescription)")
            throw VWorldAPIError.networkError(error)
        }
    }

    /// 여러 레이어의 데이터를 동시에 가져오기 (우선순위 기반 점진적 로딩)
    /// - Parameters:
    ///   - layers: 가져올 레이어 배열
    ///   - bbox: Bounding Box
    ///   - forceRefresh: 캐시 무시
    ///   - onLayerLoaded: 각 레이어가 로드될 때마다 호출되는 콜백 (선택적)
    @MainActor
    func fetchMultipleLayers(
        layers: [FlightZoneLayer],
        bbox: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double),
        forceRefresh: Bool = false,
        onLayerLoaded: ((FlightZoneLayer, [DroneZoneFeature]) -> Void)? = nil
    ) async -> [FlightZoneLayer: [DroneZoneFeature]] {

        isLoading = true
        errorMessage = nil

        var results: [FlightZoneLayer: [DroneZoneFeature]] = [:]

        // 우선순위 순으로 정렬 (loadingPriority가 낮을수록 먼저)
        let sortedLayers = layers.sorted { $0.loadingPriority < $1.loadingPriority }

        // 병렬 요청 (우선순위 순으로 시작)
        await withTaskGroup(of: (FlightZoneLayer, Result<[DroneZoneFeature], Error>).self) { group in
            for layer in sortedLayers {
                group.addTask {
                    do {
                        let features = try await self.fetchFlightZones(
                            layer: layer,
                            bbox: bbox,
                            forceRefresh: forceRefresh
                        )
                        return (layer, .success(features))
                    } catch {
                        print("⚠️ \(layer.displayName) 로드 실패: \(error.localizedDescription)")
                        return (layer, .failure(error))
                    }
                }
            }

            // 완료되는 즉시 처리 (우선순위 순서대로 Task 추가했으므로 대체로 우선순위대로 완료됨)
            for await (layer, result) in group {
                switch result {
                case .success(let features):
                    results[layer] = features
                    print("✅ \(layer.displayName) 로드 완료 (\(features.count)개 구역)")

                    // 콜백 호출 - 즉시 UI에 표시 가능
                    onLayerLoaded?(layer, features)

                case .failure(let error):
                    // 에러는 로그만 남기고 계속 진행
                    print("⚠️ \(layer.displayName) 에러: \(error.localizedDescription)")
                }
            }
        }

        isLoading = false
        print("✅ VWorld 데이터 로드 완료: \(results.count)/\(layers.count)개 레이어")

        return results
    }

    /// 캐시 클리어
    func clearCache() {
        cache.removeAll()
        cacheTimestamps.removeAll()
        print("🗑️ VWorld 캐시 삭제됨")
    }

    /// 특정 레이어의 캐시만 삭제
    func clearCache(for layer: FlightZoneLayer) {
        let keysToRemove = cache.keys.filter { $0.hasPrefix(layer.rawValue) }
        keysToRemove.forEach { key in
            cache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
        print("🗑️ VWorld 캐시 삭제됨: \(layer.displayName)")
    }

    /// Debounce를 적용한 데이터 로드 (지도 이동 시 사용)
    /// - Parameters:
    ///   - layers: 가져올 레이어 배열
    ///   - bbox: Bounding Box
    ///   - delay: Debounce 지연 시간 (초)
    @MainActor
    func fetchWithDebounce(
        layers: [FlightZoneLayer],
        bbox: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double),
        delay: TimeInterval = 0.5
    ) {
        // 기존 타이머 취소
        debounceTimer?.invalidate()

        // 새 타이머 시작
        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { [weak self] in
                guard let self = self else { return }
                _ = await self.fetchMultipleLayers(layers: layers, bbox: bbox)
            }
        }
    }

    // MARK: - Private Cache Management

    /// 🔧 메모리 최적화: 캐시 크기 제한과 함께 저장
    private func saveToCacheWithSizeLimit(key: String, features: [DroneZoneFeature]) {
        // 캐시 크기가 최대치를 초과하면 가장 오래된 항목부터 제거 (LRU)
        if cache.count >= maxCacheSize {
            removeOldestCacheItems(count: maxCacheSize / 4) // 25% 제거
        }

        cache[key] = features
        cacheTimestamps[key] = Date()
    }

    /// 🔧 메모리 최적화: 가장 오래된 캐시 항목 제거 (LRU)
    private func removeOldestCacheItems(count: Int) {
        // 타임스탬프 기준으로 정렬하여 가장 오래된 항목 찾기
        let sortedKeys = cacheTimestamps.sorted { $0.value < $1.value }
            .prefix(count)
            .map { $0.key }

        var removedCount = 0
        for key in sortedKeys {
            cache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
            removedCount += 1
        }

        if removedCount > 0 {
            print("♻️ VWorld 캐시 정리: \(removedCount)개 오래된 항목 제거 (남은 캐시: \(cache.count)개)")
        }
    }

    /// 🔧 메모리 최적화: 만료된 캐시 항목 제거
    private func removeExpiredCacheItems() {
        let now = Date()
        var expiredKeys: [String] = []

        for (key, timestamp) in cacheTimestamps {
            if now.timeIntervalSince(timestamp) >= cacheExpirationInterval {
                expiredKeys.append(key)
            }
        }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            print("♻️ VWorld 캐시 정리: \(expiredKeys.count)개 만료된 항목 제거 (남은 캐시: \(cache.count)개)")
        }
    }

    /// 🔧 메모리 최적화: 자동 캐시 정리 타이머 시작
    private func startCacheCleanupTimer() {
        // 5분마다 만료된 캐시 정리
        cacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.removeExpiredCacheItems()
        }
    }
}

// MARK: - Helper Extensions

extension VWorldAPIManager {
    /// 전체 레이어 수
    var totalLayersCount: Int {
        return FlightZoneLayer.allCases.count
    }

    /// 로드된 레이어 수
    var loadedLayersCount: Int {
        return loadedZones.keys.count
    }

    /// 전체 구역 개수
    var totalZonesCount: Int {
        return loadedZones.values.reduce(0) { $0 + $1.count }
    }

    /// 특정 레이어의 구역 개수
    func zonesCount(for layer: FlightZoneLayer) -> Int {
        return loadedZones[layer]?.count ?? 0
    }
}

// MARK: - VWorld 공공기관 연락처 매니저

/// VWorld 구역의 공공기관 연락처 관리 매니저
final class VWorldContactManager: ObservableObject {
    static let shared = VWorldContactManager()

    // MARK: - Published Properties

    /// 기관명 → 연락처 정보 매핑
    @Published var contacts: [String: PublicContactInfo] = [:]

    /// 로딩 상태
    @Published var isLoading = false

    // MARK: - Private Properties

    /// S3 연락처 파일 URL
    private let contactsURL = "https://sciencefiction.co.kr/dronepass/vworld-contacts.txt"

    /// 캐시 저장을 위한 UserDefaults 키
    private let cacheKey = "vworld_contacts_cache"
    private let lastFetchKey = "vworld_contacts_last_fetch"

    /// 캐시 유효 기간 (15일)
    private let cacheValidDays = 5

    // MARK: - Initialization

    private init() {
        print("✅ VWorldContactManager 초기화")
    }

    // MARK: - Public Methods

    /// S3에서 연락처 데이터 로드 (15일 캐싱 지원)
    func fetchContacts() async {
        await MainActor.run {
            isLoading = true
        }

        defer {
            Task {
                await MainActor.run {
                    isLoading = false
                }
            }
        }

        // 1. 캐시 확인 (5일 이내면 캐시 사용)
        if let cachedContacts = loadFromCache(), isCacheValid() {
            await MainActor.run {
                self.contacts = cachedContacts
                print("✅ 캐시된 연락처 사용: \(cachedContacts.count)개 기관 (S3 요청 생략)")
            }
            return
        }

        // 2. 캐시가 없거나 만료됨 → S3에서 다운로드
        print("🌐 S3에서 연락처 데이터 다운로드 시도...")
        guard let url = URL(string: contactsURL) else {
            print("❌ Invalid contacts URL")
            // URL이 잘못되었으면 기존 캐시라도 사용
            if let cachedContacts = loadFromCache() {
                await MainActor.run {
                    self.contacts = cachedContacts
                    print("⚠️ URL 오류로 만료된 캐시 사용: \(cachedContacts.count)개 기관")
                }
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else {
                print("❌ Failed to decode contacts data")
                // 디코딩 실패 시 기존 캐시 사용
                if let cachedContacts = loadFromCache() {
                    await MainActor.run {
                        self.contacts = cachedContacts
                        print("⚠️ 디코딩 실패로 만료된 캐시 사용: \(cachedContacts.count)개 기관")
                    }
                }
                return
            }

            // 3. 다운로드 성공 → 파싱 후 캐시에 저장
            let parsedContacts = parseContacts(content: content)
            saveToCache(parsedContacts)  // 디스크에 저장

            await MainActor.run {
                self.contacts = parsedContacts
                print("✅ S3에서 연락처 데이터 로드 완료: \(parsedContacts.count)개 기관")
            }
        } catch {
            print("❌ S3 다운로드 실패: \(error)")
            // 네트워크 오류 시 기존 캐시 사용 (오프라인 지원)
            if let cachedContacts = loadFromCache() {
                await MainActor.run {
                    self.contacts = cachedContacts
                    print("⚠️ 오프라인: 만료된 캐시 사용 (\(cachedContacts.count)개 기관)")
                }
            }
        }
    }

    /// 구역명으로 연락처 찾기 (부분 일치)
    /// - Parameter zoneName: 구역 이름 (예: "경복궁", "설악산")
    /// - Returns: 일치하는 연락처 정보
    func findContact(for zoneName: String) -> PublicContactInfo? {
        // 정확히 일치하는 기관명 찾기
        if let exactMatch = contacts[zoneName] {
            return exactMatch
        }

        // 부분 일치 검색
        for (orgName, contactInfo) in contacts {
            // 구역명에 기관명이 포함되어 있거나, 기관명에 구역명이 포함되어 있으면
            if zoneName.contains(orgName) || orgName.contains(zoneName) {
                return contactInfo
            }
        }

        return nil
    }

    // MARK: - Private Methods

    /// UserDefaults에서 캐시된 연락처 데이터 로드
    /// - Returns: 캐시된 연락처 딕셔너리 (없으면 nil)
    private func loadFromCache() -> [String: PublicContactInfo]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            print("📦 캐시된 연락처 데이터 없음")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let contactsArray = try decoder.decode([PublicContactInfo].self, from: data)
            // 중복 기관명 방어: uniqueKeysWithValues는 중복 키에서 크래시하므로 마지막 값 우선으로 병합
            let contactsDict = Dictionary(contactsArray.map { ($0.organizationName, $0) }, uniquingKeysWith: { _, latest in latest })
            print("✅ 캐시에서 연락처 로드: \(contactsDict.count)개 기관")
            return contactsDict
        } catch {
            print("❌ 캐시 디코딩 실패: \(error)")
            return nil
        }
    }

    /// UserDefaults에 연락처 데이터 저장
    /// - Parameter contacts: 저장할 연락처 딕셔너리
    private func saveToCache(_ contacts: [String: PublicContactInfo]) {
        do {
            let encoder = JSONEncoder()
            let contactsArray = Array(contacts.values)
            let data = try encoder.encode(contactsArray)
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: lastFetchKey)
            print("💾 연락처 캐시 저장 완료: \(contacts.count)개 기관")
        } catch {
            print("❌ 캐시 저장 실패: \(error)")
        }
    }

    /// 캐시가 유효한지 확인 (15일 이내)
    /// - Returns: 유효하면 true, 만료되었거나 없으면 false
    private func isCacheValid() -> Bool {
        guard let lastFetchDate = UserDefaults.standard.object(forKey: lastFetchKey) as? Date else {
            print("📦 마지막 업데이트 시간 없음")
            return false
        }

        let daysSinceLastFetch = Calendar.current.dateComponents([.day], from: lastFetchDate, to: Date()).day ?? Int.max
        let isValid = daysSinceLastFetch < cacheValidDays

        if isValid {
            print("✅ 캐시 유효: \(daysSinceLastFetch)일 경과 (15일 이내)")
        } else {
            print("⏰ 캐시 만료: \(daysSinceLastFetch)일 경과 (15일 초과)")
        }

        return isValid
    }

    /// 텍스트 파일 파싱
    /// - Parameter content: S3에서 다운로드한 텍스트 내용
    /// - Returns: 기관명 → 연락처 매핑
    private func parseContacts(content: String) -> [String: PublicContactInfo] {
        var contactsDict: [String: PublicContactInfo] = [:]

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") } // 빈 줄과 주석 제거

        var i = 0
        while i < lines.count {
            let organizationName = lines[i]

            // 다음 줄이 전화번호인지 확인
            guard i + 1 < lines.count else {
                i += 1
                continue
            }

            let phoneNumber = lines[i + 1]

            // 전화번호 형식 검증 (숫자, 하이픈, 괄호만 허용)
            let phonePattern = "^[0-9\\-()]+$"
            if let _ = phoneNumber.range(of: phonePattern, options: .regularExpression) {
                let contact = PublicContactInfo(
                    organizationName: organizationName,
                    phoneNumber: phoneNumber
                )
                contactsDict[organizationName] = contact
                i += 2 // 기관명과 전화번호 모두 처리했으므로 2칸 이동
            } else {
                i += 1
            }
        }

        return contactsDict
    }
}
