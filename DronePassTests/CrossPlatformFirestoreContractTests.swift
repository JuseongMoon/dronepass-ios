//
//  CrossPlatformFirestoreContractTests.swift
//  DronePassTests
//
//  크로스 플랫폼 데이터 계약 테스트.
//  계약 정의: team/DATA_CONTRACT.md, fixture: team/fixtures/*.json
//  Android 대칭 테스트: CrossPlatformFirestoreContractTest.kt (Android 레포)
//

import XCTest
import FirebaseFirestore
@testable import DronePass

final class CrossPlatformFirestoreContractTests: XCTestCase {

    private var store: ShapeFirebaseStore { ShapeFirebaseStore.shared }

    override func setUp() async throws {
        // 테스트 중 우발적 쓰기(레거시 createdAt 마이그레이션 등)가 운영 Firestore에 도달하지 않도록 차단
        try await Firestore.firestore().disableNetwork()
    }

    // MARK: - Fixture 로더

    private enum FixtureError: Error {
        case notFound(String)
        case malformed(String)
    }

    /// team/fixtures/*.json 을 로드해 Firestore 문서 형태([String: Any] + Timestamp)로 변환.
    /// JSONSerialization은 숫자를 NSNumber로 돌려주므로 Firestore SDK의 문서 데이터와 동일하게 브리징된다.
    private func loadFixture(_ name: String) throws -> (documentId: String, fields: [String: Any]) {
        let bundle = Bundle(for: CrossPlatformFirestoreContractTests.self)
        let candidates = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "fixtures"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "team/fixtures"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw FixtureError.notFound(name)
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documentId = json["documentId"] as? String,
              let rawFields = json["fields"] as? [String: Any] else {
            throw FixtureError.malformed(name)
        }
        guard let fields = convertTimestamps(rawFields) as? [String: Any] else {
            throw FixtureError.malformed(name)
        }
        return (documentId, fields)
    }

