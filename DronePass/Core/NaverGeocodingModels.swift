//
//  NaverGeocodingModels.swift
//  DronePass
//
//  Created by 문주성 on 6/18/25.
//

import Foundation

// MARK: - Naver Geocoding Models

// MARK: - NaverGeocodeResponse
struct NaverGeocodeResponse: Codable {
    let status: String
    let meta: Meta
    let addresses: [NaverDetailAddress]
    let errorMessage: String
    
    enum CodingKeys: String, CodingKey {
        case status
        case meta
        case addresses
        case errorMessage
    }
}

// MARK: - Meta
struct Meta: Codable {
    let totalCount: Int
    let page: Int
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case totalCount = "totalCount"
        case page
        case count
    }
}

// MARK: - NaverDetailAddress
struct NaverDetailAddress: Codable, Identifiable {
    let roadAddress: String
    let jibunAddress: String
    let englishAddress: String?
    let addressElements: [AddressElement]
    let x: String // 경도
    let y: String // 위도
    let distance: Double
    
    var id: String { roadAddress }
    
    enum CodingKeys: String, CodingKey {
        case roadAddress
        case jibunAddress
        case englishAddress
        case addressElements
        case x
        case y
        case distance
    }
}

// MARK: - AddressElement
struct AddressElement: Codable {
    let types: [String]
    let longName: String
    let shortName: String
    let code: String
    
    enum CodingKeys: String, CodingKey {
        case types
        case longName
        case shortName
        case code
    }
    
    // 주소 요소 타입 상수
    struct Types {
        static let sido = "SIDO"
        static let sigugun = "SIGUGUN"
        static let dongmyun = "DONGMYUN"
        static let ri = "RI"
        static let roadName = "ROAD_NAME"
        static let buildingNumber = "BUILDING_NUMBER"
        static let buildingName = "BUILDING_NAME"
        static let landNumber = "LAND_NUMBER"
        static let postalCode = "POSTAL_CODE"
    }
}

// MARK: - Helper Extensions
extension NaverDetailAddress {
    // 시도 정보 가져오기
    var sido: String? {
        addressElements.first { $0.types.contains(AddressElement.Types.sido) }?.longName
    }
    
    // 시군구 정보 가져오기
    var sigugun: String? {
        addressElements.first { $0.types.contains(AddressElement.Types.sigugun) }?.longName
    }
    
    // 동면 정보 가져오기
    var dongmyun: String? {
        addressElements.first { $0.types.contains(AddressElement.Types.dongmyun) }?.longName
    }
    
    // 도로명 가져오기
    var roadName: String? {
        addressElements.first { $0.types.contains(AddressElement.Types.roadName) }?.longName
    }
    
    // 건물번호 가져오기
    var buildingNumber: String? {
        addressElements.first { $0.types.contains(AddressElement.Types.buildingNumber) }?.longName
    }
    
    // 건물명 가져오기
    var buildingName: String? {
        addressElements.first { $0.types.contains(AddressElement.Types.buildingName) }?.longName
    }
    
    // 우편번호 가져오기
    var postalCode: String? {
        addressElements.first { $0.types.contains(AddressElement.Types.postalCode) }?.longName
    }
    
    // 좌표를 Double로 변환
    var coordinate: (latitude: Double, longitude: Double)? {
        guard let latitude = Double(y),
              let longitude = Double(x) else {
            return nil
        }
        return (latitude, longitude)
    }
    
    // 전체 주소를 포맷팅된 문자열로 반환
    var formattedAddress: String {
        var components: [String] = []
        
        if let sido = sido {
            components.append(sido)
        }
        if let sigugun = sigugun {
            components.append(sigugun)
        }
        if let dongmyun = dongmyun {
            components.append(dongmyun)
        }
        if let roadName = roadName {
            components.append(roadName)
        }
        if let buildingNumber = buildingNumber {
            components.append(buildingNumber)
        }
        if let buildingName = buildingName {
            components.append(buildingName)
        }
        
        return components.joined(separator: " ")
    }
}

// MARK: - Usage Example
extension NaverGeocodeResponse {
    static func decode(from jsonData: Data) throws -> NaverGeocodeResponse {
        let decoder = JSONDecoder()
        return try decoder.decode(NaverGeocodeResponse.self, from: jsonData)
    }
    
    // 사용 예시
    static func example() {
        let jsonString = """
        {
            "status": "OK",
            "meta": {
                "totalCount": 1,
                "page": 1,
                "count": 1
            },
            "addresses": [
                {
                    "roadAddress": "경기도 성남시 분당구 불정로 6 NAVER그린팩토리",
                    "jibunAddress": "경기도 성남시 분당구 정자동 178-1 NAVER그린팩토리",
                    "englishAddress": "6, Buljeong-ro, Bundang-gu, Seongnam-si, Gyeonggi-do, Republic of Korea",
                    "addressElements": [
                        {
                            "types": ["SIDO"],
                            "longName": "경기도",
                            "shortName": "경기도",
                            "code": ""
                        }
                    ],
                    "x": "127.1054328",
                    "y": "37.3595963",
                    "distance": 0.0
                }
            ],
            "errorMessage": ""
        }
        """
        
        if let jsonData = jsonString.data(using: .utf8) {
            do {
                let response = try NaverGeocodeResponse.decode(from: jsonData)
                print("Status: \(response.status)")
                print("Total Count: \(response.meta.totalCount)")
                
                if let firstAddress = response.addresses.first {
                    print("Road Address: \(firstAddress.roadAddress)")
                    print("Coordinates: \(String(describing: firstAddress.coordinate))")
                    print("Formatted Address: \(firstAddress.formattedAddress)")
                }
            } catch {
                print("Decoding error: \(error)")
            }
        }
    }
}
