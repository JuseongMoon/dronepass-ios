//
//  VWorldZoneDetailView.swift
//  DronePass
//
//  VWorld 비행 구역 상세 정보 표시
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

struct VWorldZoneDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let feature: DroneZoneFeature

    // MARK: - Computed Properties

    /// 레이어 타입별 예상 행 개수
    private var estimatedRowCount: Int {
        switch feature.layer {
        case .culturalHeritage:  // 문화재보호구역
            return 9  // 기본정보(4) + 문화재정보(4)
        case .temporaryProhibited:  // 임시비행금지구역
            return 8  // 기본정보(4) + NOTAM정보(4)
        case .consultationZone, .nationalPark:  // 사전협의구역, 국립자연공원
            return 7  // 기본정보(4) + 관리기관정보(3-4)
        case .prohibitedZone, .restrictedZone, .boundaryZone, .dangerZone:  // 비행금지구역, 비행제한구역, 경계구역, 위험지역
            return 5  // 기본정보(3-4) + 공공기관(1-2)
        case .controlZone, .ultraLightZone:  // 관제권, 초경량비행장치공역
            return 4  // 기본정보(3-4)
        case .lightAircraftZone, .obstacleZone, .trafficZone: // 경량항공기 이착륙장, 장애물공역, 비행장교통구역
            return 2  // 기본정보(3-4)
        }
    }

    /// 행 개수에 따른 동적 시트 높이 설정
    private var dynamicDetents: Set<PresentationDetent> {
        let rowCount = estimatedRowCount
        switch rowCount {
        case 0...2:
            return [.height(230), .large]  // 매우작게 (1-2행)
        case 3...4:
            return [.height(280), .large]  // 작게 (3-4행)
        case 5:
            return [.height(340), .large]  // 중간 (5-6행)
        case 6:
            return [.height(380), .large]  // 중간 (5-6행)
        case 7:
            return [.height(480), .large]  // 크게 (7-8행)
        case 8:
            return [.height(550), .large]  // 크게 (7-8행)
        case 9:
            return [.height(680), .large]  // 크게 (7-8행)
        default:
            return [.fraction(0.65), .large]  // 매우 크게 (9행 이상)
        }
    }

    var body: some View {
        let _ = print("🟢 [상세보기] View 렌더링 시작 - 레이어: \(feature.layer.displayName), 코드: \(feature.zoneCode ?? "없음")")

        NavigationView {
            List {
                // 기본 정보 섹션
                Section {
                    let _ = print("🟢 [상세보기] 기본 정보 섹션 렌더링")
                    // 구역 유형
                    HStack {
                        Text(NSLocalizedString("vworld.detail.zoneType", comment: "Zone Type"))
                            .bold()
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(feature.layer.overlayColor)
                                .frame(width: 12, height: 12)
                            Text(feature.layer.displayName)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 구역 코드/이름
                    if let code = feature.zoneCode {
                        HStack {
                            Text(NSLocalizedString("vworld.detail.zoneCode", comment: "Zone Code"))
                                .bold()
                            Spacer()
                            Text(code)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 좌표
                    HStack {
                        Text(NSLocalizedString("vworld.detail.coordinates", comment: "Coordinates"))
                            .bold()
                        Spacer()
                        Text(feature.geometry.centerCoordinate.formattedCoordinate)
                            .foregroundColor(.secondary)
                    }

                    // 고도 정보
                    if feature.altitudeInfo != nil {
                        HStack {
                            Text(NSLocalizedString("vworld.detail.altitudeLimit", comment: "Altitude Limit"))
                                .bold()
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let upper = feature.formattedUpperAltitude {
                                    Text("\(NSLocalizedString("vworld.detail.upper", comment: "Upper")): \(upper)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let lower = feature.formattedLowerAltitude {
                                    Text("\(NSLocalizedString("vworld.detail.lower", comment: "Lower")): \(lower)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // 임시비행금지구역 전용 섹션
                if feature.layer == .temporaryProhibited {
                    Section(NSLocalizedString("vworld.notam.title", comment: "NOTAM Information")) {
                        // 상태
                        HStack {
                            Text(NSLocalizedString("vworld.notam.status", comment: "Status"))
                                .bold()
                            Spacer()
                            HStack(spacing: 4) {
                                Text(feature.notamStatus.emoji)
                                Text(feature.notamStatus.displayName)
                                    .foregroundColor(statusColor(for: feature.notamStatus))
                            }
                        }

                        // 시작 일시
                        if let startDate = feature.notamStartDate {
                            HStack {
                                Text(NSLocalizedString("vworld.notam.start", comment: "Start"))
                                    .bold()
                                Spacer()
                                Text(formatNotamDate(startDate))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 종료 일시
                        if let endDate = feature.notamEndDate {
                            HStack {
                                Text(NSLocalizedString("vworld.notam.end", comment: "End"))
                                    .bold()
                                Spacer()
                                Text(formatNotamDate(endDate))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 남은 일수
                        if let days = feature.daysRemaining {
                            HStack {
                                Text(NSLocalizedString("vworld.notam.remaining", comment: "Remaining Period"))
                                    .bold()
                                Spacer()
                                Text("\(days)\(NSLocalizedString("vworld.notam.days", comment: "days"))")
                                    .foregroundColor(days <= 7 ? .orange : .secondary)
                            }
                        }
                    }
                }

                // 사전협의구역 전용 섹션
                if feature.layer == .consultationZone {
                    Section(NSLocalizedString("vworld.authority.title", comment: "Managing Authority")) {
                        // 기관명 (한글)
                        if let nameKor = feature.authorityNameKor {
                            HStack {
                                Text(NSLocalizedString("vworld.authority.name", comment: "Organization Name"))
                                    .bold()
                                Spacer()
                                Text(nameKor)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 기관명 (영문)
                        if let nameEng = feature.authorityNameEng {
                            HStack {
                                Text(NSLocalizedString("vworld.authority.nameEng", comment: "English Name"))
                                    .bold()
                                Spacer()
                                Text(nameEng)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 관리부서
                        if let dept = feature.operatingInstitution {
                            HStack {
                                Text(NSLocalizedString("vworld.authority.department", comment: "Department"))
                                    .bold()
                                Spacer()
                                Text(dept)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 연락처
                        if let phone = feature.phoneNumber {
                            HStack {
                                Text(NSLocalizedString("vworld.authority.contact", comment: "Contact"))
                                    .bold()
                                Spacer()
                                if let url = URL(string: "tel:\(phone.replacingOccurrences(of: "-", with: ""))") {
                                    Link(phone, destination: url)
                                        .foregroundColor(.blue)
                                } else {
                                    Text(phone)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                // 문화재보호구역 전용 섹션
                if feature.layer == .culturalHeritage {
                    Section(NSLocalizedString("vworld.heritage.title", comment: "Cultural Heritage Information")) {
                        // 문화재명
                        if let name = feature.zoneCode {
                            HStack {
                                Text(NSLocalizedString("vworld.heritage.name", comment: "Heritage Name"))
                                    .bold()
                                Spacer()
                                Text(name)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        // 행정구역
                        if let address = feature.fullAddress {
                            HStack {
                                Text(NSLocalizedString("vworld.heritage.address", comment: "Administrative District"))
                                    .bold()
                                Spacer()
                                Text(address)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 용도지역
                        if let zoneName = feature.zoneName {
                            HStack {
                                Text(NSLocalizedString("vworld.heritage.zone", comment: "Zoning"))
                                    .bold()
                                Spacer()
                                Text(zoneName)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 고시 정보
                        if let year = feature.designationYear, let num = feature.designationNumber {
                            HStack {
                                Text(NSLocalizedString("vworld.heritage.designation", comment: "Designation"))
                                    .bold()
                                Spacer()
                                Text("\(year)\(NSLocalizedString("vworld.heritage.yearPrefix", comment: "Year"))\(num)\(NSLocalizedString("vworld.heritage.numberSuffix", comment: "No."))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 공공기관 연락처 섹션 (사전협의구역 제외한 모든 레이어에 표시)
                if feature.layer != .consultationZone, let contact = feature.publicContact {
                    Section(NSLocalizedString("vworld.authority.title", comment: "Managing Authority")) {
                        // 기관명
                        HStack {
                            Text(NSLocalizedString("vworld.authority.name", comment: "Organization Name"))
                                .bold()
                            Spacer()
                            Text(contact.organizationName)
                                .foregroundColor(.secondary)
                        }

                        // 연락처
                        HStack {
                            Text(NSLocalizedString("vworld.authority.contact", comment: "Contact"))
                                .bold()
                            Spacer()
                            if let url = URL(string: "tel:\(contact.phoneNumber.replacingOccurrences(of: "-", with: ""))") {
                                Link(contact.phoneNumber, destination: url)
                                    .foregroundColor(.blue)
                            } else {
                                Text(contact.phoneNumber)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 44)
            .environment(\.defaultMinListHeaderHeight, 8)
            .navigationTitle(NSLocalizedString("vworld.detail.title", comment: "Zone Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .presentationDetents(dynamicDetents)
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Helper Functions

    private func statusColor(for status: NotamStatus) -> Color {
        switch status {
        case .active: return .red
        case .scheduled: return .blue
        case .expired: return .gray
        case .unknown: return .secondary
        }
    }

    private func formatNotamDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        formatter.timeZone = TimeZone.current // KST로 변환해서 표시
        return formatter.string(from: date)
    }
}

// MARK: - GeoJSONGeometry Extension (중심 좌표 계산)

extension GeoJSONGeometry {
    var centerCoordinate: CLLocationCoordinate2D {
        switch coordinates {
        case .point(let coord):
            return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])

        case .polygon(let rings):
            guard let firstRing = rings.first, !firstRing.isEmpty else {
                return CLLocationCoordinate2D(latitude: 0, longitude: 0)
            }
            let avgLat = firstRing.map { $0[1] }.reduce(0, +) / Double(firstRing.count)
            let avgLon = firstRing.map { $0[0] }.reduce(0, +) / Double(firstRing.count)
            return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)

        case .multiPolygon(let polygons):
            guard let firstPolygon = polygons.first,
                  let firstRing = firstPolygon.first,
                  !firstRing.isEmpty else {
                return CLLocationCoordinate2D(latitude: 0, longitude: 0)
            }
            let avgLat = firstRing.map { $0[1] }.reduce(0, +) / Double(firstRing.count)
            let avgLon = firstRing.map { $0[0] }.reduce(0, +) / Double(firstRing.count)
            return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)

        case .lineString(let coords):
            guard !coords.isEmpty else {
                return CLLocationCoordinate2D(latitude: 0, longitude: 0)
            }
            let avgLat = coords.map { $0[1] }.reduce(0, +) / Double(coords.count)
            let avgLon = coords.map { $0[0] }.reduce(0, +) / Double(coords.count)
            return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)

        case .unknown:
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }
}

// MARK: - CLLocationCoordinate2D Extension (좌표 포맷)

extension CLLocationCoordinate2D {
    var formattedCoordinate: String {
        let latDirection = latitude >= 0 ? "N" : "S"
        let lonDirection = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@",
                     abs(latitude), latDirection,
                     abs(longitude), lonDirection)
    }
}

// MARK: - Preview

#Preview("비행금지구역") {
    let dummyFeature = DroneZoneFeature(
        from: GeoJSONFeature(
            type: "Feature",
            id: "test.1",
            geometry: GeoJSONGeometry(
                type: "Polygon",
                coordinates: .polygon([[[126.5, 37.5], [126.6, 37.5], [126.6, 37.6], [126.5, 37.6], [126.5, 37.5]]])
            ),
            properties: [
                "prh_lbl_1": AnyCodable("RK P73A"),
                "prh_lbl_2": AnyCodable("UNL"),
                "prh_lbl_3": AnyCodable("GND"),
                "prh_lbl_4": AnyCodable("비행금지구역")
            ]
        ),
        layer: .prohibitedZone
    )

    VWorldZoneDetailView(feature: dummyFeature)
}

#Preview("임시비행금지구역 (NOTAM)") {
    let dummyFeature = DroneZoneFeature(
        from: GeoJSONFeature(
            type: "Feature",
            id: "test.2",
            geometry: GeoJSONGeometry(
                type: "Polygon",
                coordinates: .polygon([[[126.5, 37.5], [126.6, 37.5], [126.6, 37.6], [126.5, 37.6], [126.5, 37.5]]])
            ),
            properties: [
                "prh_lbl_1": AnyCodable("D0145/25"),
                "prh_lbl_2": AnyCodable("500 AGL"),
                "prh_lbl_3": AnyCodable("SFC"),
                "notam": AnyCodable("A)RKRR B)2501311500 C)2504301459")
            ]
        ),
        layer: .temporaryProhibited
    )

    VWorldZoneDetailView(feature: dummyFeature)
}
