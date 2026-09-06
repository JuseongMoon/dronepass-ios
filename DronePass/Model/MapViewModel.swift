import SwiftUI
import NMapsMap
import CoreLocation
import Combine

@MainActor
class MapViewModel: NSObject, ObservableObject {
    @Published var hasCenteredOnUser = false
    @Published var highlightedShapeID: UUID?
    @Published var overlays: [NMFOverlay] = []
    @Published var currentMapView: NMFMapView?

    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()

    // 중복 오버레이 리로드 방지를 위한 디바운싱
    private var lastReloadTime: Date = Date.distantPast
    private let reloadDebounceInterval: TimeInterval = 0.3 // 300ms (증가)

    // 하이라이트 오버레이 추적을 위한 변수
    private var currentHighlightOverlay: NMFCircleOverlay?

    // 이전 도형 상태 추적을 위한 변수
    private var lastShapeCount: Int = 0
    private var lastShapeIDs: Set<UUID> = []

    // 리로드 중 플래그 (터치 이벤트 안정성 향상)
    private var isReloadingOverlays = false

    // 오버레이-도형 매핑 (속성 업데이트를 위해)
    private var overlayToShapeMap: [NMFCircleOverlay: UUID] = [:]

    // MARK: - 스케치 모드 관련
    @Published var isSketchModeActive: Bool = false
    // 스케치 ID → 오버레이 매핑 (Lazy 로딩을 위해 딕셔너리로 관리)
    private var sketchOverlayDict: [UUID: NMFPolylineOverlay] = [:]
    private var currentDrawingOverlay: NMFPolylineOverlay?

    // MARK: - Constants
    private enum CameraConstants {
        static let defaultRadius: Double = 100.0
    }
    
    private enum AnimationType {
        case none
        case smooth
        case immediate
    }

    // NotificationCenter 상수 정의
    private static let moveToShapeNotification = Notification.Name("MoveToShapeNotification")
    private static let moveWithoutZoomNotification = Notification.Name("MoveWithoutZoomNotification")
    private static let shapeOverlayTappedNotification = Notification.Name("ShapeOverlayTapped")
    private static let openSavedTabNotification = Notification.Name("OpenSavedTabNotification")
    private static let clearMapHighlightNotification = Notification.Name("ClearMapHighlightNotification")

    override init() {
        super.init()
        setupLocationManager()
        setupShapeStoreObserver()
        setupNotifications()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10

        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    private func setupShapeStoreObserver() {
        ShapeFileStore.shared.$shapes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shapes in
                guard let self = self else { return }
                
                // 활성 도형 기준으로 비교해야 in-place 소프트삭제(배열 제거 없이 deletedAt만 설정)도 감지된다
                let activeShapes = shapes.filter { $0.deletedAt == nil }
                let currentShapeCount = activeShapes.count
                let currentShapeIDs = Set(activeShapes.map { $0.id })
                
                // 도형 개수나 ID가 변경된 경우에만 오버레이 리로드
                if currentShapeCount != self.lastShapeCount || currentShapeIDs != self.lastShapeIDs {
                    self.reloadOverlaysIfNeeded()
                    self.lastShapeCount = currentShapeCount
                    self.lastShapeIDs = currentShapeIDs
                    print("📊 도형 변경 감지: \(currentShapeCount)개 도형")
                }
                // 변경사항이 없는 경우 오버레이 리로드 스킵
            }
            .store(in: &cancellables)
    }
    
