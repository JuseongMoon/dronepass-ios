//
//  ShapeDetailView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif
import SafariServices

struct ShapeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var repository = ShapeRepository.shared
    @StateObject private var shapeObserver: ShapeRealtimeObserver
    @ObservedObject private var droneManager = DroneManager.shared

    private let originalShape: ShapeModel
    
    var onClose: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    
    @State private var showMapSheet = false
    @State private var showDeleteAlert = false
    @State private var showActionSheet = false
    @State private var showSafari = false
    @State private var safariURL: URL? = nil
    @State private var showEditSheet = false
    @State private var showDuplicateSheet = false
    @State private var isDeleting = false // 삭제 중 상태 추가
    @State private var showCopyToast = false // 복사 토스트 표시 상태
    @State private var copyMessage = "" // 복사 메시지
    
    init(shape: ShapeModel, onClose: (() -> Void)? = nil, onEdit: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        _shapeObserver = StateObject(wrappedValue: ShapeRealtimeObserver(shape: shape))
        self.originalShape = shape
        self.onClose = onClose
        self.onEdit = onEdit
        self.onDelete = onDelete
    }
    
    private var addressURL: URL? {
        guard let address = shapeObserver.shape.address else { return nil }
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    // 연결된 드론 정보
    private var connectedDrone: DroneModel? {
        if let droneId = shapeObserver.shape.droneId {
            let drone = droneManager.getDrone(by: droneId)

            // 드론이 삭제되었거나 찾을 수 없는 경우 명확히 로깅
            if drone == nil {
                print("⚠️ ShapeDetailView: 연결된 드론을 찾을 수 없음 (ID: \(droneId))")
                print("   - Shape: \(shapeObserver.shape.title)")
                print("   - 활성 드론 수: \(droneManager.activeDrones.count)")
            }

            return drone
        }

        // 레거시 호환성: droneId가 없는 기존 도형은 첫 번째 드론 사용
        let firstDrone = droneManager.activeDrones.first
        if firstDrone != nil {
            print("ℹ️ ShapeDetailView: 레거시 도형, 첫 번째 드론 사용 (\(firstDrone!.name))")
        }
        return firstDrone
    }
    
    // MARK: - 지도앱 연동 버튼
    private var mapButtons: [(title: String, action: () -> Void)] {
        let coordinate = shapeObserver.shape.baseCoordinate
        let name = shapeObserver.shape.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "목적지"

        // 한국 현지 기능 활성화 여부 확인
        let isKoreaFeaturesEnabled = SettingManager.shared.isKoreaFeaturesEnabled

        let googleMaps = (NSLocalizedString("shape.detail.map.google", comment: "Google Maps"), {
            let urlStr = "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving"
            self.openMapApp(urlScheme: urlStr, appStoreId: "585027354")
        })

        let naverMap = (NSLocalizedString("shape.detail.map.naver", comment: "Naver Map"), {
            let urlStr = "nmap://route/public?dlat=\(coordinate.latitude)&dlng=\(coordinate.longitude)&dname=\(name)"
            self.openMapApp(urlScheme: urlStr, appStoreId: "311867728")
        })

        let kakaoMap = (NSLocalizedString("shape.detail.map.kakao", comment: "Kakao Map"), {
            let urlStr = "kakaomap://route?ep=\(coordinate.latitude),\(coordinate.longitude)&by=CAR"
            self.openMapApp(urlScheme: urlStr, appStoreId: "304608425")
        })

        let tmap = (NSLocalizedString("shape.detail.map.tmap", comment: "TMAP"), {
            let urlStr = "tmap://route?goalname=\(name)&goalx=\(coordinate.longitude)&goaly=\(coordinate.latitude)"
            self.openMapApp(urlScheme: urlStr, appStoreId: "431589174")
        })

        // 한국 현지 기능 활성화: 네이버, 카카오, 티맵, 구글 순서
        // 비활성화: 구글맵만 표시
        if isKoreaFeaturesEnabled {
            return [naverMap, kakaoMap, tmap, googleMaps]
        } else {
            return [googleMaps]
        }
    }
    
    // MARK: - 지도앱 실행
    private func openMapApp(urlScheme: String, appStoreId: String) {
        guard let url = URL(string: urlScheme) else { return }

        openURL(url)
        // 앱이 설치되어 있지 않은 경우 앱스토어로 이동
        if let appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreId)") {
            openURL(appStoreURL)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    // 드론 정보 셀
                    HStack {
                        Text(NSLocalizedString("shape.detail.drone", comment: "Drone"))
                            .bold()
                        Spacer()
                        HStack(spacing: 8) {
                            if let drone = connectedDrone {
                                // 드론이 정상적으로 연결된 경우
                                if let color = drone.paletteColor {
                                    Circle()
                                        .fill(Color(color.uiColor))
                                        .frame(width: 12, height: 12)
                                }
                                Text(drone.name)
                                    .foregroundColor(.secondary)
                            } else if shapeObserver.shape.droneId != nil {
                                // droneId는 있지만 드론을 찾을 수 없음 (삭제된 드론)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text(NSLocalizedString("shape.detail.drone.deleted", comment: "Deleted drone"))
                                    .foregroundColor(.orange)
                                    .italic()
                            } else {
                                // 레거시 도형 (droneId 없음)
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12))
                                Text(NSLocalizedString("shape.detail.drone.unassigned", comment: "No drone assigned"))
                                    .foregroundColor(.gray)
                                    .italic()
                            }
                        }
                    }

                    HStack {
                        Text(NSLocalizedString("shape.detail.title", comment: "Title"))
                            .bold()
                        Spacer()
                        Text(shapeObserver.shape.title)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("shape.detail.coordinate", comment: "Coordinates"))
                            .bold()
                        Spacer()
                        Text(shapeObserver.shape.baseCoordinate.formattedCoordinate)
                            .foregroundColor(.secondary)
                    }
                    .copyableText(
                        shapeObserver.shape.baseCoordinate.decimalCoordinate,
                        showToast: $showCopyToast,
                        toastMessage: $copyMessage
                    )
                    
                    HStack {
                        Text(NSLocalizedString("shape.detail.address", comment: "Address"))
                            .bold()

                        Spacer()
                        Text(shapeObserver.shape.address ?? "-")
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundColor(.blue)
                            .onTapGesture {
                                showActionSheet = true
                            }
                    }
                    .copyableText(
                        shapeObserver.shape.address,
                        showToast: $showCopyToast,
                        toastMessage: $copyMessage
                    )
                    
                    if let radius = shapeObserver.shape.radius {
                        HStack {
                            Text(NSLocalizedString("shape.detail.radius", comment: "Radius"))
                                .bold()

                            Spacer()
                            Text("\(Int(radius)) m")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let height = shapeObserver.shape.height {
                        HStack {
                            Text(NSLocalizedString("shape.detail.altitude", comment: "Altitude"))
                                .bold()

                            Spacer()
                            Text("\(Int(height)) m")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text(NSLocalizedString("shape.detail.startDate", comment: "Start Date"))
                            .bold()

                        Spacer()
                        Text(DateFormatter.localizedDateTime.string(from: shapeObserver.shape.flightStartDate))
                            .foregroundColor(.secondary)
                    }

                    if let expire = shapeObserver.shape.flightEndDate {
                        HStack {
                            Text(NSLocalizedString("shape.detail.endDate", comment: "End Date"))
                                .bold()

                            Spacer()
                            Text(DateFormatter.localizedDateTime.string(from: expire))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(NSLocalizedString("shape.detail.memo", comment: "Memo")) {
                    VStack {
                        HyperlinkTextView(
                            text: shapeObserver.shape.memo ?? "-",
                            font: .systemFont(ofSize: 16),
                            textColor: UIColor.secondaryLabel,
                            showSafari: $showSafari,
                            safariURL: $safariURL
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 44)
            .environment(\.defaultMinListHeaderHeight, 8)
            .padding(.top, -20)
            .navigationTitle(NSLocalizedString("shape.detail.navigation.title", comment: "Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(NSLocalizedString("shape.detail.edit", comment: "Edit")) {
                            showEditSheet = true
                        }
                        Button(NSLocalizedString("shape.detail.duplicate", comment: "Duplicate")) {
                            showDuplicateSheet = true
                        }
                        Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                            showDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert(NSLocalizedString("shape.detail.deleteAlert.title", comment: "Delete Shape"), isPresented: $showDeleteAlert) {
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
                Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                    isDeleting = true
                    Task {
                        do {
                            try await repository.removeShape(id: shapeObserver.shape.id)
                            print("✅ 도형 삭제 완료: \(shapeObserver.shape.title)")
                            await MainActor.run {
                                onDelete?()
                                dismiss()
                                NotificationCenter.default.post(name: .shapesDidChange, object: nil)
                                isDeleting = false
                            }
                        } catch {
                            print("❌ 도형 삭제 실패: \(error.localizedDescription)")
                            await MainActor.run {
                                isDeleting = false
                            }
                        }
                    }
                }
            } message: {
                Text(String(format: NSLocalizedString("shape.detail.deleteAlert.message", comment: "Are you sure you want to delete '%@'?"), shapeObserver.shape.title))
            }
            .confirmationDialog(NSLocalizedString("shape.detail.navigation.title.dialog", comment: "Choose Navigation App"), isPresented: $showActionSheet, titleVisibility: .visible) {
                ForEach(mapButtons, id: \.title) { button in
                    Button(button.title) { button.action() }
                }
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("shape.detail.navigation.message", comment: "Start navigation with the app below."))
            }
            .sheet(isPresented: $showSafari) {
                if let url = safariURL {
                    SafariView(url: url)
                }
            }
            .sheet(isPresented: $showEditSheet) {
                ShapeEditView(
                    coordinate: shapeObserver.shape.baseCoordinate,
                    onAdd: { updatedShape in
                        shapeObserver.shape = updatedShape
                        showEditSheet = false
                    },
                    originalShape: shapeObserver.shape
                )
            }
            .sheet(isPresented: $showDuplicateSheet) {
                ShapeEditView(
                    coordinate: shapeObserver.shape.baseCoordinate,
                    onAdd: { newShape in
                        showDuplicateSheet = false
                        NotificationCenter.default.post(name: .shapesDidChange, object: nil)
                        dismiss() // 복제 후 원본 상세뷰 닫기
                    },
                    originalShape: shapeObserver.shape,
                    isDuplicateMode: true
                )
            }
        }
        .presentationDetents([.fraction(0.8)])
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.popover)
        .copyToast(showToast: $showCopyToast, message: copyMessage)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct HyperlinkTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    @Binding var showSafari: Bool
    @Binding var safariURL: URL?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.dataDetectorTypes = [.link, .phoneNumber]
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.isUserInteractionEnabled = true
        textView.showsVerticalScrollIndicator = true
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let attrStr = NSMutableAttributedString(string: text)
        attrStr.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.count))
        attrStr.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: text.count))
        uiView.attributedText = attrStr
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let parent: HyperlinkTextView
        
        init(parent: HyperlinkTextView) { self.parent = parent }
        
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
            if URL.scheme == "http" || URL.scheme == "https" {
                parent.safariURL = URL
                parent.showSafari = true
                return false
            }
            // 전화, 메일 등은 시스템이 처리
            return true
        }
    }
}

