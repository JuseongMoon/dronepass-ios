//
//  DroneModel.swift
//  DronePass
//
//  Created by Claude on 2025-09-30.
//

// 역할: 드론 데이터 모델
// 연관기능: 다중 드론 관리, 색상 관리, Firebase 동기화

import Foundation

public struct DroneModel: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var color: String
    public var serialNumber: String?
    public var takeoffWeight: String?
    public var size: String?
    public var memo: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public var isDeleted: Bool {
        return deletedAt != nil
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        color: String,
        serialNumber: String? = nil,
        takeoffWeight: String? = nil,
        size: String? = nil,
        memo: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.serialNumber = serialNumber
        self.takeoffWeight = takeoffWeight
        self.size = size
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    // MARK: - 색상 관련 헬퍼

    /// PaletteColor enum에서 색상 찾기
    public var paletteColor: PaletteColor? {
        return PaletteColor.allCases.first { $0.rawValue.lowercased() == color.lowercased() }
    }

    /// 유효한 팔레트 색상인지 확인
    public var isValidPaletteColor: Bool {
        return paletteColor != nil
    }

    // MARK: - 편의 생성자

    /// 기본 드론 생성 (첫 번째 사용자용)
    public static func createDefault() -> DroneModel {
        return DroneModel(
            name: NSLocalizedString("drone.edit.defaultName.first", comment: "My Drone"),
            color: PaletteColor.blue.rawValue
        )
    }

    /// 새로운 드론 생성 (다음 색상으로)
    public static func createNew(withColor color: PaletteColor, index: Int) -> DroneModel {
        let format = NSLocalizedString("drone.edit.defaultName", comment: "Drone %d")
        return DroneModel(
            name: String(format: format, index + 1),
            color: color.rawValue
        )
    }

    // MARK: - 수정 메서드

    /// 드론 정보 업데이트
    public mutating func update(name: String? = nil, color: String? = nil, serialNumber: String? = nil, takeoffWeight: String? = nil, size: String? = nil, memo: String? = nil) {
        if let name = name {
            self.name = name
        }
        if let color = color {
            self.color = color
        }
        if let serialNumber = serialNumber {
            self.serialNumber = serialNumber
        }
        if let takeoffWeight = takeoffWeight {
            self.takeoffWeight = takeoffWeight
        }
        if let size = size {
            self.size = size
        }
        if let memo = memo {
            self.memo = memo
        }
        self.updatedAt = Date()
    }

    /// 소프트 삭제
    public mutating func softDelete() {
        self.deletedAt = Date()
        self.updatedAt = Date()
    }

    /// 삭제 취소
    public mutating func restore() {
        self.deletedAt = nil
        self.updatedAt = Date()
    }
}

// MARK: - Collection 확장

extension Array where Element == DroneModel {
    /// 활성 드론들만 필터링
    public var active: [DroneModel] {
        return self.filter { !$0.isDeleted }
    }

    /// 이름으로 드론 찾기
    public func drone(withName name: String) -> DroneModel? {
        return self.active.first { $0.name == name }
    }

    /// ID로 드론 찾기
    public func drone(withId id: String) -> DroneModel? {
        return self.active.first { $0.id == id }
    }
}