    /// 중복 오버레이 리로드를 방지하는 디바운싱 리로드
    private func reloadOverlaysIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastReloadTime) >= reloadDebounceInterval {
            reloadOverlays()
            lastReloadTime = now
        }
        // 디바운싱 로그 제거 (너무 자주 출력되는 문제 해결)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMoveToShape(_:)),
            name: Self.moveToShapeNotification,
            object: nil
        )

        // 드론 필터 변경 알림 처리
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDroneFilterChanged),
            name: .droneFilterChanged,
            object: nil
        )

        // 드론 강조 변경 알림 처리
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDroneHighlightChanged),
            name: .droneHighlightChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMoveWithoutZoom(_:)),
            name: Self.moveWithoutZoomNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShapeOverlayTapped(_:)),
            name: Self.shapeOverlayTappedNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClearMapHighlight),
            name: Self.clearMapHighlightNotification,
            object: nil
        )
        
        // 로그아웃 시 맵 오버레이 정리 알림
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClearMapOverlays),
            name: Notification.Name("ClearMapOverlays"),
            object: nil
        )
        
        // 색상 변경 시 지도 오버레이 리로드 알림
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReloadMapOverlays),
            name: Notification.Name("ReloadMapOverlays"),
            object: nil
        )
        
        // 도형 변경 시 지도 오버레이 리로드 알림
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShapesDidChange),
            name: Notification.Name("shapesDidChange"),
            object: nil
        )

        // DroneManager 초기 로드 완료 알림 처리
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDroneInitialLoadCompleted),
            name: Notification.Name("DroneInitialLoadCompleted"),
            object: nil
        )
    }

    @objc private func handleShapeOverlayTapped(_ notification: Notification) {
        guard let shape = notification.object as? ShapeModel else { return }
        
        // 하이라이트 상태 업데이트 (전체 리로드 대신 하이라이트만 변경)
        updateHighlight(for: shape.id)
        
        // 저장 탭 열기 알림 전송
        NotificationCenter.default.post(
            name: Self.openSavedTabNotification,
            object: shape.id
        )
    }

    @objc private func handleClearMapHighlight() {
        if highlightedShapeID != nil {
            updateHighlight(for: nil)
        }
    }

    // MARK: - 하이라이트 최적화 메서드
    
    /// 하이라이트만 효율적으로 업데이트 (전체 오버레이 리로드 없이)
    private func updateHighlight(for shapeID: UUID?) {
        guard let mapView = currentMapView else { return }
        
        // 기존 하이라이트와 동일한 경우 스킵
        if highlightedShapeID == shapeID {
            return
        }
        
        // 기존 하이라이트 오버레이 제거
        if let currentHighlight = currentHighlightOverlay {
            currentHighlight.mapView = nil
            if let index = overlays.firstIndex(where: { $0 === currentHighlight }) {
                overlays.remove(at: index)
            }
            currentHighlightOverlay = nil
        }
        
        // 새로운 하이라이트 설정
        highlightedShapeID = shapeID
        
        // 새로운 하이라이트 오버레이 추가
        if let shapeID = shapeID,
           let shape = ShapeFileStore.shared.shapes.first(where: { $0.id == shapeID }),
           let radius = shape.radius {
            
            let center = NMGLatLng(lat: shape.baseCoordinate.latitude, lng: shape.baseCoordinate.longitude)
            let highlightOverlay = createHighlightOverlay(center: center, radius: radius)
            highlightOverlay.mapView = mapView
            overlays.append(highlightOverlay)
            currentHighlightOverlay = highlightOverlay
            
            print("✨ 하이라이트 업데이트: \(shape.title)")
        } else {
            print("🚫 하이라이트 제거")
        }
    }
    
    @objc private func handleClearMapOverlays() {
        clearAllOverlays()
    }
    
    @objc private func handleReloadMapOverlays() {
        print("🔄 설정 변경 감지: 오버레이 리로드")
        // 만료된 도형 숨기기 설정 변경을 반영하기 위해 전체 오버레이 재생성
        reloadOverlays()
    }
    
    private func forceOverlayRedraw() {
        guard let mapView = currentMapView else { return }

        // 리로드 중 플래그 설정
        isReloadingOverlays = true
        defer { isReloadingOverlays = false }

        print("🎨 오버레이 완전 재생성 시작")

        // 기존 오버레이 완전 제거
        clearOverlays()
        
        // 새로운 오버레이 다시 생성
        let savedShapes = ShapeFileStore.shared.shapes.filter { $0.deletedAt == nil }
        
        // 중복 제거를 위해 ID 기반으로 필터링
        let uniqueShapes = Array(Set(savedShapes.map { $0.id })).compactMap { id in
            savedShapes.first { $0.id == id }
        }

        // 시작 전 도형 숨기기 설정이 활성화되어 있으면 시작 전 도형 필터링
        let notStartedFilteredShapes: [ShapeModel]
        if SettingManager.shared.isHideNotStartedShapesEnabled {
            notStartedFilteredShapes = uniqueShapes.filter { !$0.isNotStarted }
        } else {
            notStartedFilteredShapes = uniqueShapes
        }

        // 만료된 도형 숨기기 설정이 활성화되어 있으면 만료된 도형 필터링
        let filteredShapes: [ShapeModel]
        if SettingManager.shared.isHideExpiredShapesEnabled {
            filteredShapes = notStartedFilteredShapes.filter { !$0.isExpired }
        } else {
            filteredShapes = notStartedFilteredShapes
        }

        // 새로운 오버레이 생성
        for shape in filteredShapes {
            addOverlay(for: shape, mapView: mapView)
            print("🎨 새 오버레이 생성: \(shape.title) - \(shape.effectiveColor)")
        }

        // 하이라이트 다시 적용
        if let highlightedID = highlightedShapeID,
           let highlightedShape = filteredShapes.first(where: { $0.id == highlightedID }),
           let radius = highlightedShape.radius {

            let center = NMGLatLng(lat: highlightedShape.baseCoordinate.latitude, lng: highlightedShape.baseCoordinate.longitude)
            let highlightOverlay = createHighlightOverlay(center: center, radius: radius)
            highlightOverlay.mapView = mapView
            overlays.append(highlightOverlay)
            currentHighlightOverlay = highlightOverlay
        }

        print("🎨 오버레이 완전 재생성 완료: \(filteredShapes.count)개")
    }
    

    
    @objc private func handleShapesDidChange() {
        print("🔄 MapViewModel: shapesDidChange 알림 수신 - 지도 오버레이 리로드")
        reloadOverlays()
    }

    // MARK: - 카메라 이동 처리
    @objc private func handleMoveWithoutZoom(_ notification: Notification) {
        guard let moveData = notification.object as? SavedTableListView.MoveToShapeData,
              let mapView = currentMapView else { return }
        
        if shouldSkipMove(for: moveData) { return }
        
        // 하이라이트 업데이트 (전체 오버레이 리로드 없이)
        updateHighlight(for: moveData.shapeID)

        // 저장 탭 열기 알림 전송
        NotificationCenter.default.post(
            name: Self.openSavedTabNotification,
            object: moveData.shapeID
        )
        
        // 줌 변경 없이 좌표만 이동
        let center = NMGLatLng(lat: moveData.coordinate.latitude, lng: moveData.coordinate.longitude)
        let (offsetX, offsetY) = calculateDynamicOffsets()
        let offsetCenter = offsetLatLng(center: center, mapView: mapView, offsetX: offsetX, offsetY: offsetY)
        let cameraPosition = NMFCameraPosition(offsetCenter, zoom: mapView.cameraPosition.zoom)
        let cameraUpdate = NMFCameraUpdate(position: cameraPosition)
        cameraUpdate.animation = .easeIn
        mapView.moveCamera(cameraUpdate)
    }
        
    @objc private func handleMoveToShape(_ notification: Notification) {
        guard let moveData = notification.object as? SavedTableListView.MoveToShapeData,
              let mapView = currentMapView else { return }
        
        // 이미 하이라이트된 도형이면 리턴
        if shouldSkipMove(for: moveData) { return }
        
        moveCameraToShape(
            shapeID: moveData.shapeID,
            coordinate: moveData.coordinate,
            radius: moveData.radius,
            mapView: mapView
        )
    }
    
    private func shouldSkipMove(for moveData: SavedTableListView.MoveToShapeData) -> Bool {
        guard let shapeID = highlightedShapeID,
              let currentShape = ShapeFileStore.shared.shapes.first(where: { $0.id == shapeID }) else {
            return false
        }
        return currentShape.baseCoordinate == moveData.coordinate
    }
    
    private func moveCameraToShape(shapeID: UUID, coordinate: CoordinateManager, radius: Double, mapView: NMFMapView) {
        let center = NMGLatLng(lat: coordinate.latitude, lng: coordinate.longitude)
        let targetZoom = calculateZoomLevel(for: radius)
        
        // 1단계: 먼저 현재 위치에서 목표 줌 레벨로 조정
        let currentCameraPosition = mapView.cameraPosition
        let cameraPosition1 = NMFCameraPosition(currentCameraPosition.target, zoom: targetZoom)
        let cameraUpdate1 = NMFCameraUpdate(position: cameraPosition1)
        cameraUpdate1.animation = .easeIn
        mapView.moveCamera(cameraUpdate1)
        
        // 2단계: 목표 좌표로 이동하면서 하이라이트 적용
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            // 하이라이트 상태 업데이트 (전체 오버레이 리로드 없이)
            self.updateHighlight(for: shapeID)

            // 줌 레벨이 변경된 후, 올바른 projection으로 오프셋을 계산합니다.
            let (offsetX, offsetY) = self.calculateDynamicOffsets()
            let offsetCenter = self.offsetLatLng(center: center, mapView: mapView, offsetX: offsetX, offsetY: offsetY)

            let cameraPosition2 = NMFCameraPosition(offsetCenter, zoom: targetZoom)
            let cameraUpdate2 = NMFCameraUpdate(position: cameraPosition2)
            cameraUpdate2.animation = .easeIn
            mapView.moveCamera(cameraUpdate2)
        }
    }
    
    private func calculateDynamicOffsets() -> (x: CGFloat, y: CGFloat) {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        if isPad {
            // iPad인 경우 일반적인 가로 모드 오프셋 적용
            // X축: 화면 너비의 14%만큼 왼쪽으로 이동 (오른쪽으로 보이게)
            let offsetX: CGFloat = -100 // 고정값 사용
            return (x: offsetX, y: 0)
        } else {
            // iPhone 모드 - 고정값 사용
            // Y축: 화면 높이의 23%만큼 위로 이동 (위에 27% 여백)
            // X축: 중앙 정렬 (오프셋 0)
            let offsetY: CGFloat = 200 // 고정값 사용
            return (x: 0, y: offsetY)
        }
    }

    func addOverlay(for shape: ShapeModel, mapView: NMFMapView) {
        switch shape.shapeType {
        case .circle:
            addCircleOverlay(for: shape, mapView: mapView)
        default:
            break
        }
    }
    
    private func addCircleOverlay(for shape: ShapeModel, mapView: NMFMapView) {
            guard let radius = shape.radius else { return }

            let center = NMGLatLng(lat: shape.baseCoordinate.latitude, lng: shape.baseCoordinate.longitude)
        let circleOverlay = createCircleOverlay(center: center, radius: radius, shape: shape)
        circleOverlay.mapView = mapView
        overlays.append(circleOverlay)

        // 오버레이-도형 매핑 추가 (속성 업데이트를 위해)
        overlayToShapeMap[circleOverlay] = shape.id

        // 터치 핸들러 설정 (안전한 캡처)
        let shapeID = shape.id
        circleOverlay.touchHandler = { [weak self] _ in
            guard let self = self, !self.isReloadingOverlays else {
                print("⚠️ 터치 이벤트 무시: 리로드 중")
                return false
            }

            // 최신 도형 정보 가져오기
            guard let currentShape = ShapeFileStore.shared.shapes.first(where: { $0.id == shapeID }) else {
                print("⚠️ 터치 이벤트 무시: 도형을 찾을 수 없음")
                return false
            }

            // ShapeOverlayTapped 알림 전송
            NotificationCenter.default.post(
                name: Self.shapeOverlayTappedNotification,
                object: currentShape
            )

            return true
        }
    }
    
    private func createCircleOverlay(center: NMGLatLng, radius: Double, shape: ShapeModel) -> NMFCircleOverlay {
        let circleOverlay = NMFCircleOverlay()
        circleOverlay.center = center
        circleOverlay.radius = radius

        // POI 심볼(0)보다 위에 그려지도록 globalZIndex를 50으로 설정
        // 기본값 -200,000(셰이프)은 심볼 아래에 그려져 터치 이벤트를 받지 못함
        // 50: POI 위, 화살표 경로(100,000) 아래의 적절한 위치
        circleOverlay.globalZIndex = 50

        let isNotStarted = shape.isNotStarted
        let isExpired = shape.isExpired
        let mainColor: UIColor = isExpired ? .systemGray : (UIColor(hex: shape.effectiveColor) ?? .black)

        // 드론이 강조 상태인지 확인
        let isHighlighted = shape.droneId.map { DroneManager.shared.highlightedDroneIds.contains($0) } ?? false

        // 투명도 설정: 시작 전 도형은 더 높은 투명도
        let alphaValue: CGFloat
        if isNotStarted {
            alphaValue = isHighlighted ? 0.5 : 0.2
        } else {
            alphaValue = isHighlighted ? 0.7 : 0.3
        }

        circleOverlay.fillColor = mainColor.withAlphaComponent(alphaValue)

        // 테두리 설정: 시작 전 도형은 얇은 테두리(1)와 투명도 0.5 적용
        if isNotStarted {
            circleOverlay.outlineWidth = 1
            if isHighlighted {
                circleOverlay.outlineColor = UIColor(hex: "#333333") ?? .black
            } else {
                circleOverlay.outlineColor = mainColor.withAlphaComponent(0.5)
            }
        } else {
            circleOverlay.outlineWidth = 2
            circleOverlay.outlineColor = isHighlighted ? (UIColor(hex: "#333333") ?? .black) : mainColor
        }

        return circleOverlay
    }

    private func createHighlightOverlay(center: NMGLatLng, radius: Double) -> NMFCircleOverlay {
                let highlightOverlay = NMFCircleOverlay()
                highlightOverlay.center = center
                highlightOverlay.radius = radius + 2
                highlightOverlay.fillColor = UIColor.clear
                highlightOverlay.outlineWidth = 5
                highlightOverlay.outlineColor = .systemRed

        // CircleOverlay(50)보다 위에 그려지도록 globalZIndex를 60으로 설정
        // 하이라이트 외곽선이 일반 도형 위에 명확히 표시됨
        highlightOverlay.globalZIndex = 60

        return highlightOverlay
    }

    // MARK: - 오버레이 속성 업데이트 (재생성 없이)

    /// 오버레이를 재생성하지 않고 색상과 투명도만 업데이트합니다.
    /// 터치 핸들러가 유지되므로 터치 반응이 손실되지 않습니다.
    private func updateOverlayProperties() {
        guard !isReloadingOverlays else {
            print("⚠️ 이미 리로드 중이므로 속성 업데이트를 스킵합니다")
            return
        }

        print("🎨 오버레이 속성 업데이트 시작 (재생성 없음)")

        // 각 오버레이의 속성을 업데이트
        for (overlay, shapeID) in overlayToShapeMap {
            guard let shape = ShapeFileStore.shared.shapes.first(where: { $0.id == shapeID }) else {
                continue
            }

            // 색상 및 투명도 계산
            let isNotStarted = shape.isNotStarted
            let isExpired = shape.isExpired
            let mainColor: UIColor = isExpired ? .systemGray : (UIColor(hex: shape.effectiveColor) ?? .black)

            // 드론이 강조 상태인지 확인
            let isHighlighted = shape.droneId.map { DroneManager.shared.highlightedDroneIds.contains($0) } ?? false

            // 투명도 설정: 시작 전 도형은 더 높은 투명도
            let alphaValue: CGFloat
            if isNotStarted {
                alphaValue = isHighlighted ? 0.5 : 0.2
            } else {
                alphaValue = isHighlighted ? 0.7 : 0.3
            }

            // 속성만 변경 (터치 핸들러는 그대로 유지)
            overlay.fillColor = mainColor.withAlphaComponent(alphaValue)

            // 테두리 설정: 시작 전 도형은 얇은 테두리(1)와 투명도 0.5 적용
            if isNotStarted {
                overlay.outlineWidth = 1
                if isHighlighted {
                    overlay.outlineColor = UIColor(hex: "#333333") ?? .black
                } else {
                    overlay.outlineColor = mainColor.withAlphaComponent(0.5)
                }
            } else {
                overlay.outlineWidth = 2
                overlay.outlineColor = isHighlighted ? (UIColor(hex: "#333333") ?? .black) : mainColor
            }
        }

        print("✅ 오버레이 속성 업데이트 완료: \(overlayToShapeMap.count)개")
    }

    func reloadOverlays() {
        // 리로드 중 플래그 설정
        isReloadingOverlays = true
        defer { isReloadingOverlays = false }

        // 기존 오버레이 정리
        clearOverlays()

        // 새로운 오버레이 추가
        guard let mapView = currentMapView else { return }

        let savedShapes = ShapeFileStore.shared.shapes.filter { $0.deletedAt == nil }
        
        // 중복 제거를 위해 ID 기반으로 필터링
        let uniqueShapes = Array(Set(savedShapes.map { $0.id })).compactMap { id in
            savedShapes.first { $0.id == id }
        }
        
        // 시작 전 도형 숨기기 설정이 활성화되어 있으면 시작 전 도형 필터링
        let notStartedFilteredShapes: [ShapeModel]
        if SettingManager.shared.isHideNotStartedShapesEnabled {
            notStartedFilteredShapes = uniqueShapes.filter { !$0.isNotStarted }
            print("🔄 시작 전 도형 필터링: \(notStartedFilteredShapes.count)개 도형 (전체: \(uniqueShapes.count)개)")
        } else {
            notStartedFilteredShapes = uniqueShapes
        }

        // 만료된 도형 숨기기 설정이 활성화되어 있으면 만료된 도형 필터링
        let expiredFilteredShapes: [ShapeModel]
        if SettingManager.shared.isHideExpiredShapesEnabled {
            expiredFilteredShapes = notStartedFilteredShapes.filter { !$0.isExpired }
            print("🔄 만료된 도형 필터링: \(expiredFilteredShapes.count)개 도형 (시작 전 필터링 후: \(notStartedFilteredShapes.count)개)")
        } else {
            expiredFilteredShapes = notStartedFilteredShapes
        }

        // 드론 필터링 추가
        let droneFilteredShapes: [ShapeModel]
        let selectedDroneIds = DroneManager.shared.selectedDroneIds

        if !DroneManager.shared.hasCompletedInitialLoad {
            // 드론 초기 로드 중: 오버레이를 생성하지 않음 (도형 숨김)
            droneFilteredShapes = []
            print("⏳ 드론 초기 로드 중: 도형 숨김 (드론 정보 로딩 대기)")
        } else if selectedDroneIds.isEmpty {
            // 초기 로드 완료 후 아무것도 선택 안됨 = 아무것도 표시하지 않음
            droneFilteredShapes = []
        } else {
            // 선택된 드론의 도형만 필터링
            droneFilteredShapes = expiredFilteredShapes.filter { shape in
                if let droneId = shape.droneId {
                    return selectedDroneIds.contains(droneId)
                } else {
                    // 하이브리드 호환성: droneId 없는 기존 도형은 첫 번째 드론으로 처리
                    if let firstDroneId = DroneManager.shared.activeDrones.first?.id {
                        return selectedDroneIds.contains(firstDroneId)
                    }
                    return false
                }
            }
            print("🎯 드론 필터링: \(droneFilteredShapes.count)개 도형 (선택된 드론: \(selectedDroneIds.count)개)")
        }
        
        for shape in droneFilteredShapes {
            addOverlay(for: shape, mapView: mapView)
        }
        
        // 하이라이트가 있는 경우 다시 적용 (필터링된 도형 중에서만)
        if let highlightedID = highlightedShapeID,
           let highlightedShape = droneFilteredShapes.first(where: { $0.id == highlightedID }),
           let radius = highlightedShape.radius {
            
            let center = NMGLatLng(lat: highlightedShape.baseCoordinate.latitude, lng: highlightedShape.baseCoordinate.longitude)
            let highlightOverlay = createHighlightOverlay(center: center, radius: radius)
            highlightOverlay.mapView = mapView
            overlays.append(highlightOverlay)
            currentHighlightOverlay = highlightOverlay
        }
    }
    
    private func clearOverlays() {
        overlays.forEach { overlay in
            overlay.mapView = nil
        }
        overlays.removeAll()
        overlayToShapeMap.removeAll() // 매핑도 함께 정리
        currentHighlightOverlay = nil
        // 로그 메시지 제거 (너무 자주 출력되는 문제 해결)
    }
    
    // 로그아웃 시 호출할 메서드
    func clearAllOverlays() {
        // 중복된 오버레이만 정리
        removeDuplicateOverlays()
        highlightedShapeID = nil
        currentHighlightOverlay = nil
        // 로그 메시지 간소화
        print("🚪 로그아웃: 오버레이 정리 완료")
    }
    
    // 중복된 오버레이 제거
    private func removeDuplicateOverlays() {
        guard let mapView = currentMapView else { return }
        
        let savedShapes = ShapeFileStore.shared.shapes.filter { $0.deletedAt == nil }
        
        // 중복 제거를 위해 ID 기반으로 필터링
        let uniqueShapes = Array(Set(savedShapes.map { $0.id })).compactMap { id in
            savedShapes.first { $0.id == id }
        }
        
        // 만료된 도형 숨기기 설정이 활성화되어 있으면 만료된 도형 필터링
        let filteredShapes: [ShapeModel]
        if SettingManager.shared.isHideExpiredShapesEnabled {
            filteredShapes = uniqueShapes.filter { !$0.isExpired }
        } else {
            filteredShapes = uniqueShapes
        }
        
        // 중복이 있는 경우에만 정리
        if uniqueShapes.count != savedShapes.count {
            print("🧹 중복 오버레이 발견: \(savedShapes.count)개 → \(filteredShapes.count)개")
            
            // 기존 오버레이 정리
            clearOverlays()
            
            // 필터링된 도형만 다시 추가
            for shape in filteredShapes {
                addOverlay(for: shape, mapView: mapView)
            }
            
            // 하이라이트 재적용 (필터링된 도형 중에서만)
            if let highlightedID = highlightedShapeID,
               let highlightedShape = filteredShapes.first(where: { $0.id == highlightedID }),
               let radius = highlightedShape.radius {
                
                let center = NMGLatLng(lat: highlightedShape.baseCoordinate.latitude, lng: highlightedShape.baseCoordinate.longitude)
                let highlightOverlay = createHighlightOverlay(center: center, radius: radius)
                highlightOverlay.mapView = mapView
                overlays.append(highlightOverlay)
                currentHighlightOverlay = highlightOverlay
            }
        }
        // 중복이 없는 경우 로그 제거 (불필요한 출력 방지)
    }
    
    func calculateZoomLevel(for radius: Double) -> Double {
        let minRadius: Double = 100
        let maxRadius: Double = 3000
        let minZoom: Double = 11
        let maxZoom: Double = 14
        
        if radius <= minRadius { return maxZoom }
        if radius >= maxRadius { return minZoom }
        
        let zoomRange = maxZoom - minZoom
        let radiusRange = maxRadius - minRadius
        let normalizedRadius = radius - minRadius
        
        return maxZoom - (normalizedRadius * zoomRange / radiusRange)
    }
    
    func offsetLatLng(center: NMGLatLng, mapView: NMFMapView, offsetX: CGFloat, offsetY: CGFloat) -> NMGLatLng {
        let point = mapView.projection.point(from: center)
        let offsetPoint = CGPoint(x: point.x + offsetX, y: point.y + offsetY)
        return mapView.projection.latlng(from: offsetPoint)
    }
}

