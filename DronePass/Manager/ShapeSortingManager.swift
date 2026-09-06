//
//  ShapeSortingManager.swift
//  DronePass
//
//  Created by 문주성 on 7/29/25.
//

import Foundation
import SwiftUI

// ShapeModel을 사용하기 위한 import
import CoreLocation

// MARK: - Sort Options
enum SortOption: String, CaseIterable {
    case title = "title"
    case dateCreated = "dateCreated"
    case flightStartDate = "flightStartDate"
    case flightEndDate = "flightEndDate"

    var icon: String {
        switch self {
        case .title: return "textformat"
        case .dateCreated: return "calendar"
        case .flightStartDate: return "airplane.departure"
        case .flightEndDate: return "airplane.arrival"
        }
    }

    var localizedName: String {
        switch self {
        case .title:
            return NSLocalizedString("sort.option.title", comment: "By Title")
        case .dateCreated:
            return NSLocalizedString("sort.option.dateCreated", comment: "By Date Created")
        case .flightStartDate:
            return NSLocalizedString("sort.option.flightStartDate", comment: "By Flight Start Date")
        case .flightEndDate:
            return NSLocalizedString("sort.option.flightEndDate", comment: "By Flight End Date")
        }
    }
}

// MARK: - Sort Direction
enum SortDirection: String, CaseIterable {
    case ascending = "ascending"
    case descending = "descending"

    var icon: String {
        switch self {
        case .ascending: return "arrow.down"
        case .descending: return "arrow.up"
        }
    }

    var localizedName: String {
        switch self {
        case .ascending:
            return NSLocalizedString("sort.direction.ascending", comment: "Ascending")
        case .descending:
            return NSLocalizedString("sort.direction.descending", comment: "Descending")
        }
    }

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

// MARK: - Shape Sorting Manager
final class ShapeSortingManager: ObservableObject {
    static let shared = ShapeSortingManager()
    
    // 초기화 중 저장 방지를 위한 플래그
    private var isInitializing = false
    
    @Published var selectedSortOption: SortOption = .title {
        didSet {
            if !isInitializing {
                saveSortSettings()
            }
        }
    }
    @Published var sortDirection: SortDirection = .ascending {
        didSet {
            if !isInitializing {
                saveSortSettings()
            }
        }
    }
    
    // MARK: - UserDefaults Keys
    private enum UserDefaultsKeys {
        static let selectedSortOption = "ShapeSortingManager.selectedSortOption"
        static let sortDirection = "ShapeSortingManager.sortDirection"
    }
    
    private init() {
        isInitializing = true
        loadSortSettings()
        isInitializing = false
    }
    
    // MARK: - UserDefaults Management
    private func saveSortSettings() {
        UserDefaults.standard.set(selectedSortOption.rawValue, forKey: UserDefaultsKeys.selectedSortOption)
        UserDefaults.standard.set(sortDirection.rawValue, forKey: UserDefaultsKeys.sortDirection)
        print("💾 ShapeSortingManager: 정렬 설정 저장 - \(selectedSortOption.rawValue), \(sortDirection.rawValue)")
    }
    
    private func loadSortSettings() {
        // 정렬 옵션 로드
        if let sortOptionString = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedSortOption),
           let sortOption = SortOption(rawValue: sortOptionString) {
            selectedSortOption = sortOption
        }
        
        // 정렬 방향 로드
        if let sortDirectionString = UserDefaults.standard.string(forKey: UserDefaultsKeys.sortDirection),
           let sortDirection = SortDirection(rawValue: sortDirectionString) {
            self.sortDirection = sortDirection
        }
        
        print("📱 ShapeSortingManager: 정렬 설정 로드 - \(selectedSortOption.rawValue), \(sortDirection.rawValue)")
    }
    
