//
//  FlightZoneOverlayManager.swift
//  DronePass
//
//  네이버 지도에 VWorld 드론 구역 오버레이 관리
//

import Foundation
import NMapsMap
import CoreLocation
import SwiftUI

/// 네이버 지도 위에 드론 비행 구역 오버레이를 표시하는 매니저
final class FlightZoneOverlayManager: ObservableObject {

    // MARK: - Published Properties

    /// 현재 표시 중인 레이어들
    @Published var visibleLayers: Set<FlightZoneLayer> = []

    /// 오버레이 표시 여부 (전체 토글)
    @Published var isOverlayVisible: Bool = false

    /// 현재 표시된 오버레이 개수
    @Published var overlayCount: Int = 0

    /// 레이어 로딩 중 상태
    @Published var isLoadingLayers: Bool = false

    // MARK: - Private Properties

    /// 네이버 지도 인스턴스
    private weak var mapView: NMFMapView?

    /// 오버레이 저장소 (레이어 → 오버레이 배열)
    private var overlays: [FlightZoneLayer: [NMFPolygonOverlay]] = [:]

    /// 오버레이 → Feature 매핑 (터치 이벤트 처리용)
    private var overlayFeatureMap: [NMFPolygonOverlay: DroneZoneFeature] = [:]

    /// 현재 선택된 오버레이 (외곽선 강조용)
    private var selectedOverlay: NMFPolygonOverlay? {
        didSet {
            // 이전 오버레이 외곽선 복원
            if let old = oldValue {
                old.outlineWidth = 2
            }
            // 새 오버레이 외곽선 강조
            if let new = selectedOverlay {
                new.outlineWidth = 4
            }
        }
    }

    /// VWorld API 매니저
    private let apiManager = VWorldAPIManager.shared

    /// 비행 구역 계산기
    private let calculator = FlightZoneCalculator()

    /// 오버레이 터치 콜백
    var onOverlayTapped: ((DroneZoneFeature) -> Void)?

    /// Debounce 타이머 (지도 이동 시 너무 자주 호출 방지)
    private var debounceTimer: Timer?

    /// 각 레이어별로 로드된 Feature ID (zoneCode) 추적 (중복 방지용)
    private var loadedFeatures: [FlightZoneLayer: Set<String>] = [:]

    /// 진행 중인 Task 추적 (취소용)
    private var fetchTask: Task<Void, Never>?

    /// 스케치 모드 진입 전 표시 중이던 레이어 상태 저장
    private var savedVisibleLayers: Set<FlightZoneLayer>?

    /// 스케치 모드로 인해 일시적으로 숨겨진 상태
    @Published var isTemporarilyHidden: Bool = false

    // MARK: - Initialization

    init() {
        print("✅ FlightZoneOverlayManager 초기화")

        // Task로 래핑하여 View body 렌더링 사이클 외부에서 @Published 변경
        Task { @MainActor in
            loadVisibleLayersFromStorage()
        }

        // 🔧 메모리 최적화: 메모리 경고 감지
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        // 메모리 경고 옵저버 제거
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        // 타이머 정리
        debounceTimer?.invalidate()
        debounceTimer = nil

        // 진행 중인 Task 취소
        fetchTask?.cancel()
        fetchTask = nil

        // 모든 오버레이 제거
        for layer in FlightZoneLayer.allCases {
            removeOverlays(for: layer)
        }

        print("♻️ FlightZoneOverlayManager 메모리 해제")
    }

    // MARK: - Public Methods

    /// 지도 인스턴스 설정
    func setMapView(_ mapView: NMFMapView) {
        self.mapView = mapView
        print("✅ FlightZoneOverlayManager: 지도 설정됨")
    }