extension MapViewModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latlng = NMGLatLng(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        
        if !hasCenteredOnUser {
            hasCenteredOnUser = true
            NotificationCenter.default.post(name: Notification.Name("CenterOnUserLocation"), object: latlng)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }

    // MARK: - Drone Filter Handling

    @objc private func handleDroneFilterChanged() {
        print("🎯 드론 필터 변경 감지 - 지도 오버레이 업데이트")
        reloadOverlaysIfNeeded()
    }

    @objc private func handleDroneHighlightChanged() {
        print("🎨 드론 강조 변경 감지: 오버레이 속성 업데이트 (재생성 없음)")

        // 오버레이를 재생성하지 않고 속성만 업데이트
        updateOverlayProperties()
    }

    @objc private func handleDroneInitialLoadCompleted() {
        print("✅ 드론 초기 로드 완료: 오버레이 생성 시작")
        reloadOverlays()
    }

    // MARK: - 스케치 모드 메서드

    /// 스케치 모드 진입 - 모든 기존 오버레이 숨김
    func enterSketchMode() {
        guard !isSketchModeActive else { return }
        isSketchModeActive = true

        // 기존 오버레이들 숨기기
        overlays.forEach { overlay in
            overlay.hidden = true
        }

        // 스케치 오버레이 표시
        reloadSketchOverlays()

        print("✏️ 지도 스케치 모드 진입: 기존 오버레이 숨김")
    }

    /// 스케치 모드 종료 - 기존 오버레이 복원
    func exitSketchMode() {
        guard isSketchModeActive else { return }
        isSketchModeActive = false

        // 기존 오버레이들 다시 표시
        overlays.forEach { overlay in
            overlay.hidden = false
        }

        // 스케치 오버레이도 계속 표시 (최상위 레이어)
        reloadSketchOverlays()

        print("✏️ 지도 스케치 모드 종료: 기존 오버레이 복원")
    }

    /// 스케치 오버레이 리로드 (Lazy 로딩 - 뷰포트 내 스케치만)
    func reloadSketchOverlays() {
        // 기존 스케치 오버레이 정리
        clearSketchOverlays()

        // 뷰포트 내 스케치만 로드
        updateVisibleSketchOverlays()

        print("✏️ 스케치 오버레이 리로드 (Lazy)")
    }

    /// 뷰포트 내 스케치 오버레이 업데이트 (Lazy 스무딩)
    /// 스케치 모드가 아니어도 스케치는 항상 표시됨
    func updateVisibleSketchOverlays() {
        guard let mapView = currentMapView else { return }

        let bounds = mapView.coveringBounds
        let allSketches = SketchFileStore.shared.sketches

        // 뷰포트 내 스케치 ID 필터링
        let visibleSketchIds = Set(allSketches.filter { sketch in
            isSketchInBounds(sketch, bounds: bounds)
        }.map { $0.id })

        // 안 보이는 오버레이 제거
        let idsToRemove = sketchOverlayDict.keys.filter { !visibleSketchIds.contains($0) }
        for id in idsToRemove {
            sketchOverlayDict[id]?.mapView = nil
            sketchOverlayDict.removeValue(forKey: id)
        }

        // 새로 보이는 스케치 오버레이 생성
        for sketch in allSketches where visibleSketchIds.contains(sketch.id) {
            if sketchOverlayDict[sketch.id] == nil {
                addSketchOverlay(for: sketch, mapView: mapView)
            }
        }
    }

    /// 스케치가 뷰포트 bounds 내에 있는지 확인
    private func isSketchInBounds(_ sketch: SketchModel, bounds: NMGLatLngBounds) -> Bool {
        guard !sketch.points.isEmpty else { return false }

        // 스케치의 bounding box 계산
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLng = Double.greatestFiniteMagnitude
        var maxLng = -Double.greatestFiniteMagnitude

        for point in sketch.points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLng = min(minLng, point.longitude)
            maxLng = max(maxLng, point.longitude)
        }

        // 뷰포트와 스케치 bounding box가 겹치는지 확인
        let boundsMinLat = bounds.southWestLat
        let boundsMaxLat = bounds.northEastLat
        let boundsMinLng = bounds.southWestLng
        let boundsMaxLng = bounds.northEastLng

        // 두 사각형이 겹치지 않는 경우
        if maxLat < boundsMinLat || minLat > boundsMaxLat ||
           maxLng < boundsMinLng || minLng > boundsMaxLng {
            return false
        }

        return true
    }

    /// 스케치 오버레이 추가 (딕셔너리에 저장)
    private func addSketchOverlay(for sketch: SketchModel, mapView: NMFMapView) {
        guard sketch.points.count >= 2 else { return }

        // 이미 존재하면 스킵
        if sketchOverlayDict[sketch.id] != nil { return }

        // displayPoints 사용 (스무딩 적용된 포인트)
        let coords = sketch.displayPoints.map { NMGLatLng(lat: $0.latitude, lng: $0.longitude) }

        let polyline = NMFPolylineOverlay(coords)
        // 투명도를 색상에 적용
        let baseColor = UIColor(hex: sketch.color) ?? .red
        polyline?.color = baseColor.withAlphaComponent(CGFloat(sketch.opacity))
        polyline?.width = CGFloat(sketch.strokeWidth)
        polyline?.globalZIndex = 100  // 최상위 레이어
        polyline?.mapView = mapView

        if let polyline = polyline {
            sketchOverlayDict[sketch.id] = polyline
        }
    }

    /// 현재 그리기 중인 스케치 미리보기 업데이트
    func updateCurrentDrawingPreview(points: [CoordinateManager]) {
        guard let mapView = currentMapView, points.count >= 2 else {
            // 포인트가 부족하면 미리보기 제거
            currentDrawingOverlay?.mapView = nil
            currentDrawingOverlay = nil
            return
        }

        // 기존 미리보기 제거
        currentDrawingOverlay?.mapView = nil

        let coords = points.map { NMGLatLng(lat: $0.latitude, lng: $0.longitude) }

        let polyline = NMFPolylineOverlay(coords)
        // 투명도를 색상에 적용
        let baseColor = UIColor(hex: SketchManager.shared.currentColor) ?? .red
        polyline?.color = baseColor.withAlphaComponent(CGFloat(SketchManager.shared.currentOpacity))
        polyline?.width = CGFloat(SketchManager.shared.currentStrokeWidth)
        polyline?.globalZIndex = 101  // 가장 위
        polyline?.mapView = mapView

        currentDrawingOverlay = polyline
    }

    /// 스케치 오버레이 정리
    func clearSketchOverlays() {
        for (_, overlay) in sketchOverlayDict {
            overlay.mapView = nil
        }
        sketchOverlayDict.removeAll()

        currentDrawingOverlay?.mapView = nil
        currentDrawingOverlay = nil
    }

    /// 특정 스케치 오버레이 제거
    func removeSketchOverlay(id: UUID) {
        sketchOverlayDict[id]?.mapView = nil
        sketchOverlayDict.removeValue(forKey: id)
    }

    /// 모든 스케치 오버레이 삭제
    func deleteAllSketchOverlays() {
        clearSketchOverlays()
        print("🗑️ 모든 스케치 오버레이 삭제됨")
    }
} 
