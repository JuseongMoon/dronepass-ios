//
//  ShapeManager.swift
//  DronePass
//
//  Created by 문주성 on 5/19/25.
//

import Foundation
import CoreLocation
import Combine

// 도형 데이터를 저장하기 위한 모델
struct Shape: Codable {
    let id: String
    let name: String
    var endDate: Date?
    var coordinate: CLLocationCoordinate2D
    
    // CLLocationCoordinate2D는 Codable을 준수하지 않아서 별도로 인코딩/디코딩
    enum CodingKeys: String, CodingKey {
        case id, name, endDate, latitude, longitude
    }
    
    init(id: String, name: String, endDate: Date?, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.endDate = endDate
        self.coordinate = coordinate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
}


final class ShapeUserDefaultsStore {
    
    static let shared = ShapeUserDefaultsStore()
    private init() {
        loadShapes()
    }
    
    @Published private(set) var shapes: [Shape] = []
    private let shapesKey = "savedShapes"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Methods
    
    func getAllShapes() -> [Shape] {
        return shapes
    }
    
    func addShape(_ shape: Shape) {
        shapes.append(shape)
        saveShapes()
    }
    
    func removeShape(withId id: String) {
        shapes.removeAll { $0.id == id }
        saveShapes()
    }
    
    func updateShape(_ shape: Shape) {
        if let index = shapes.firstIndex(where: { $0.id == shape.id }) {
            shapes[index] = shape
            saveShapes()
        }
    }
    
    func deleteExpiredShapes() {
        let now = Date()
        shapes.removeAll { shape in
            if let endDate = shape.endDate {
                return endDate < now
            }
            return false
        }
        saveShapes()
        NotificationCenter.default.post(name: .shapesDidChange, object: nil)
    }
    
    func clearAll() {
        shapes.removeAll()
        saveShapes()
        NotificationCenter.default.post(name: .shapesDidChange, object: nil)
    }
    
    // MARK: - Private Methods
    
    private func saveShapes() {
        do {
            let data = try JSONEncoder().encode(shapes)
            UserDefaults.standard.set(data, forKey: shapesKey)
        } catch {
            print("도형 데이터 저장 실패: \(error.localizedDescription)")
        }
    }
    
    private func loadShapes() {
        guard let data = UserDefaults.standard.data(forKey: shapesKey) else { return }
        do {
            shapes = try JSONDecoder().decode([Shape].self, from: data)
        } catch {
            print("도형 데이터 로드 실패: \(error.localizedDescription)")
        }
    }
}