    /// {"_seconds": N, "_nanoseconds": N} 객체를 Firestore Timestamp로 재귀 치환
    private func convertTimestamps(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            if dict.count == 2,
               let seconds = dict["_seconds"] as? Int64,
               let nanoseconds = dict["_nanoseconds"] as? Int32 {
                return Timestamp(seconds: seconds, nanoseconds: nanoseconds)
            }
            return dict.mapValues { convertTimestamps($0) }
        }
        if let array = value as? [Any] {
            return array.map { convertTimestamps($0) }
        }
        return value
    }

    private func parseFixture(_ name: String) throws -> ShapeModel {
        let (documentId, fields) = try loadFixture(name)
        return try store.parseShapeFromDocument(fields, id: documentId)
    }

    // MARK: - 도형 4종 정본 파싱

    func testCircleFixtureParses() throws {
        let shape = try parseFixture("shape-circle")
        XCTAssertEqual(shape.id.uuidString, "1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D")
        XCTAssertEqual(shape.title, "한강 드론 비행구역")
        XCTAssertEqual(shape.shapeType, .circle)
        XCTAssertEqual(shape.baseCoordinate.latitude, 37.541234, accuracy: 0.0000001)
        XCTAssertEqual(shape.baseCoordinate.longitude, 126.986123, accuracy: 0.0000001)
        XCTAssertEqual(shape.memo, "비행 승인 완료")
        XCTAssertEqual(shape.address, "서울특별시 용산구")
        XCTAssertEqual(shape.color, "#007AFF")
        XCTAssertEqual(shape.radius, 150.5)
        XCTAssertEqual(shape.height, 120.5)
        XCTAssertEqual(shape.droneId, "DRONE-001")
        XCTAssertEqual(shape.createdAt, Date(timeIntervalSince1970: 1_782_864_000))
        XCTAssertEqual(shape.flightStartDate, Date(timeIntervalSince1970: 1_782_900_000))
        XCTAssertEqual(shape.flightEndDate, Date(timeIntervalSince1970: 1_785_456_000))
        // 나노초 보존 (123ms)
        XCTAssertEqual(shape.updatedAt.timeIntervalSince1970, 1_782_907_200.123, accuracy: 0.000001)
        XCTAssertNil(shape.deletedAt)
    }

    func testRectangleFixtureParses() throws {
        let shape = try parseFixture("shape-rectangle")
        XCTAssertEqual(shape.shapeType, .rectangle)
        XCTAssertEqual(shape.secondCoordinate?.latitude, 37.610111)
        XCTAssertEqual(shape.secondCoordinate?.longitude, 126.722222)
        XCTAssertEqual(shape.memo, "")
        XCTAssertEqual(shape.address, "")
        XCTAssertNil(shape.flightEndDate)
        XCTAssertNil(shape.deletedAt)
        XCTAssertNil(shape.radius)
    }

    func testPolygonFixtureParses() throws {
        let shape = try parseFixture("shape-polygon")
        XCTAssertEqual(shape.shapeType, .polygon)
        let coords = try XCTUnwrap(shape.polygonCoordinates)
        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[0].latitude, 37.511111)
        XCTAssertEqual(coords[1].longitude, 127.013333)
        XCTAssertEqual(coords[2].latitude, 37.509999)
        XCTAssertNil(shape.secondCoordinate)
    }

    func testPolylineFixtureParses() throws {
        let shape = try parseFixture("shape-polyline")
        XCTAssertEqual(shape.shapeType, .polyline)
        let coords = try XCTUnwrap(shape.polylineCoordinates)
        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[0].latitude, 36.351234)
        XCTAssertEqual(coords[2].longitude, 127.389012)
        XCTAssertEqual(shape.memo, "구간 A-B")
    }

    // MARK: - 소프트삭제 / Android 작성 형태

    func testSoftDeletedFixtureParsesTombstone() throws {
        let shape = try parseFixture("shape-soft-deleted")
        XCTAssertEqual(shape.deletedAt, Date(timeIntervalSince1970: 1_782_950_400))
        XCTAssertEqual(shape.updatedAt, shape.deletedAt)
        // 정수 JSON(radius: 80)도 Double로 파싱 (NSNumber 브리징)
        XCTAssertEqual(shape.radius, 80.0)
    }

    /// Android는 활성 도형에 deletedAt 키를 아예 쓰지 않는다 (커밋 e65feb60 회귀 케이스)
    func testAndroidActiveShapeWithoutDeletedAtKeyParsesAsActive() throws {
        let (documentId, fields) = try loadFixture("shape-android-active")
        XCTAssertNil(fields["deletedAt"], "fixture 전제: deletedAt 키 자체가 없어야 함")
        let shape = try store.parseShapeFromDocument(fields, id: documentId)
        XCTAssertNil(shape.deletedAt)
        // Android가 정수로 쓴 숫자 필드도 파싱되어야 함
        XCTAssertEqual(shape.radius, 200.0)
        XCTAssertEqual(shape.height, 100.0)
    }

    // MARK: - 레거시(구 iOS) 데이터 관용

    func testLegacyFixtureParsesWithFallbacks() throws {
        let shape = try parseFixture("shape-legacy")
        // shapeType "Circle" → lowercased 관용
        XCTAssertEqual(shape.shapeType, .circle)
        // startedAt → flightStartDate, expireDate → flightEndDate
        XCTAssertEqual(shape.flightStartDate, Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertEqual(shape.flightEndDate, Date(timeIntervalSince1970: 1_755_000_000))
        // createdAt 부재 → flightStartDate 값, updatedAt 부재 → createdAt 값
        XCTAssertEqual(shape.createdAt, shape.flightStartDate)
        XCTAssertEqual(shape.updatedAt, shape.createdAt)
        // memo/address 부재 허용
        XCTAssertNil(shape.memo)
        XCTAssertNil(shape.address)
    }

    func testShapeTypeIsCaseInsensitive() throws {
        var (documentId, fields) = try loadFixture("shape-circle")
        fields["shapeType"] = "CIRCLE"
        let shape = try store.parseShapeFromDocument(fields, id: documentId)
        XCTAssertEqual(shape.shapeType, .circle)
    }

    func testMissingUpdatedAtFallsBackToCreatedAt() throws {
        var (documentId, fields) = try loadFixture("shape-circle")
        fields.removeValue(forKey: "updatedAt")
        let shape = try store.parseShapeFromDocument(fields, id: documentId)
        XCTAssertEqual(shape.updatedAt, shape.createdAt)
    }

    // MARK: - 거부 규칙

    /// 미상 shapeType은 circle로 강제하지 않고 해당 문서를 거부(skip)한다
    func testUnknownShapeTypeIsRejected() throws {
        var (documentId, fields) = try loadFixture("shape-circle")
        fields["shapeType"] = "hexagon"
        XCTAssertThrowsError(try store.parseShapeFromDocument(fields, id: documentId))
    }

    /// 좌표는 {latitude, longitude} 맵이어야 하며 GeoPoint는 거부된다
    func testGeoPointBaseCoordinateIsRejected() throws {
        var (documentId, fields) = try loadFixture("shape-circle")
        fields["baseCoordinate"] = GeoPoint(latitude: 37.5, longitude: 127.0)
        XCTAssertThrowsError(try store.parseShapeFromDocument(fields, id: documentId))
    }

    // MARK: - 쓰기(인코딩) 계약

    func testEncodingProducesContractShape() throws {
        let id = UUID()
        let shape = ShapeModel(
            id: id,
            title: "인코딩 검증",
            shapeType: .circle,
            baseCoordinate: CoordinateManager(latitude: 37.1234567891, longitude: 127.9876543219),
            createdAt: Date(timeIntervalSince1970: 1_782_864_000),
            flightStartDate: Date(timeIntervalSince1970: 1_782_900_000),
            color: "#007AFF",
            updatedAt: Date(timeIntervalSince1970: 1_782_907_200)
        )
        let data = try store.shapeToFirestoreData(shape)

        // id는 대문자 UUID, shapeType은 소문자 문자열
        XCTAssertEqual(data["id"] as? String, id.uuidString)
        XCTAssertEqual(id.uuidString, id.uuidString.uppercased())
        XCTAssertEqual(data["shapeType"] as? String, "circle")

        // 좌표는 6자리 반올림된 {latitude, longitude} 맵
        let coord = try XCTUnwrap(data["baseCoordinate"] as? [String: Double])
        XCTAssertEqual(try XCTUnwrap(coord["latitude"]), 37.123457, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(coord["longitude"]), 127.987654, accuracy: 0.0000001)

        // memo/address는 nil이어도 항상 "" 로 존재
        XCTAssertEqual(data["memo"] as? String, "")
        XCTAssertEqual(data["address"] as? String, "")

        // 날짜는 전부 Firestore Timestamp
        XCTAssertTrue(data["createdAt"] is Timestamp)
        XCTAssertTrue(data["flightStartDate"] is Timestamp)
        XCTAssertTrue(data["updatedAt"] is Timestamp)

        // 값 없는 선택 필드는 키 자체가 없어야 한다
        for absentKey in ["flightEndDate", "deletedAt", "droneId", "radius",
                          "secondCoordinate", "polygonCoordinates", "polylineCoordinates", "height"] {
            XCTAssertNil(data[absentKey], "선택 필드 \(absentKey)는 nil일 때 키가 없어야 함")
        }
    }

    // MARK: - 왕복 무손실

    func testEncodeDecodeRoundTripPreservesAllShapeTypes() throws {
        let createdAt = Date(timeIntervalSince1970: 1_782_864_000)
        let start = Date(timeIntervalSince1970: 1_782_900_000)
        let end = Date(timeIntervalSince1970: 1_785_456_000)
        let updatedAt = Date(timeIntervalSince1970: 1_782_907_200)

        let shapes: [ShapeModel] = [
            ShapeModel(
                title: "왕복-원", shapeType: .circle,
                baseCoordinate: CoordinateManager(latitude: 37.541234, longitude: 126.986123),
                radius: 150.5, height: 120.5, memo: "메모", address: "주소",
                createdAt: createdAt, flightStartDate: start, flightEndDate: end,
                color: "#007AFF", droneId: "DRONE-001", updatedAt: updatedAt
            ),
            ShapeModel(
                title: "왕복-사각형", shapeType: .rectangle,
                baseCoordinate: CoordinateManager(latitude: 37.615321, longitude: 126.715654),
                secondCoordinate: CoordinateManager(latitude: 37.610111, longitude: 126.722222),
                memo: "", address: "",
                createdAt: createdAt, flightStartDate: start,
                color: "#FF3B30", updatedAt: updatedAt
            ),
            ShapeModel(
                title: "왕복-다각형", shapeType: .polygon,
                baseCoordinate: CoordinateManager(latitude: 37.511111, longitude: 127.011111),
                polygonCoordinates: [
                    CoordinateManager(latitude: 37.511111, longitude: 127.011111),
                    CoordinateManager(latitude: 37.512222, longitude: 127.013333),
                    CoordinateManager(latitude: 37.509999, longitude: 127.014444),
                ],
                memo: "", address: "",
                createdAt: createdAt, flightStartDate: start,
                color: "#34C759", updatedAt: updatedAt
            ),
            ShapeModel(
                title: "왕복-폴리라인", shapeType: .polyline,
                baseCoordinate: CoordinateManager(latitude: 36.351234, longitude: 127.384567),
                polylineCoordinates: [
                    CoordinateManager(latitude: 36.351234, longitude: 127.384567),
                    CoordinateManager(latitude: 36.353456, longitude: 127.386789),
                ],
                memo: "", address: "",
                createdAt: createdAt, flightStartDate: start,
                color: "#FF9500", updatedAt: updatedAt
            ),
        ]

        for original in shapes {
            let encoded = try store.shapeToFirestoreData(original)
            let decoded = try store.parseShapeFromDocument(encoded, id: original.id.uuidString)
            XCTAssertEqual(decoded, original, "\(original.title) 왕복 시 데이터 손실")
        }
    }

    // MARK: - 전체 fixture 무결성

    func testAllFixturesParseAndPreserveDocumentIdentity() throws {
        let fixtureNames = [
            "shape-circle", "shape-rectangle", "shape-polygon", "shape-polyline",
            "shape-soft-deleted", "shape-android-active", "shape-legacy",
        ]
        for name in fixtureNames {
            let (documentId, fields) = try loadFixture(name)
            let shape = try store.parseShapeFromDocument(fields, id: documentId)
            // 문서 ID = id 필드 = 대문자 UUID
            XCTAssertEqual(shape.id.uuidString, documentId, "\(name): 문서 ID와 id 필드 불일치")
            XCTAssertEqual(documentId, documentId.uppercased(), "\(name): 문서 ID가 대문자가 아님")
        }
    }
}
