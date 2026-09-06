//
//  SearchAddressViewModel.swift
//  DronePass
//
//  Created by 문주성 on 7/22/25.
//

import SwiftUI
import Combine
import Foundation
import MapKit

class SearchAddressViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var addresses: [NaverDetailAddress] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("[주소검색] ViewModel 초기화")
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .sink { [weak self] searchText in
                print("[주소검색] 검색어 변경 감지: \(searchText)")
                Task { @MainActor in
                    await self?.searchAddress(query: searchText)
                }
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    func searchAddress(query: String) async {
        print("[주소검색] searchAddress 호출: \(query)")
        isSearching = true
        errorMessage = nil
        
        do {
            let addresses = try await NaverGeocodingService.shared.geocode(address: query)
            self.addresses = addresses
            self.isSearching = false
        } catch {
            self.errorMessage = "검색 중 오류가 발생했습니다: \(error.localizedDescription)"
            self.isSearching = false
            print("[주소검색] 에러 발생: \(error)")
        }
    }
}
