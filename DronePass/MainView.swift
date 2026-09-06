//
//  MainView.swift
//  DronePass
//
//  Created by 문주성 on 6/10/25.
//

import SwiftUI
import NMapsMap
import MapKit

class MainViewCoordinator: NSObject, ObservableObject {
    @Published var currentAddress: String = ""
    @Published var isSearchingAddress: Bool = false
    @Published var selectedAddress: String = ""
    @Published var selectedCoordinate: CoordinateManager?
    
    var onLongPress: ((CoordinateManager) -> Void)?
    
    init(onLongPress: ((CoordinateManager) -> Void)? = nil) {
        self.onLongPress = onLongPress
        super.init()
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let naverMapView = gesture.view as? NMFNaverMapView else { return }
        let mapView = naverMapView.mapView
        
        let point = gesture.location(in: gesture.view)
        let latlng = mapView.projection.latlng(from: point)
        let coordinate = CoordinateManager(latitude: latlng.lat, longitude: latlng.lng)
        
        // 주소 조회
        Task {
            do {
                let address = try await NaverGeocodingService.shared.reverseGeocode(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                await MainActor.run {
                    self.currentAddress = address
                    self.onLongPress?(coordinate)
                }
            } catch {
                print("주소 변환 실패:", error)
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
        // 주소 조회
        Task {
            do {
                let address = try await NaverGeocodingService.shared.reverseGeocode(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                await MainActor.run {
                    self.currentAddress = address
                    let coord = CoordinateManager(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    self.onLongPress?(coord)
                }
            } catch {
                print("주소 변환 실패:", error)
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        let coordinate = annotation.coordinate
        let coord = CoordinateManager(latitude: coordinate.latitude, longitude: coordinate.longitude)
        self.selectedCoordinate = coord
    }
}

extension MainViewCoordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

private struct NewShapeDraft: Identifiable {
    let id = UUID()
    let coordinate: CoordinateManager
    let address: String?
}

struct MainView: View {
    @StateObject var viewModel = MapViewModel()
    @StateObject var flightZoneManager = FlightZoneOverlayManager()
    @ObservedObject var droneManager = DroneManager.shared
    @ObservedObject var kpIndexManager = KPIndexManager.shared
    @ObservedObject var weatherManager = WeatherManager.shared
    @State var mapView: NMFMapView?

    // 새 도형 만들기 관련 상태
    @State private var newShapeCoordinate: CoordinateManager?
    @State private var newShapeAddress: String?
    @State private var newShapeDraft: NewShapeDraft?

    // 알림 관련 상태
    @State private var showNewShapeConfirmAlert = false
    @State private var showGeocodingFailedAlert = false

    // 🔧 메모리 최적화: NotificationCenter 옵저버 추적용
    @State private var notificationObservers: [NSObjectProtocol] = []

    // KP 예보 시트 표시 상태
    @State private var showKPForecastSheet = false

    // 날씨 정보 시트 표시 상태
    @State private var showWeatherInfoSheet = false

    // 스케치 모드 관련 상태
    @State private var isSketchModeActive = false
    @ObservedObject var sketchManager = SketchManager.shared

    // VWorld 구역 상세 정보 시트 표시 상태
    @State private var showZoneDetailSheet = false
    @State private var selectedZoneFeature: DroneZoneFeature?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 배경 지도
                NaverMapView(
                    mapView: $mapView,
                    onMapViewCreated: { mapView in
                        setupMapView(mapView)
                    },
                    onLongPress: { coordinate in
                        handleLongPress(at: coordinate)
                    }
                )
                .ignoresSafeArea()

                // 플로팅 버튼들 (스케치 모드가 아닐 때만 표시)
                if !isSketchModeActive {
                    MainFloatingButtonView(
                        droneManager: droneManager,
                        kpIndexManager: kpIndexManager,
                        weatherManager: weatherManager,
                        settingManager: SettingManager.shared,
                        flightZoneManager: flightZoneManager,
                        geometry: geometry,
                        mapView: mapView,
                        dropdownTopPadding: dropdownTopPadding(for: geometry.size.height),
                        showWeatherInfoSheet: $showWeatherInfoSheet,
                        showKPForecastSheet: $showKPForecastSheet,
                        onCreateShape: { coordinate in
                            presentShapeEditor(at: coordinate, address: nil)
                        },
                        isSketchModeActive: $isSketchModeActive
                    )
                }

                // 스케치 모드: 지도에 직접 제스처가 추가됨 (SketchGestureHandler)
                // 별도의 오버레이 뷰 없이 지도에서 직접 스케치 처리

                // 비행구역 레이어 로딩 인디케이터
                if flightZoneManager.isLoadingLayers {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)
//                        .offset(y: 100)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            setupNotifications()
            // KP 데이터는 MainTabView의 .onAppear에서 앱 시작 시 자동 로드됨
        }
        .onDisappear {
            removeNotifications()
            viewModel.currentMapView = nil
            viewModel.overlays.removeAll()
        }
        .sheet(item: $newShapeDraft, onDismiss: clearNewShapeData) { draft in
            ShapeEditView(
                coordinate: draft.coordinate,
                onAdd: { _ in
                    viewModel.reloadOverlays()
                    clearNewShapeData()
                },
                originalShape: ShapeModel(
                    id: draft.id,
                    title: "",
                    shapeType: .circle,
                    baseCoordinate: draft.coordinate,
                    radius: nil,
                    memo: nil,
                    address: draft.address,
                    createdAt: Date(),
                    deletedAt: nil,
                    flightStartDate: Date(),
                    flightEndDate: nil,
                    color: droneManager.selectedDrone?.color ?? ColorManager.shared.defaultColor.rawValue,
                    droneId: droneManager.selectedDroneId
                )
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(NSLocalizedString("main.newShape.alert.title", comment: "New shape alert title"), isPresented: $showNewShapeConfirmAlert) {
            Button(NSLocalizedString("common.no", comment: "No"), role: .cancel) { clearNewShapeData() }
            Button(NSLocalizedString("common.yes", comment: "Yes"), action: {
                presentPendingShapeEditor()
            })
        } message: {
            Text(NSLocalizedString("main.newShape.alert.message", comment: "New shape confirmation message"))
        }
        .alert(NSLocalizedString("main.addressSearch.failed.title", comment: "Address search failed title"), isPresented: $showGeocodingFailedAlert) {
            Button(NSLocalizedString("common.no", comment: "No"), role: .cancel) { clearNewShapeData() }
            Button(NSLocalizedString("common.yes", comment: "Yes"), action: {
                presentPendingShapeEditor()
            })
        } message: {
            Text(NSLocalizedString("main.addressSearch.failed.message", comment: "Address search failed message"))
        }
        .sheet(isPresented: $showKPForecastSheet) {
            KPForecastView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showWeatherInfoSheet) {
            WeatherForecastView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showZoneDetailSheet) {
            if let feature = selectedZoneFeature {
                let _ = print("🟡 [Sheet] 상세보기 표시 - 레이어: \(feature.layer.displayName), 코드: \(feature.zoneCode ?? "없음")")
                VWorldZoneDetailView(feature: feature)
                    .onDisappear {
                        // 시트가 닫힐 때 선택 해제
                        flightZoneManager.clearSelection()
                        selectedZoneFeature = nil
                    }
            } else {
                let _ = print("❌ [Sheet] selectedZoneFeature가 nil")
            }
        }
        .onChange(of: selectedZoneFeature?.id) { _, newID in
            if newID != nil {
                print("🟢 [onChange] selectedZoneFeature 변경 감지 (ID: \(newID ?? "nil")) → Sheet 표시")
                // Task로 래핑하여 View body 렌더링 사이클 외부에서 상태 변경
                Task { @MainActor in
                    showZoneDetailSheet = true
                }
            }
        }
        .onChange(of: isSketchModeActive) { _, newValue in
            if newValue {
                enterSketchMode()
            }
        }
        // sketchManager.isSketchModeActive가 외부에서 변경될 때 동기화
        // (MainTabView의 스케치 툴바 완료 버튼에서 종료 시)
        .onChange(of: sketchManager.isSketchModeActive) { _, newValue in
            if !newValue && isSketchModeActive {
                // 스케치 모드가 외부에서 종료됨 → 로컬 상태 정리
                // Task로 래핑하여 뷰 업데이트 사이클 외부에서 상태 변경
                Task { @MainActor in
                    SketchGestureHandler.shared.detach()  // 스케치 제스처 제거
                    viewModel.exitSketchMode()
                    isSketchModeActive = false
                    flightZoneManager.restoreFromTemporaryHide()
                }
            }
        }
    }
    
    private func handleLongPress(at location: CLLocationCoordinate2D) {
        Task {
            do {
                let address = try await NaverGeocodingService.shared.reverseGeocode(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                // 성공 시, 좌표와 주소를 저장하고 확인창을 띄웁니다.
                self.newShapeCoordinate = CoordinateManager(latitude: location.latitude, longitude: location.longitude)
                self.newShapeAddress = address
                self.showNewShapeConfirmAlert = true
            } catch {
                // 실패 시, 안내 문구를 주소로 설정하고 실패 알림을 띄웁니다.
                self.newShapeCoordinate = CoordinateManager(latitude: location.latitude, longitude: location.longitude)
                self.newShapeAddress = NSLocalizedString("mainView.address.notFound", comment: "Address not found for this location")
                self.showGeocodingFailedAlert = true
            }
        }
    }
    
    private func clearNewShapeData() {
        newShapeCoordinate = nil
        newShapeAddress = nil
        newShapeDraft = nil
        showNewShapeConfirmAlert = false
        showGeocodingFailedAlert = false
    }

    private func presentPendingShapeEditor() {
        guard let coordinate = newShapeCoordinate else {
            clearNewShapeData()
            return
        }
        presentShapeEditor(at: coordinate, address: newShapeAddress)
    }

    private func presentShapeEditor(at coordinate: CoordinateManager, address: String?) {
        newShapeDraft = NewShapeDraft(coordinate: coordinate, address: address)
    }

    // MARK: - Sketch Mode

    /// 스케치 모드 진입
    private func enterSketchMode() {
        sketchManager.enterSketchMode()
        viewModel.enterSketchMode()
        flightZoneManager.hideTemporarily()

        // 지도에 스케치 제스처 추가
        if let mapView = viewModel.currentMapView {
            SketchGestureHandler.shared.attach(to: mapView)
        }
    }

    /// 스케치 모드 종료
    private func exitSketchMode() {
        // 지도에서 스케치 제스처 제거
        SketchGestureHandler.shared.detach()

        sketchManager.exitSketchMode()
        viewModel.exitSketchMode()
        isSketchModeActive = false
        flightZoneManager.restoreFromTemporaryHide()
    }
    
    // 화면 높이에 따른 드롭다운 상단 패딩 계산
    private func dropdownTopPadding(for screenHeight: CGFloat) -> CGFloat {
        // Mac에서 iPad 앱으로 실행하는 경우
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return 20  // Mac에서 실행 시 패딩 값 (조정 가능)
        }
        
        // iPad는 고정값 사용
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 30
        }
        
        // iPhone은 화면 높이에 따라 다른 값 사용
        if screenHeight > 900 {
            // iPhone 16 Pro Max, 15 Pro Max 등
            return 60
        } else if screenHeight > 850 {
            // iPhone 14/15 Plus
            return 50
        } else if screenHeight > 800 {
            // iPhone 12, 13, 14, 15
            return 40
        } else {
            // iPhone SE, Mini 등 작은 화면
            return 40
        }
    }
    
    private func setupMapView(_ mapView: NMFMapView) {
        // 전체 함수 내용을 Task로 래핑하여 View body 렌더링 사이클 외부에서 실행
        Task { @MainActor in
            viewModel.currentMapView = mapView

            // VWorld 오버레이 매니저에 지도 설정
            flightZoneManager.setMapView(mapView)

            // 오버레이 리로드
            viewModel.reloadOverlays()
            // 앱 시작 시 저장된 스케치 오버레이 로드
            viewModel.reloadSketchOverlays()

            // VWorld 오버레이 터치 이벤트 설정
            flightZoneManager.onOverlayTapped = { feature in
                print("🟠 [콜백] onOverlayTapped 호출됨 - 레이어: \(feature.layer.displayName), 코드: \(feature.zoneCode ?? "없음")")
                Task { @MainActor in
                    print("🟠 [콜백] MainActor에서 selectedZoneFeature 설정")
                    selectedZoneFeature = feature
                }
            }

            // 지도 이동 시 VWorld 구역 자동 로드
            setupMapCameraChangeListener(mapView)
        }
    }

    private func setupMapCameraChangeListener(_ mapView: NMFMapView) {
        // 🔧 메모리 최적화: 옵저버 반환 객체를 저장하여 나중에 제거 가능하도록 함
        // 카메라 이동 완료 시 드론 구역 로드 (debounce 적용)
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("MapCameraDidChange"),
            object: nil,
            queue: .main
        ) { [weak flightZoneManager, weak viewModel] _ in
            guard let manager = flightZoneManager else { return }

            let bounds = mapView.coveringBounds
            let bbox = (
                minLon: bounds.southWestLng,
                minLat: bounds.southWestLat,
                maxLon: bounds.northEastLng,
                maxLat: bounds.northEastLat
            )

            // Debounce를 적용한 로드 (MainActor 컨텍스트에서 실행)
            Task { @MainActor in
                manager.fetchWithDebounce(
                    layers: Array(manager.visibleLayers),
                    bbox: bbox,
                    delay: 0.5
                )

                // 뷰포트 내 스케치 오버레이 업데이트 (Lazy 로딩)
                viewModel?.updateVisibleSketchOverlays()
            }
        }
        notificationObservers.append(observer)
    }
    
    private func setupNotifications() {
        // 🔧 메모리 최적화: 모든 옵저버 반환 객체를 저장
        let observer1 = NotificationCenter.default.addObserver(
            forName: Notification.Name("CenterOnUserLocation"),
            object: nil,
            queue: .main
        ) { notification in
            if let latlng = notification.object as? NMGLatLng {
                let cameraUpdate = NMFCameraUpdate(position: NMFCameraPosition(latlng, zoom: 16))
                cameraUpdate.animation = .easeIn
                // ⭐️ mapView가 nil이 아닐 때만 접근
                mapView?.moveCamera(cameraUpdate)
            }
        }
        notificationObservers.append(observer1)

        let observer2 = NotificationCenter.default.addObserver(
            forName: Notification.Name("ShapeOverlayTapped"),
            object: nil,
            queue: .main
        ) { notification in
            if let shape = notification.object as? ShapeModel {
                // MapViewModel에서 이미 updateHighlight()로 최적화된 처리 중
                // 전체 오버레이 리로드는 터치 핸들러를 제거/재생성하여 터치 이벤트 손실 발생
                DispatchQueue.main.async {
                    // 저장 탭 열기 및 스크롤 알림 전송
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenSavedTabNotification"),
                        object: shape.id
                    )
                }
            }
        }
        notificationObservers.append(observer2)

        // 색상 변경 시 지도 오버레이 속성 업데이트
        // MapViewModel의 handleReloadMapOverlays()에서 처리하므로 여기서는 제거
        // 중복 리로드 방지로 터치 반응 안정성 향상

        // 스케치 변경 알림 옵저버
        let observer3 = NotificationCenter.default.addObserver(
            forName: .sketchesDidChange,
            object: nil,
            queue: .main
        ) { [weak viewModel] _ in
            // Task로 래핑하여 View body 렌더링 사이클 외부에서 상태 변경
            Task { @MainActor in
                viewModel?.reloadSketchOverlays()
            }
        }
        notificationObservers.append(observer3)

        // 한국 특화 기능 비활성화 시 모든 비행구역 오버레이 숨기기
        let observer4 = NotificationCenter.default.addObserver(
            forName: Notification.Name("HideAllFlightZones"),
            object: nil,
            queue: .main
        ) { [weak flightZoneManager] _ in
            Task { @MainActor in
                flightZoneManager?.hideAllLayers()
            }
        }
        notificationObservers.append(observer4)

    }
    
    private func removeNotifications() {
        // 🔧 메모리 최적화: 저장된 모든 옵저버 제거
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        // 기존 self 기반 옵저버도 제거 (혹시 남아있을 수 있으므로)
        NotificationCenter.default.removeObserver(self)

        print("♻️ MainView: NotificationCenter 옵저버 \(notificationObservers.count)개 제거됨")
    }
}

#Preview {
    MainView()
}