    // MARK: - Sorting Logic
    func sortShapes(_ shapes: [ShapeModel]) -> [ShapeModel] {
        let sortedShapes = shapes.sorted { first, second in
            // 주 정렬 기준에 따른 비교
            let primaryComparison: ComparisonResult

            switch selectedSortOption {
            case .title:
                primaryComparison = first.title.localizedCompare(second.title)
            case .dateCreated:
                primaryComparison = first.createdAt.compare(second.createdAt)
            case .flightStartDate:
                primaryComparison = first.flightStartDate.compare(second.flightStartDate)
            case .flightEndDate:
                let firstEndDate = first.flightEndDate ?? Date.distantFuture
                let secondEndDate = second.flightEndDate ?? Date.distantFuture
                primaryComparison = firstEndDate.compare(secondEndDate)
            }

            // 주 정렬 기준이 같지 않으면 그 결과를 반환
            if primaryComparison != .orderedSame {
                return sortDirection == .ascending ?
                    (primaryComparison == .orderedAscending) :
                    (primaryComparison == .orderedDescending)
            }

            // 보조 정렬 기준 적용
            let secondaryComparison: ComparisonResult

            switch selectedSortOption {
            case .title:
                // 제목순의 경우: 비행시작일순 → 주소순
                secondaryComparison = first.flightStartDate.compare(second.flightStartDate)
                if secondaryComparison != .orderedSame {
                    return sortDirection == .ascending ?
                        (secondaryComparison == .orderedAscending) :
                        (secondaryComparison == .orderedDescending)
                }
                // 마지막: 주소순
                let firstAddress = first.address ?? ""
                let secondAddress = second.address ?? ""
                let addressComparison = firstAddress.localizedCompare(secondAddress)
                return sortDirection == .ascending ?
                    (addressComparison == .orderedAscending) :
                    (addressComparison == .orderedDescending)
            case .dateCreated, .flightStartDate, .flightEndDate:
                // 생성일순, 비행시작일순, 비행종료일순의 경우: 제목순 → 주소순
                let titleComparison = first.title.localizedCompare(second.title)
                if titleComparison != .orderedSame {
                    return sortDirection == .ascending ?
                        (titleComparison == .orderedAscending) :
                        (titleComparison == .orderedDescending)
                }
                // 마지막: 주소순
                let firstAddress = first.address ?? ""
                let secondAddress = second.address ?? ""
                let addressComparison = firstAddress.localizedCompare(secondAddress)
                return sortDirection == .ascending ?
                    (addressComparison == .orderedAscending) :
                    (addressComparison == .orderedDescending)
            }
        }

        return sortedShapes
    }
    
    // MARK: - Active, Not Started, and Expired Shapes with Sorting
    func getNotStartedShapes(_ allShapes: [ShapeModel]) -> [ShapeModel] {
        let notStartedShapes = allShapes.filter { shape in
            return shape.isNotStarted
        }
        return sortShapes(notStartedShapes)
    }

    func getActiveShapes(_ allShapes: [ShapeModel]) -> [ShapeModel] {
        let activeShapes = allShapes.filter { shape in
            // 시작 전 도형 제외
            if shape.isNotStarted { return false }
            // 만료된 도형 제외
            guard let endDate = shape.flightEndDate else { return true }
            return endDate > Date()
        }
        return sortShapes(activeShapes)
    }

    func getExpiredShapes(_ allShapes: [ShapeModel]) -> [ShapeModel] {
        let expiredShapes = allShapes.filter { shape in
            guard let endDate = shape.flightEndDate else { return false }
            return endDate <= Date()
        }
        return sortShapes(expiredShapes)
    }
    
    // MARK: - Sort Option Management
    func setSortOption(_ option: SortOption) {
        selectedSortOption = option
    }
    
    func toggleSortDirection() {
        sortDirection = sortDirection == .ascending ? .descending : .ascending
    }

    func cycleSortOption() {
        let allOptions = SortOption.allCases
        if let currentIndex = allOptions.firstIndex(of: selectedSortOption) {
            let nextIndex = (currentIndex + 1) % allOptions.count
            selectedSortOption = allOptions[nextIndex]
        }
    }

    func resetToDefault() {
        selectedSortOption = .title
        sortDirection = .ascending
    }
    
    // MARK: - Current Sort Option Display
    var currentSortOptionDisplay: String {
        return "\(selectedSortOption.rawValue) \(sortDirection.rawValue)"
    }
}
