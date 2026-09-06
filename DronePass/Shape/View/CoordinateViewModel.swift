//
//  SearchCoordinateViewModel.swift
//  DronePass
//
//  Created by 문주성 on 7/22/25.
//

import Foundation

public class SearchCoordinateViewModel: ObservableObject {
    @Published var coordinateText: String = ""
    @Published var coordinateValidation: String = ""
    @Published var isCoordinateValid = true
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var address: String?
    @Published var parsedCoordinate: CoordinateManager?
    @Published var showAddressNotFoundAlert = false
    
    func validateAndSearch() async {
        if let coordinate = CoordinateManager.parse(coordinateText) {
            coordinateValidation = NSLocalizedString("coordinate.validation.valid", comment: "Valid coordinate format")
            isCoordinateValid = true
            parsedCoordinate = coordinate

            // Reverse Geocoding 수행
            await reverseGeocode(coordinate: coordinate)
        } else {
            coordinateValidation = NSLocalizedString("coordinate.validation.invalid", comment: "Invalid coordinate format")
            isCoordinateValid = false
            address = nil
            parsedCoordinate = nil
        }
    }
    
    @MainActor
    private func reverseGeocode(coordinate: CoordinateManager) async {
        isSearching = true
        errorMessage = nil
        address = nil
        
        do {
            // Double 타입의 위도, 경도 값을 직접 전달
            let address = try await NaverGeocodingService.shared.reverseGeocode(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            self.address = address
        } catch {
            // 주소 검색 실패 시 알림창 표시
            self.showAddressNotFoundAlert = true
            print("[좌표검색] 에러 발생: \(error)")
        }
        
        isSearching = false
    }
}
