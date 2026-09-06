//
//  NaverGeocodingService.swift
//  DronePass
//
//  Created by 문주성 on 5/24/25.
//


import Foundation // 네트워크 통신 등 기본 기능을 위해 Foundation 프레임워크를 가져옵니다.


// MARK: - Models
struct NaverGeocodingResponse: Codable {
    let status: String
    let addresses: [NaverAddress]?
    let error: NaverErrorResponse?
    
    struct NaverErrorResponse: Codable {
        let errorCode: String
        let message: String
        let details: String
    }
}

struct NaverAddress: Codable {
    let roadAddress: String
    let jibunAddress: String
    let englishAddress: String?
    let x: String
    let y: String
    
    // NaverDetailAddress로 변환하는 메서드
    func toDetailAddress() -> NaverDetailAddress {
        return NaverDetailAddress(
            roadAddress: roadAddress,
            jibunAddress: jibunAddress,
            englishAddress: englishAddress,
            addressElements: [], // 기본값으로 빈 배열 사용
            x: x,
            y: y,
            distance: 0.0 // 기본값으로 0.0 사용
        )
    }
}

struct NaverReverseGeocodingResponse: Codable {
    let status: Status
    let results: [NaverResult]?
    
    struct Status: Codable {
        let code: Int
        let name: String
        let message: String
    }
    
    struct NaverResult: Codable {
        let name: String
        let code: Code?
        let region: Region
        let land: Land
        
        struct Code: Codable {
            let id: String
            let type: String
            let mappingId: String
        }
        
        struct Region: Codable {
            let area0: Area
            let area1: Area
            let area2: Area
            let area3: Area
            let area4: Area
            
            struct Area: Codable {
                let name: String
                let coords: Coords?
                let alias: String?
                
                struct Coords: Codable {
                    let center: Center
                    
                    struct Center: Codable {
                        let crs: String
                        let x: Double
                        let y: Double
                    }
                }
            }
        }
        
        struct Land: Codable {
            let type: String
            let number1: String
            let number2: String
            let addition0: Addition
            let addition1: Addition
            let addition2: Addition
            let name: String?
            
            struct Addition: Codable {
                let type: String
                let value: String
            }
        }
    }
}

// MARK: - Service
final class NaverGeocodingService {
    // 싱글톤 패턴: 앱 전체에서 이 서비스 인스턴스를 하나만 공유합니다.
    static let shared = NaverGeocodingService()
    
    // URLSession: 네트워크 통신을 담당하는 객체입니다.
    private let session = URLSession.shared
    
    // 네이버 API 인증 정보 (Info.plist → Secrets.xcconfig에서 주입)
    private let clientID: String = {
        guard let key = Bundle.main.infoDictionary?["NAVER_MAP_API_KEY_ID"] as? String,
              !key.isEmpty else {
            print("⚠️ 네이버 지도 API Key ID가 Info.plist에 설정되지 않았습니다.")
            return ""
        }
        return key
    }()
    private let clientSecret: String = {
        guard let key = Bundle.main.infoDictionary?["NAVER_MAP_API_KEY_SECRET"] as? String,
              !key.isEmpty else {
            print("⚠️ 네이버 지도 API Secret이 Info.plist에 설정되지 않았습니다.")
            return ""
        }
        return key
    }()
    
    // MARK: - Geocoding (주소 → 좌표)
    func geocode(address: String) async throws -> [NaverDetailAddress] {
        let urlString = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode?query=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "URL", code: 0)
        }
        
        var request = URLRequest(url: url)
        request.addValue(clientID, forHTTPHeaderField: "X-NCP-APIGW-API-KEY-ID")
        request.addValue(clientSecret, forHTTPHeaderField: "X-NCP-APIGW-API-KEY")

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Response", code: 0)
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(NaverGeocodingResponse.self, from: data),
               let error = errorResponse.error {
                throw NSError(domain: "API", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: error.message])
            }
            throw NSError(domain: "API", code: httpResponse.statusCode)
        }
        
        let geocodingResponse = try JSONDecoder().decode(NaverGeocodingResponse.self, from: data)
        guard let addresses = geocodingResponse.addresses else {
            throw NSError(domain: "Data", code: 0)
        }
        
        // NaverAddress를 NaverDetailAddress로 변환
        return addresses.map { $0.toDetailAddress() }
    }
    
    // MARK: - Reverse Geocoding (좌표 → 주소)
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> String {
        let urlString = "https://maps.apigw.ntruss.com/map-reversegeocode/v2/gc?coords=\(longitude),\(latitude)&orders=roadaddr,addr&output=json"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "URL", code: 0)
        }
        
        var request = URLRequest(url: url)
        request.addValue(clientID, forHTTPHeaderField: "X-NCP-APIGW-API-KEY-ID")
        request.addValue(clientSecret, forHTTPHeaderField: "X-NCP-APIGW-API-KEY")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Response", code: 0)
        }
        
        if httpResponse.statusCode != 200 {
            throw NSError(domain: "API", code: httpResponse.statusCode)
        }
        
        let reverseGeocodingResponse = try JSONDecoder().decode(NaverReverseGeocodingResponse.self, from: data)
        
        guard reverseGeocodingResponse.status.code == 0,
              let results = reverseGeocodingResponse.results else {
            throw NSError(domain: "Data", code: 0)
        }
        
        // 도로명 주소 우선
        if let roadAddr = results.first(where: { $0.name == "roadaddr" }) {
            var address = ""
            
            // 지역 정보
            let region = roadAddr.region
            address += "\(region.area1.name) \(region.area2.name) \(region.area3.name)"
            
            // 도로명 + 건물번호
            if let roadName = roadAddr.land.name {
                address += " \(roadName)"
                address += " \(roadAddr.land.number1)"
                if !roadAddr.land.number2.isEmpty {
                    address += "-\(roadAddr.land.number2)"
                }
            }
            
            // 건물명
            if roadAddr.land.addition0.type == "building" && !roadAddr.land.addition0.value.isEmpty {
                address += " (\(roadAddr.land.addition0.value))"
            }
            
            return address
        }
        
        // 지번 주소
        if let addr = results.first(where: { $0.name == "addr" }) {
            var address = ""
            let region = addr.region
            address += "\(region.area1.name) \(region.area2.name) \(region.area3.name)"
            
            if !addr.land.number1.isEmpty {
                address += " \(addr.land.number1)"
                if !addr.land.number2.isEmpty {
                    address += "-\(addr.land.number2)"
                }
            }
            
            return address
        }
        
        throw NSError(domain: "Data", code: 0)
    }
}
