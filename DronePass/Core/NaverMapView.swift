//
//  NaverMapView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//


import SwiftUI
import NMapsMap
import CoreLocation

struct NaverMapView: UIViewRepresentable {
    @Binding var mapView: NMFMapView?
    var onMapViewCreated: (NMFMapView) -> Void
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    
    func makeUIView(context: Context) -> NMFNaverMapView {
        let naverMapView = NMFNaverMapView()
        naverMapView.showLocationButton = true
        naverMapView.mapView.touchDelegate = context.coordinator
        naverMapView.mapView.addCameraDelegate(delegate: context.coordinator)
        
        // 현재 위치 오버레이 활성화
        naverMapView.mapView.locationOverlay.hidden = false
        
        // 현재 위치를 초기 카메라 위치로 설정
        let initialPosition: NMFCameraPosition
        
        if let currentLocation = LocationManager.shared.currentLocation {
            // 현재 위치가 있으면 현재 위치로 설정
            let latLng = NMGLatLng(lat: currentLocation.coordinate.latitude, lng: currentLocation.coordinate.longitude)
            initialPosition = NMFCameraPosition(latLng, zoom: 12)
            
            // 현재 위치 오버레이 위치 설정
            naverMapView.mapView.locationOverlay.location = latLng
        } else {
            // 현재 위치가 없으면 서울 중심을 기본값으로 사용
            let seoulPosition = NMGLatLng(lat: 37.575563, lng: 126.976793)
            initialPosition = NMFCameraPosition(seoulPosition, zoom: 12)
            
            // 위치 업데이트를 시작하고 위치가 업데이트되면 카메라 이동
            LocationManager.shared.startUpdatingLocation()
            
            // 위치 업데이트 알림을 받아서 카메라 이동 및 현재 위치 표시
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("LocationDidUpdate"),
                object: nil,
                queue: .main
            ) { notification in
                if let location = notification.userInfo?["location"] as? CLLocation {
                    let currentLatLng = NMGLatLng(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
                    let currentPosition = NMFCameraPosition(currentLatLng, zoom: 12)
                    
                    // 카메라 이동
                    naverMapView.mapView.moveCamera(NMFCameraUpdate(position: currentPosition))
                    
                    // 현재 위치 오버레이 위치 설정
                    naverMapView.mapView.locationOverlay.location = currentLatLng
                }
            }
        }
        
        naverMapView.mapView.moveCamera(NMFCameraUpdate(position: initialPosition))

        // 🔧 지도 UI 컨트롤 위치 조정 (내 위치 버튼, 네이버 로고, 축척 표시)
        // 하단 여백을 추가하여 탭바와 겹치지 않도록 위로 이동
        naverMapView.mapView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: -33,  // 탭바 높이를 고려한 하단 여백 (필요시 조정 가능)
            right: 0
        )

        // DispatchQueue.main.async로 지연하여 View body 렌더링 사이클 외부에서 상태 변경
        DispatchQueue.main.async {
            self.mapView = naverMapView.mapView
            self.onMapViewCreated(naverMapView.mapView)
        }

        return naverMapView
    }
    
    func updateUIView(_ uiView: NMFNaverMapView, context: Context) {
        // 필요한 경우 여기서 업데이트 로직 구현
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NMFMapViewTouchDelegate, NMFMapViewCameraDelegate {
        var parent: NaverMapView

        init(_ parent: NaverMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: NMFMapView, didTapMap latlng: NMGLatLng, point: CGPoint) {
            // 지도 탭 이벤트 (필요 시 구현)
        }

        func mapView(_ mapView: NMFMapView, didLongTapMap latlng: NMGLatLng, point: CGPoint) {
            parent.onLongPress?(CLLocationCoordinate2D(latitude: latlng.lat, longitude: latlng.lng))
        }

        // POI 심볼 터치 비활성화
        // 오버레이 위에 있는 POI 라벨을 터치해도 이벤트를 소비하여 아무 동작도 하지 않음
        func mapView(_ mapView: NMFMapView, didTap symbol: NMFSymbol) -> Bool {
            // true를 반환하여 이벤트를 소비하고 POI 터치를 비활성화
            return true
        }

        // MARK: - NMFMapViewCameraDelegate

        func mapView(_ mapView: NMFMapView, cameraDidChangeByReason reason: Int, animated: Bool) {
            // 카메라 이동 완료 시 알림 발송
            NotificationCenter.default.post(name: Notification.Name("MapCameraDidChange"), object: nil)
        }
    }
} 