// MARK: - Preview
#Preview("기본") {
    let dummy = ShapeModel(
        id: UUID(),
        title: "드론 비행연습 및 테스트촬영",
        baseCoordinate: CoordinateManager(latitude: 37.5331, longitude: 126.6342),
        radius: 999,
        memo: """
군 담당자  [ ☎ 031-290-9221 ]

· 인근 촬영금지시설이 촬영될 가능성이 명백한 경우 (업무일 기준)촬영 2일 전까지 연락 후 안내받으시기 바랍니다.
· 현장통제 보안담당자 : 031-290-9041(연락 가능시간 : 평일 09:00 ~ 17:00 / 그 외 연락불가)
demo@example.com
https://www.naver.com
· 인근 촬영금지시설이 촬영될 가능성이 명백한 경우 (업무일 기준)촬영 2일 전까지 연락 후 안내받으시기 바랍니다.
· 현장통제 보안담당자 : 031-290-9041(연락 가능시간 : 평일 09:00 ~ 17:00 / 그 외 연락불가)
demo@example.com
https://www.naver.com
· 인근 촬영금지시설이 촬영될 가능성이 명백한 경우 (업무일 기준)촬영 2일 전까지 연락 후 안내받으시기 바랍니다.
· 현장통제 보안담당자 : 031-290-9041(연락 가능시간 : 평일 09:00 ~ 17:00 / 그 외 연락불가)
demo@example.com
https://www.naver.com
""",
        address: "인천광역시 서구 청라동 1-791",
        createdAt: Date(),
        deletedAt: nil,
        flightStartDate: Date(),
        flightEndDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
        color: PaletteColor.blue.hex
    )
    
    ShapeDetailView(
        shape: dummy,
        onDelete: {
            print("프리뷰: '\(dummy.title)' 도형이 삭제되었습니다.")
        }
    )
}

