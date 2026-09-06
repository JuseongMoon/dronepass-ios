import Foundation

protocol ShapeStoreProtocol<ShapeType> {
    associatedtype ShapeType
    func loadShapes() async throws -> [ShapeType]
    func saveShapes(_ shapes: [ShapeType]) async throws
    func addShape(_ shape: ShapeType) async throws
    func removeShape(id: UUID) async throws
    func updateShape(_ shape: ShapeType) async throws
    func deleteExpiredShapes() async throws
} 