    /// 특정 레이어 표시/숨기기 토글
    /// - Parameter layer: 토글할 레이어
    @MainActor
    func toggleLayer(_ layer: FlightZoneLayer) {
        if visibleLayers.contains(layer) {
            // 레이어 숨기기
            // 1️⃣ 먼저 상태 변경 (Race condition 방지)
            visibleLayers.remove(layer)
            saveVisibleLayersToStorage()
            print("🔄 레이어 숨김 시작: \(layer.displayName)")

            // 2️⃣ 그 다음 UI에서 제거
            hideLayer(layer)
            print("✅ 레이어 숨김 완료: \(layer.displayName)")
        } else {
            // 레이어 표시하기
            visibleLayers.insert(layer)
            saveVisibleLayersToStorage()
            print("🔄 레이어 표시 시작: \(layer.displayName)")

            // 지도 영역의 데이터를 즉시 로드
            Task {
                guard let mapView = mapView else {
                    print("⚠️ 지도가 설정되지 않아 오버레이를 로드할 수 없습니다")
                    return
                }

                let bounds = mapView.coveringBounds
                let bbox = (
                    minLon: bounds.southWestLng,
                    minLat: bounds.southWestLat,
                    maxLon: bounds.northEastLng,
                    maxLat: bounds.northEastLat
                )

                print("📍 현재 지도 영역: \(bbox)")
                print("🌐 API 호출 시작: \(layer.displayName)")

                // 단일 레이어 로드
                do {
                    let features = try await apiManager.fetchFlightZones(layer: layer, bbox: bbox)
                    print("✅ API 응답: \(features.count)개 구역 수신")

                    // 오버레이 추가 전 스케치 모드 재확인
                    await MainActor.run {
                        guard !self.isTemporarilyHidden else {
                            print("⏭️ 스케치 모드로 인해 오버레이 추가 취소: \(layer.displayName)")
                            return
                        }
                        addOverlays(for: layer, features: features)
                        updateOverlayCount()
                        print("✅ 오버레이 추가 완료: 총 \(overlayCount)개 표시 중")
                    }
                } catch {
                    print("❌ API 호출 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 모든 레이어 표시
    @MainActor
    func showAllLayers() {
        visibleLayers = Set(FlightZoneLayer.allCases)
        Task {
            await refreshOverlays()
        }
        saveVisibleLayersToStorage()
        print("👁️ 모든 레이어 표시")
    }

    /// 모든 레이어 숨기기
    @MainActor
    func hideAllLayers() {
        for layer in FlightZoneLayer.allCases {
            hideLayer(layer)
        }
        visibleLayers.removeAll()
        saveVisibleLayersToStorage()
        print("🙈 모든 레이어 숨김")
    }

    /// 현재 지도 영역의 오버레이 새로고침
    @MainActor
    func refreshOverlays() async {
        guard let mapView = mapView else {
            print("⚠️ 지도가 설정되지 않음")
            return
        }

        guard !visibleLayers.isEmpty else {
            print("ℹ️ 표시할 레이어 없음")
            return
        }

        // 현재 지도 영역 가져오기
        let bounds = mapView.coveringBounds
        let bbox = (
            minLon: bounds.southWestLng,
            minLat: bounds.southWestLat,
            maxLon: bounds.northEastLng,
            maxLat: bounds.northEastLat
        )

        print("🗺️ 지도 영역 오버레이 새로고침 시작...")

        // 로딩 시작
        isLoadingLayers = true

        // API에서 데이터 가져오기 (우선순위 기반, 점진적 로딩)
        // addOverlays()에서 자동으로 중복 제거됨
        _ = await apiManager.fetchMultipleLayers(
            layers: Array(visibleLayers),
            bbox: bbox,
            onLayerLoaded: { [weak self] layer, features in
                guard let self = self else { return }
                // 각 레이어가 로드되는 즉시 지도에 표시 (중복 자동 제거)
                Task { @MainActor in
                    self.addOverlays(for: layer, features: features)
                    self.updateOverlayCount()
                    print("🎯 \(layer.displayName) 처리 완료 (우선순위 \(layer.loadingPriority)위)")
                }
            }
        )

        // 로딩 완료
        isLoadingLayers = false

        print("✅ 오버레이 새로고침 완료: \(overlayCount)개 표시됨")
    }

    /// 특정 좌표의 비행 가능 여부 확인
    func checkFlightPermission(at coordinate: CLLocationCoordinate2D) -> FlightPermissionResult {
        let zones = apiManager.loadedZones
        return calculator.checkFlightPermission(at: coordinate, zones: zones)
    }

    /// 특정 반경 내 구역 찾기
    func findNearbyZones(at coordinate: CLLocationCoordinate2D, radius: Double = 1000) -> [DroneZoneFeature] {
        let zones = apiManager.loadedZones
        return calculator.findZonesNearby(coordinate: coordinate, radius: radius, zones: zones)
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
        // 스케치 모드로 인해 일시 숨김 상태면 로드하지 않음
        guard !isTemporarilyHidden else { return }

        // 🔧 메모리 최적화: 이전 Task 취소
        fetchTask?.cancel()

        // 기존 타이머 취소
        debounceTimer?.invalidate()

        // 새 타이머 시작
        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // 🔧 새 Task 생성 및 추적
            self.fetchTask = Task { @MainActor in
                // ✅ 현재 visibleLayers 상태로 다시 필터링 (레이어 해제 후 재로딩 방지)
                let currentVisibleLayers = layers.filter { self.visibleLayers.contains($0) }

                // 표시할 레이어가 없으면 종료
                guard !currentVisibleLayers.isEmpty else {
                    print("ℹ️ Debounce: 표시할 레이어 없음")
                    return
                }

                // 🔧 메모리 최적화: 화면 밖 오버레이 제거 (새 오버레이 로드 전)
                self.removeOverlaysOutsideViewport(bbox: bbox)

                print("🔄 Debounce: \(currentVisibleLayers.count)개 레이어 로드 중...")

                // 로딩 시작
                self.isLoadingLayers = true

                // API에서 데이터 가져오기 (우선순위 기반, 점진적 로딩)
                // addOverlays()에서 자동으로 중복 제거됨
                _ = await self.apiManager.fetchMultipleLayers(
                    layers: currentVisibleLayers,
                    bbox: bbox,
                    onLayerLoaded: { [weak self] layer, features in
                        guard let self = self else { return }
                        // 각 레이어가 로드되는 즉시 지도에 표시 (중복 자동 제거)
                        Task { @MainActor in
                            // ⚠️ 추가 안전장치: 여전히 visible인지 재확인
                            guard self.visibleLayers.contains(layer) else {
                                print("⏭️ \(layer.displayName): 로드 완료했으나 이미 해제됨 - 오버레이 추가 취소")
                                return
                            }

                            self.addOverlays(for: layer, features: features)
                            self.updateOverlayCount()
                            print("🎯 \(layer.displayName) 처리 완료 (우선순위 \(layer.loadingPriority)위)")
                        }
                    }
                )

                // 로딩 완료
                self.isLoadingLayers = false

                print("✅ Debounce 오버레이 업데이트 완료: \(self.overlayCount)개 표시됨")
            }
        }
    }

    // MARK: - Private Methods

    /// 특정 레이어의 오버레이 추가
    private func addOverlays(for layer: FlightZoneLayer, features: [DroneZoneFeature]) {
        guard let mapView = mapView else { return }

        // ✅ 안전장치: 스케치 모드로 인해 일시 숨김 상태면 오버레이 추가하지 않음
        guard !isTemporarilyHidden else {
            print("⏭️ 스케치 모드 활성화 상태 - 오버레이 추가 취소")
            return
        }

        // ✅ 안전장치: 레이어가 아직 visible인지 확인 (비동기 로딩 중 해제된 경우 방지)
        guard visibleLayers.contains(layer) else {
            print("⏭️ \(layer.displayName): 레이어가 해제되어 오버레이 추가 취소")
            return
        }

        // 기존에 로드된 Feature ID 가져오기
        var loadedFeatureIDs = loadedFeatures[layer] ?? Set<String>()
        var layerOverlays = overlays[layer] ?? []
        var newCount = 0

        // 🔧 메모리 최적화: 새로 추가할 Feature ID 먼저 확인
        var featuresToAdd: [DroneZoneFeature] = []
        for feature in features {
            let featureID = feature.id
            if !loadedFeatureIDs.contains(featureID) {
                featuresToAdd.append(feature)
                loadedFeatureIDs.insert(featureID)
            }
        }

        // 새로 추가할 게 없으면 종료
        if featuresToAdd.isEmpty {
            print("♻️ \(layer.displayName): 모든 구역이 이미 로드됨 (총 \(layerOverlays.count)개)")
            return
        }

        for feature in featuresToAdd {
            // 새로운 Feature 추가
            newCount += 1
            print("   ➕ 새 구역: \(feature.zoneCode ?? feature.id) (ID: \(feature.id))")

            let polygons = feature.extractCoordinates()

            // 🔧 메모리 최적화: Polygon당 1개의 Overlay만 생성 (ring별로 중복 생성 방지)
            for (polygonIndex, polygon) in polygons.enumerated() {
                // 첫 번째 ring (외곽선)이 유효한지 확인
                guard let firstRing = polygon.first, firstRing.count >= 3 else { continue }

                // NMFPolygonOverlay 생성
                let overlay = NMFPolygonOverlay()

                // 첫 번째 ring을 외곽선으로 변환
                let outerRingPoints = firstRing.map { NMGLatLng(lat: $0.latitude, lng: $0.longitude) }

                // 🔍 디버그: 첫 번째 좌표 출력
                if let firstPoint = firstRing.first {
                    print("   🗺️ 폴리곤[\(polygonIndex)] 첫 좌표: lat=\(firstPoint.latitude), lng=\(firstPoint.longitude)")
                }

                // 나머지 ring들을 홀(interior rings)로 처리
                var interiorRings: [NMGLineString<AnyObject>] = []
                for holeRing in polygon.dropFirst() where holeRing.count >= 3 {
                    let holePoints = holeRing.map { NMGLatLng(lat: $0.latitude, lng: $0.longitude) }
                    interiorRings.append(NMGLineString(points: holePoints))
                }

                // 폴리곤 생성 (홀 포함)
                if interiorRings.isEmpty {
                    overlay.polygon = NMGPolygon(ring: NMGLineString(points: outerRingPoints))
                } else {
                    overlay.polygon = NMGPolygon(ring: NMGLineString(points: outerRingPoints), interiorRings: interiorRings)
                    print("   🕳️ 홀(interior rings) \(interiorRings.count)개 포함")
                }

                // 스타일 설정
                overlay.fillColor = layer.uiColor
                overlay.outlineColor = layer.borderUIColor
                overlay.outlineWidth = 2

                // Z-index 설정 (중요도가 높을수록 위에 표시)
                overlay.zIndex = 100 - layer.priority

                // 터치 핸들러 설정
                overlay.touchHandler = { [weak self] overlay in
                    print("🔵 [터치] 오버레이 터치 감지")

                    guard let self = self else {
                        print("❌ [터치] self가 nil")
                        return false
                    }

                    guard let polygonOverlay = overlay as? NMFPolygonOverlay else {
                        print("❌ [터치] NMFPolygonOverlay 캐스팅 실패")
                        return false
                    }

                    print("🔵 [터치] overlayFeatureMap 개수: \(self.overlayFeatureMap.count)")

                    guard let feature = self.overlayFeatureMap[polygonOverlay] else {
                        print("❌ [터치] overlayFeatureMap에서 feature를 찾을 수 없음")
                        return false
                    }

                    print("✅ [터치] feature 찾음: \(feature.layer.displayName), 코드: \(feature.zoneCode ?? "없음")")

                    // 선택된 오버레이 업데이트 (외곽선 강조)
                    self.selectedOverlay = polygonOverlay

                    // 콜백 호출
                    self.onOverlayTapped?(feature)
                    return true
                }

                // 지도에 추가
                overlay.mapView = mapView

                // 저장
                layerOverlays.append(overlay)
                overlayFeatureMap[overlay] = feature
            }
        }

        // 업데이트된 정보 저장
        overlays[layer] = layerOverlays
        loadedFeatures[layer] = loadedFeatureIDs

        if newCount > 0 {
            print("➕ \(layer.displayName): \(newCount)개 새 오버레이 추가 (총 \(layerOverlays.count)개)")
        } else {
            print("♻️ \(layer.displayName): 모든 오버레이 이미 로드됨 (총 \(layerOverlays.count)개)")
        }
    }

    /// 특정 레이어의 오버레이 제거
    private func removeOverlays(for layer: FlightZoneLayer) {
        guard let layerOverlays = overlays[layer] else { return }

        let overlayCount = layerOverlays.count

        // 🔧 메모리 최적화: 오버레이를 명시적으로 제거하고 메모리 해제
        for overlay in layerOverlays {
            // 1. 지도에서 제거
            overlay.mapView = nil

            // 2. 터치 핸들러 제거 (순환 참조 방지)
            overlay.touchHandler = nil

            // 3. Feature 매핑 제거
            overlayFeatureMap.removeValue(forKey: overlay)
        }

        // 4. 레이어 오버레이 배열 제거
        overlays.removeValue(forKey: layer)

        print("➖ \(layer.displayName): \(overlayCount)개 오버레이 제거 및 메모리 해제됨")
    }

    /// 특정 레이어 숨기기
    private func hideLayer(_ layer: FlightZoneLayer) {
        removeOverlays(for: layer)
        loadedFeatures.removeValue(forKey: layer)  // 로드된 Feature 기록 삭제
        updateOverlayCount()
    }

    /// 오버레이 개수 업데이트
    private func updateOverlayCount() {
        overlayCount = overlays.values.reduce(0) { $0 + $1.count }
    }

    /// 선택된 레이어를 UserDefaults에 저장
    private func saveVisibleLayersToStorage() {
        let layerRawValues = visibleLayers.map { $0.rawValue }
        UserDefaults.standard.set(layerRawValues, forKey: "VWorld_VisibleLayers")
    }

    /// UserDefaults에서 선택된 레이어 불러오기
    private func loadVisibleLayersFromStorage() {
        guard let layerRawValues = UserDefaults.standard.array(forKey: "VWorld_VisibleLayers") as? [String] else {
            return
        }

        visibleLayers = Set(layerRawValues.compactMap { FlightZoneLayer(rawValue: $0) })
        print("💾 저장된 레이어 로드: \(visibleLayers.count)개")
    }

    // MARK: - Sketch Mode Support

    /// 스케치 모드용: 현재 상태를 저장하고 모든 오버레이 일시 숨김
    @MainActor
    func hideTemporarily() {
        guard !isTemporarilyHidden else { return }

        // 진행 중인 API 로딩 취소 (레이스 컨디션 방지)
        fetchTask?.cancel()
        fetchTask = nil
        debounceTimer?.invalidate()
        debounceTimer = nil

        savedVisibleLayers = visibleLayers

        for (_, layerOverlays) in overlays {
            for overlay in layerOverlays {
                overlay.hidden = true
            }
        }

        isTemporarilyHidden = true
    }

    /// 스케치 모드용: 저장된 상태로 오버레이 복원
    @MainActor
    func restoreFromTemporaryHide() {
        guard isTemporarilyHidden else { return }

        if let saved = savedVisibleLayers {
            for layer in saved {
                if let layerOverlays = overlays[layer] {
                    for overlay in layerOverlays {
                        overlay.hidden = false
                    }
                }
            }
        }

        isTemporarilyHidden = false
        savedVisibleLayers = nil
    }

    // MARK: - Public Helper Methods

    /// 선택된 오버레이 해제
    func clearSelection() {
        selectedOverlay = nil
    }

    // MARK: - 🔧 메모리 최적화: 화면 밖 오버레이 관리

    /// 현재 화면 영역(viewport) 밖의 오버레이 제거
    /// - Parameter bbox: 현재 화면의 Bounding Box
    private func removeOverlaysOutsideViewport(bbox: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)) {
        // 여유 버퍼 (20% 확장 - 부드러운 전환을 위해)
        let bufferRatio = 0.2
        let lonBuffer = (bbox.maxLon - bbox.minLon) * bufferRatio
        let latBuffer = (bbox.maxLat - bbox.minLat) * bufferRatio

        let expandedBbox = (
            minLon: bbox.minLon - lonBuffer,
            minLat: bbox.minLat - latBuffer,
            maxLon: bbox.maxLon + lonBuffer,
            maxLat: bbox.maxLat + latBuffer
        )

        var totalRemoved = 0

        // 각 레이어별로 화면 밖 오버레이 제거
        for (layer, layerOverlays) in overlays {
            var overlaysToKeep: [NMFPolygonOverlay] = []
            var featuresToKeep = Set<String>()
            var removedCount = 0

            for overlay in layerOverlays {
                guard let feature = overlayFeatureMap[overlay] else {
                    // Feature 매핑이 없으면 제거
                    overlay.mapView = nil
                    overlay.touchHandler = nil
                    removedCount += 1
                    continue
                }

                // Feature의 좌표가 화면 영역 안에 있는지 확인
                if isFeatureInBounds(feature: feature, bbox: expandedBbox) {
                    overlaysToKeep.append(overlay)
                    featuresToKeep.insert(feature.id)
                } else {
                    // 화면 밖이므로 제거
                    overlay.mapView = nil
                    overlay.touchHandler = nil
                    overlayFeatureMap.removeValue(forKey: overlay)
                    removedCount += 1
                }
            }

            // 업데이트
            if removedCount > 0 {
                overlays[layer] = overlaysToKeep
                loadedFeatures[layer] = featuresToKeep
                totalRemoved += removedCount
                print("♻️ \(layer.displayName): 화면 밖 오버레이 \(removedCount)개 제거 (남은 개수: \(overlaysToKeep.count))")
            }
        }

        if totalRemoved > 0 {
            updateOverlayCount()
            print("♻️ 총 \(totalRemoved)개 오버레이 제거됨 → 현재 \(overlayCount)개")
        }
    }

    /// Feature가 Bounding Box 안에 있는지 확인
    /// - Parameters:
    ///   - feature: 확인할 Feature
    ///   - bbox: 화면 영역 (버퍼 포함)
    /// - Returns: 화면 안에 있으면 true
    private func isFeatureInBounds(
        feature: DroneZoneFeature,
        bbox: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)
    ) -> Bool {
        // Feature의 모든 좌표 추출
        let polygons = feature.extractCoordinates()

        // 좌표가 하나라도 bbox 안에 있으면 true (일부라도 보이면 유지)
        for polygon in polygons {
            for ring in polygon {
                for coord in ring {
                    if coord.longitude >= bbox.minLon &&
                       coord.longitude <= bbox.maxLon &&
                       coord.latitude >= bbox.minLat &&
                       coord.latitude <= bbox.maxLat {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// 🔧 메모리 경고 핸들러 - 긴급 메모리 정리
    @objc private func handleMemoryWarning() {
        print("⚠️ 메모리 경고 감지 - 오버레이 긴급 정리 시작")

        guard let mapView = mapView else {
            print("⚠️ 메모리 경고: 지도 없음, 모든 오버레이 제거")
            // 지도가 없으면 모든 오버레이 제거
            for layer in FlightZoneLayer.allCases {
                removeOverlays(for: layer)
            }
            return
        }

        // 현재 화면 영역만 남기고 모두 제거
        let bounds = mapView.coveringBounds
        let bbox = (
            minLon: bounds.southWestLng,
            minLat: bounds.southWestLat,
            maxLon: bounds.northEastLng,
            maxLat: bounds.northEastLat
        )

        // MainActor에서 실행
        Task { @MainActor in
            // 버퍼 없이 현재 화면 영역만 유지 (더 공격적으로 제거)
            let strictBbox = bbox  // 버퍼 0%

            var totalRemoved = 0

            for (layer, layerOverlays) in self.overlays {
                var overlaysToKeep: [NMFPolygonOverlay] = []
                var featuresToKeep = Set<String>()
                var removedCount = 0

                for overlay in layerOverlays {
                    guard let feature = self.overlayFeatureMap[overlay] else {
                        overlay.mapView = nil
                        overlay.touchHandler = nil
                        removedCount += 1
                        continue
                    }

                    if self.isFeatureInBounds(feature: feature, bbox: strictBbox) {
                        overlaysToKeep.append(overlay)
                        featuresToKeep.insert(feature.id)
                    } else {
                        overlay.mapView = nil
                        overlay.touchHandler = nil
                        self.overlayFeatureMap.removeValue(forKey: overlay)
                        removedCount += 1
                    }
                }

                if removedCount > 0 {
                    self.overlays[layer] = overlaysToKeep
                    self.loadedFeatures[layer] = featuresToKeep
                    totalRemoved += removedCount
                }
            }

            self.updateOverlayCount()
            print("✅ 메모리 경고 대응 완료 - \(totalRemoved)개 오버레이 제거, 남은 오버레이: \(self.overlayCount)개")
        }
    }
}

// MARK: - Helper Extensions

extension FlightZoneOverlayManager {
    /// 특정 레이어가 표시 중인지 확인
    func isLayerVisible(_ layer: FlightZoneLayer) -> Bool {
        return visibleLayers.contains(layer)
    }

    /// 표시 중인 레이어 개수
    var visibleLayerCount: Int {
        return visibleLayers.count
    }

    /// 모든 레이어가 선택되었는지 확인
    var allLayersVisible: Bool {
        return visibleLayers.count == FlightZoneLayer.allCases.count
    }
}
