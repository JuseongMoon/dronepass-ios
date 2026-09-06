//
//  LocationManager.swift
//  DronePass
//
//  Created by 문주성 on 5/19/25.
//




import Foundation
import CoreLocation

final class LocationManager: NSObject {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    private(set) var currentLocation: CLLocation?
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        // GPS 없는 기기(Wi-Fi 전용 iPad)에서도 일관된 위치를 받기 위해
        // 정확도 요구사항을 낮춤 (날씨 정보는 100m 정도 오차는 무방)
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        stopUpdatingLocation()
        
        // 위치 업데이트 알림 전송
        NotificationCenter.default.post(
            name: NSNotification.Name("LocationDidUpdate"),
            object: nil,
            userInfo: ["location": location]
        )
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("위치 업데이트 실패: \(error.localizedDescription)")
    }
} 
