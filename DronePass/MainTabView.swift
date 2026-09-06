//
//  MainTabView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//

import SwiftUI

// MARK: - 메인 탭 뷰
/// 지도, 저장 목록, 설정 탭을 관리하는 최상위 뷰
struct MainTabView: View {
    // MARK: - State 변수들

    /// 현재 선택된 탭 (.map, .saved, .settings)
    @State private var selectedTab: Tab = .map

    /// 스케치 모드 상태 관찰
    @ObservedObject var sketchManager = SketchManager.shared

    /// 저장 목록에서 선택된 도형의 ID (지도에서 하이라이트 표시용)
    @State private var selectedShapeID: UUID? = nil

    /// 저장 목록 오버레이 표시 여부
    @State private var isSavedSheetPresented = false

    /// 설정 오버레이 표시 여부
    @State private var isSettingsSheetPresented = false

    /// 저장 목록에서 스크롤할 도형의 ID
    @State private var shapeIDToScrollTo: UUID? = nil

    /// 푸시 알림 매니저 (팝업 표시용)
    @State private var pushNotificationManager = PushNotificationManager.shared

    /// 인증 매니저 (계정 전환 확인 alert 관찰용)
    @State private var authManager = AuthManager.shared

    // MARK: - Notification 이름 상수들
    private static let openSavedTabNotification = Notification.Name("OpenSavedTabNotification")
    private static let openSavedTabFromSettingsNotification = Notification.Name("OpenSavedTabFromSettings")
    private static let openSettingsFromSavedNotification = Notification.Name("OpenSettingsFromSaved")

    var body: some View {
        ZStack(alignment: .bottom) {
            // 메인 콘텐츠
            Group {
                switch selectedTab {
                case .map:
                    MainView()
                case .saved:
                    SavedTabPlaceholderView()
                case .settings:
                    // 설정 탭은 오버레이로 표시하므로 placeholder만 표시
                    SettingsTabPlaceholderView()
                }
            }
            
            // MARK: - 커스텀 탭바 (스케치 모드일 때 숨김)
            if !sketchManager.isSketchModeActive {
                VStack {
                    Spacer()

                    if UIDevice.current.userInterfaceIdiom == .pad {
                    // ===== 아이패드 탭바 =====
                    HStack(spacing: 0) {  // spacing: 탭 버튼 사이 간격 (0 = 붙어있음)
                        ForEach(Tab.allCases, id: \.self) { tab in
                            CustomTabButton(
                                tab: tab,
                                isSelected: getSelectedTabState(for: tab),
                                action: {
                                    handleTabSelection(tab)
                                }
                            )
                            .frame(width: 60)  // 🔧 각 탭 버튼 너비 (기본: 60)
                        }
                    }
                    // 🔧 전체 탭바 크기
                    .frame(width: 210, height: 60)  // 너비: 210 (60 x 3버튼 + 여백), 높이: 60

                    .background(.ultraThinMaterial)  // 블러 효과 배경
                    .clipShape(RoundedRectangle(cornerRadius: 30))  // 🔧 모서리 둥글기 (기본: 30)
                    .shadow(radius: 10, x: 0, y: 5)  // 그림자: 반경 10, 아래쪽(y:5)으로 드리움
                    .padding(.bottom, 20)  // 🔧 화면 하단에서 떨어진 거리 (기본: 20)

                } else {
                    // ===== 아이폰 탭바 =====
                    HStack(spacing: 0) {  // spacing: 탭 버튼 사이 간격 (0 = 붙어있음)
                        ForEach(Tab.allCases, id: \.self) { tab in
                            CustomTabButton(
                                tab: tab,
                                isSelected: getSelectedTabState(for: tab),
                                action: {
                                    handleTabSelection(tab)
                                }
                            )
                            .frame(width: 60)  // 🔧 각 탭 버튼 너비 (기본: 60)
                        }
                    }
                    // 🔧 전체 탭바 크기
                    .frame(width: 210, height: 60)  // 너비: 210, 높이: 60

                    .background(.ultraThinMaterial)  // 블러 효과 배경
                    .clipShape(RoundedRectangle(cornerRadius: 30))  // 🔧 모서리 둥글기 (기본: 30)
                    .shadow(radius: 10, x: 0, y: 5)  // 그림자: 반경 10, 아래쪽(y:5)으로 드리움
                    .padding(.bottom, 15)  // 🔧 화면 하단에서 떨어진 거리 (기본: 15)
                }
            }
            }

            // MARK: - 스케치 툴바 (스케치 모드일 때 표시, 탭바와 동일한 위치)
            if sketchManager.isSketchModeActive {
                VStack {
                    Spacer()
                    SketchToolbarView(onComplete: {
                        // 스케치 모드 종료 (MainView에서 onChange로 감지하여 로컬 상태 정리)
                        sketchManager.exitSketchMode()
                    })
                    .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 20 : 15)
                }
            }
        }
        .overlay(savedListOverlay)
        .overlay(settingsOverlay)
        .overlay(pushNotificationOverlay)
        .onAppear {
            setupNotifications()
            // 앱 시작 시 KP 데이터 가져오기
            Task {
                await KPIndexManager.shared.fetchKPData(forceRefresh: true)
                // VWorld 공공기관 연락처 데이터 가져오기
                await VWorldContactManager.shared.fetchContacts()
            }
        }
        .onDisappear {
            removeNotifications()
        }
        .onChange(of: isSavedSheetPresented) { _, isPresented in
            if !isPresented {
                // 하이라이트 해제 알림
                NotificationCenter.default.post(
                    name: Notification.Name("ClearMapHighlightNotification"),
                    object: nil
                )
                // 목록 선택 상태도 해제
                selectedShapeID = nil
            }
        }
        .onChange(of: sketchManager.isSketchModeActive) { _, isActive in
            if isActive {
                // 스케치 모드 진입 시 저장/설정 탭 닫기
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    isSavedSheetPresented = false
                    isSettingsSheetPresented = false
                }
            }
        }
        // 계정 전환 시 미동기화 로컬 데이터 손실 경고 (AuthManager가 요청, 앱 루트에서 표시)
        .alert(
            NSLocalizedString("account.switch.warning.title", comment: "Account switch data loss warning title"),
            isPresented: Binding(
                get: { authManager.pendingAccountSwitchAtRisk != nil },
                set: { if !$0 { authManager.resolveAccountSwitch(false) } }
            ),
            presenting: authManager.pendingAccountSwitchAtRisk
        ) { atRisk in
            Button(NSLocalizedString("account.switch.warning.continue", comment: "Continue and discard local data"), role: .destructive) {
                authManager.resolveAccountSwitch(true)
            }
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {
                authManager.resolveAccountSwitch(false)
            }
        } message: { atRisk in
            Text(String(format: NSLocalizedString("account.switch.warning.message", comment: "Account switch data loss message"), atRisk))
        }
    }
    
    // 탭 선택 상태 계산 함수
    private func getSelectedTabState(for tab: Tab) -> Bool {
        switch tab {
        case .map:
            return selectedTab == .map && !isSavedSheetPresented && !isSettingsSheetPresented
        case .saved:
            return isSavedSheetPresented
        case .settings:
            return isSettingsSheetPresented
        }
    }
    
    // 탭 선택 처리 함수
    private func handleTabSelection(_ tab: Tab) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            switch tab {
            case .map:
                // 지도 탭: 저장뷰와 설정창 모두 닫기
                isSavedSheetPresented = false
                isSettingsSheetPresented = false
                selectedTab = .map
            case .saved:
                // 저장 탭: 이미 열려있으면 닫고 지도로 돌아가기
                if isSavedSheetPresented {
                    isSavedSheetPresented = false
                    selectedTab = .map
                } else {
                    // 설정창이 열려있으면 닫고 저장뷰 열기
                    isSettingsSheetPresented = false
                    isSavedSheetPresented = true
                }
            case .settings:
                // 설정 탭: 이미 열려있으면 닫고 지도로 돌아가기
                if isSettingsSheetPresented {
                    isSettingsSheetPresented = false
                    selectedTab = .map
                } else {
                    // 저장뷰가 열려있으면 닫고 설정창 열기
                    isSavedSheetPresented = false
                    isSettingsSheetPresented = true
                }
            }
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: Self.openSavedTabNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let shapeID = notification.object as? UUID {
                // 1. 하이라이트를 위해 selectedShapeID는 즉시 업데이트합니다.
                self.selectedShapeID = shapeID

                // 2. 도형이 실제로 존재하는지 확인
                let allShapes = ShapeFileStore.shared.shapes
                let shapeExists = allShapes.contains { $0.id == shapeID }

                if shapeExists {
                    // 3. 시트가 닫혀있었다면, 애니메이션 시간을 고려하여 스크롤을 지연 실행합니다.
                    let wasSheetClosed = !self.isSavedSheetPresented

                    // 설정창이 열려있으면 닫고, 저장 탭 열기 (애니메이션 적용)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if self.isSettingsSheetPresented {
                            self.isSettingsSheetPresented = false
                        }
                        if wasSheetClosed {
                            self.isSavedSheetPresented = true
                        }
                    }

                    if wasSheetClosed {
                        // 애니메이션 시간(response: 0.4)보다 약간 긴 딜레이를 줍니다.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.shapeIDToScrollTo = shapeID
                        }
                    } else {
                        // 시트가 이미 열려있었다면, 바로 스크롤을 실행합니다.
                        self.shapeIDToScrollTo = shapeID
                    }
                    print("🔄 MainTabView: 도형 스크롤 준비 - \(shapeID)")
                } else {
                    print("⚠️ MainTabView: 도형이 존재하지 않음 - \(shapeID)")
                }
            }
        }
        
        // 설정창에서 저장 탭 열기 알림 처리
        NotificationCenter.default.addObserver(
            forName: Self.openSavedTabFromSettingsNotification,
            object: nil,
            queue: .main
        ) { _ in
            // 설정창을 닫고 저장뷰 열기 (애니메이션 적용)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isSettingsSheetPresented = false
                isSavedSheetPresented = true
            }
        }
        
        // 저장뷰에서 설정 탭 열기 알림 처리
        NotificationCenter.default.addObserver(
            forName: Self.openSettingsFromSavedNotification,
            object: nil,
            queue: .main
        ) { _ in
            // 저장뷰를 닫고 설정창 열기 (애니메이션 적용)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isSavedSheetPresented = false
                isSettingsSheetPresented = true
            }
        }
    }
    
    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func getOverlayEdge() -> Edge {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // 아이패드에서는 기본적으로 좌측에 표시
            return .leading
        } else {
            return .bottom
        }
    }

    // MARK: - Overlay Views (컴파일러 타입 체크 최적화를 위해 분리)

    @ViewBuilder
    private var savedListOverlay: some View {
        if isSavedSheetPresented {
            SavedListOverlayView(
                selectedShapeID: $selectedShapeID,
                isPresented: $isSavedSheetPresented,
                shapeIDToScrollTo: $shapeIDToScrollTo
            )
            .transition(.move(edge: getOverlayEdge()).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var settingsOverlay: some View {
        if isSettingsSheetPresented {
            SettingsOverlayView(
                isPresented: $isSettingsSheetPresented
            )
            .transition(.move(edge: getOverlayEdge()).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var pushNotificationOverlay: some View {
        Group {
            if let notification = pushNotificationManager.receivedPushNotification {
                PushNotificationPopupView(
                    notification: notification,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            pushNotificationManager.receivedPushNotification = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pushNotificationManager.receivedPushNotification != nil)
    }
}

// MARK: - Supporting Types
extension MainTabView {
    enum Tab: CaseIterable {
        case map, saved, settings
        
        var title: String {
            switch self {
            case .map: return NSLocalizedString("main.tab.map", comment: "Map tab")
            case .saved: return NSLocalizedString("main.tab.saved", comment: "Saved tab")
            case .settings: return NSLocalizedString("main.tab.settings", comment: "Settings tab")
            }
        }
        
        var icon: String {
            switch self {
            case .map: return "map"
            case .saved: return "tray.full"
            case .settings: return "gearshape"
            }
        }
        
        var selectedIcon: String {
            switch self {
            case .map: return "map.fill"
            case .saved: return "tray.full.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
}

// MARK: - Custom Tab Button
struct CustomTabButton: View {
    let tab: MainTabView.Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(height: 24)  // 🔧 아이콘 높이 고정 (모든 탭 동일)

                Text(tab.title)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(height: 16)  // 🔧 텍스트 높이 고정 (모든 탭 동일)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Saved Tab Placeholder View
struct SavedTabPlaceholderView: View {
    var body: some View {
        // 투명한 뷰이지만 실제 뷰로 존재
        Color.clear
            .contentShape(Rectangle()) // 터치 영역 확보
    }
}

// MARK: - Settings Tab Placeholder View
struct SettingsTabPlaceholderView: View {
    var body: some View {
        // 투명한 뷰이지만 실제 뷰로 존재
        Color.clear
            .contentShape(Rectangle()) // 터치 영역 확보
    }
}

// MARK: - Saved List Overlay View (저장 목록 오버레이)
/// 아이패드: 화면 좌측에 표시
/// 아이폰: 화면 하단에서 올라옴
struct SavedListOverlayView: View {
    @Binding var selectedShapeID: UUID?
    @Binding var isPresented: Bool
    @Binding var shapeIDToScrollTo: UUID?
    @StateObject private var placeShapeStore = ShapeFileStore.shared

    /// 드래그 시 이동 거리 (픽셀 단위)
    @State private var dragOffset: CGFloat = 0

    /// 현재 드래그 중인지 여부
    @State private var isDragging = false
    @StateObject private var sortingManager = ShapeSortingManager.shared

    /// 🔧 오버레이를 닫기 위한 최소 드래그 거리 (기본: 100px)
    /// - 아이패드: 오른쪽으로 100px 이상 드래그하면 닫힘
    /// - 아이폰: 아래로 100px 이상 드래그하면 닫힘
    private let dismissThreshold: CGFloat = 100

    var body: some View {
        GeometryReader { geometry in
            if UIDevice.current.userInterfaceIdiom == .pad {
                // ===== 아이패드 레이아웃: 화면 좌측에서 나타남 =====
                HStack {
                    VStack(spacing: 0) {
                        // 드래그 핸들과 헤더를 포함하는 상단 영역
                        VStack(spacing: 0) {
                            // 🔧 드래그 핸들 (상단 중앙의 가로 막대)
                            RoundedRectangle(cornerRadius: 2.5)  // 🔧 모서리 둥글기 (기본: 2.5)
                                .fill(Color(UIColor.systemGray3))  // 색상 (systemGray3 = 중간 회색)
                                .frame(width: 40, height: 5)  // 🔧 크기: 너비 40, 높이 5
                                .padding(.top, 12)  // 🔧 상단 여백 (기본: 12)
                                .padding(.bottom, 8)  // 🔧 하단 여백 (기본: 8)

                            // 🔧 헤더 영역 (제목 + 정렬 버튼)
                            HStack {
                                Text(NSLocalizedString("main.savedList.title", comment: "Saved list title"))
                                    .font(.headline)  // 폰트: headline (시스템 기본 중간 크기)
                                    .fontWeight(.semibold)  // 두께: semibold (중간 굵기)

                                Spacer()

                                // 정렬 버튼들 컨테이너
                                HStack(spacing: 8) {  // 🔧 버튼 사이 간격 (기본: 8)
//                                    if !placeShapeStore.shapes.isEmpty {
//                                        Text("\(placeShapeStore.shapes.count)개")
//                                            .font(.caption2)
//                                            .foregroundColor(.secondary)
//                                    }
                                    
                                    // 🔧 정렬 옵션 버튼 (제목/색상/생성일/시작일/종료일)
                                    Button(action: {
                                        sortingManager.cycleSortOption()
                                    }) {
                                        HStack(spacing: 4) {  // 🔧 아이콘-텍스트 간격 (기본: 4)
                                            Image(systemName: "arrow.up.arrow.down")
                                                .font(.caption2)  // 아이콘 크기 (caption2 = 작은 크기)
                                            Text(sortingManager.selectedSortOption.localizedName)
                                                .font(.caption2)  // 텍스트 크기
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.blue)  // 🔧 버튼 색상 (기본: 파란색)
                                        .padding(.horizontal, 8)  // 🔧 좌우 내부 여백 (기본: 8)
                                        .padding(.vertical, 4)  // 🔧 상하 내부 여백 (기본: 4)
                                        .background(Color.blue.opacity(0.1))  // 🔧 배경 투명도 (기본: 0.1)
                                        .cornerRadius(8)  // 🔧 모서리 둥글기 (기본: 8)
                                    }

                                    // 🔧 정렬 방향 버튼 (오름차순/내림차순)
                                    Button(action: {
                                        sortingManager.toggleSortDirection()
                                    }) {
                                        HStack(spacing: 4) {  // 🔧 아이콘-텍스트 간격 (기본: 4)
                                            Image(systemName: sortingManager.sortDirection.icon)
                                                .font(.caption2)  // 아이콘 크기
                                            Text(sortingManager.sortDirection.localizedName)
                                                .font(.caption2)  // 텍스트 크기
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.orange)  // 🔧 버튼 색상 (기본: 주황색)
                                        .padding(.horizontal, 8)  // 🔧 좌우 내부 여백 (기본: 8)
                                        .padding(.vertical, 4)  // 🔧 상하 내부 여백 (기본: 4)
                                        .background(Color.orange.opacity(0.1))  // 🔧 배경 투명도 (기본: 0.1)
                                        .cornerRadius(8)  // 🔧 모서리 둥글기 (기본: 8)
                                    }
                                }
                            }
                            .padding(.horizontal)  // 🔧 헤더 좌우 여백 (기본: 시스템 표준)
                            .padding(.bottom, 4)  // 🔧 헤더 하단 여백 (기본: 4)
                        }
                        .background(Color(UIColor.systemBackground))  // 헤더 배경: 시스템 기본 배경색
                        .zIndex(1)  // 헤더가 목록 위에 표시되도록 z-index 설정

                        // 저장된 항목 목록 (스크롤 가능)
                        SavedTableListView(
                            selectedShapeID: $selectedShapeID,
                            shapeIDToScrollTo: $shapeIDToScrollTo
                        )
                            .padding(.top, 8)  // 🔧 헤더와 목록 사이 간격 (기본: 8)
                            .zIndex(0)  // 목록은 헤더 아래에 표시
                    }
                    // 🔧 오버레이 전체 크기 설정
                    .frame(width: min(geometry.size.width * 0.4, 400))  // 너비: 화면의 40% 또는 최대 400px
                    .frame(maxHeight: geometry.size.height * 0.8)  // 🔧 최대 높이: 화면의 80%
                    .background(.ultraThinMaterial)  // 블러 효과 배경 (시스템 머티리얼)
                    .clipShape(RoundedRectangle(cornerRadius: 16))  // 🔧 모서리 둥글기 (기본: 16)
                    .shadow(radius: 10)  // 🔧 그림자 반경 (기본: 10)
                    .offset(x: dragOffset)  // 드래그 시 오른쪽으로 이동
                    // 🔧 애니메이션: 드래그 중이 아닐 때만 스프링 애니메이션 적용
                    .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    // response: 애니메이션 지속 시간 (0.3초)
                    // dampingFraction: 탄성 정도 (0.8 = 약간 튕김)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                }
                                // 오른쪽으로만 드래그 가능 (음수 방지)
                                dragOffset = max(0, gesture.translation.width)
                            }
                            .onEnded { gesture in
                                isDragging = false
                                // dismissThreshold(100px) 이상 드래그하면 오버레이 닫기
                                if gesture.translation.width > dismissThreshold {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isPresented = false
                                    }
                                    dragOffset = 0
                                } else {
                                    // 임계값 미만이면 원위치
                                    dragOffset = 0
                                }
                            }
                    )
                    // 🔧 오버레이 위치 조정 (화면 가장자리로부터의 거리)
                    .padding(.leading, 20)  // 좌측 여백 (기본: 20)
                    .padding(.top, 40)  // 상단 여백 (기본: 40)
                    .padding(.bottom, 0)  // 하단 여백 (기본: 0)
                    
                    Spacer()
                }
            } else {
                // ===== 아이폰 레이아웃: 화면 하단에서 올라옴 =====
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 0) {
                        // 드래그 핸들과 헤더를 포함하는 상단 영역
                        VStack(spacing: 0) {
                            // 🔧 드래그 핸들 (상단 중앙의 가로 막대)
                            RoundedRectangle(cornerRadius: 2.5)  // 🔧 모서리 둥글기 (기본: 2.5)
                                .fill(Color(UIColor.systemGray3))  // 색상 (systemGray3 = 중간 회색)
                                .frame(width: 40, height: 5)  // 🔧 크기: 너비 40, 높이 5
                                .padding(.top, 12)  // 🔧 상단 여백 (기본: 12)
                                .padding(.bottom, 8)  // 🔧 하단 여백 (기본: 8)

                            // 🔧 헤더 영역 (제목 + 정렬 버튼)
                            HStack {
                                Text(NSLocalizedString("main.savedList.title", comment: "Saved list title"))
                                    .font(.headline)  // 폰트: headline
                                    .fontWeight(.semibold)  // 두께: semibold

                                Spacer()

                                // 정렬 버튼들 컨테이너
                                HStack(spacing: 8) {  // 🔧 버튼 사이 간격 (기본: 8)
//                                    if !placeShapeStore.shapes.isEmpty {
//                                        Text("\(placeShapeStore.shapes.count)개")
//                                            .font(.caption)
//                                            .foregroundColor(.secondary)
//                                    }
                                    
                                    // 🔧 정렬 옵션 버튼 (제목/색상/생성일/시작일/종료일)
                                    Button(action: {
                                        sortingManager.cycleSortOption()
                                    }) {
                                        HStack(spacing: 4) {  // 🔧 아이콘-텍스트 간격 (기본: 4)
                                            Image(systemName: "arrow.up.arrow.down")
                                                .font(.caption)  // 아이콘 크기 (caption = 중간 작은 크기)
                                            Text(sortingManager.selectedSortOption.localizedName)
                                                .font(.caption)  // 텍스트 크기
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.blue)  // 🔧 버튼 색상 (기본: 파란색)
                                        .padding(.horizontal, 8)  // 🔧 좌우 내부 여백 (기본: 8)
                                        .padding(.vertical, 4)  // 🔧 상하 내부 여백 (기본: 4)
                                        .background(Color.blue.opacity(0.1))  // 🔧 배경 투명도 (기본: 0.1)
                                        .cornerRadius(8)  // 🔧 모서리 둥글기 (기본: 8)
                                    }

                                    // 🔧 정렬 방향 버튼 (오름차순/내림차순)
                                    Button(action: {
                                        sortingManager.toggleSortDirection()
                                    }) {
                                        HStack(spacing: 4) {  // 🔧 아이콘-텍스트 간격 (기본: 4)
                                            Image(systemName: sortingManager.sortDirection.icon)
                                                .font(.caption)  // 아이콘 크기
                                            Text(sortingManager.sortDirection.localizedName)
                                                .font(.caption)  // 텍스트 크기
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.orange)  // 🔧 버튼 색상 (기본: 주황색)
                                        .padding(.horizontal, 8)  // 🔧 좌우 내부 여백 (기본: 8)
                                        .padding(.vertical, 4)  // 🔧 상하 내부 여백 (기본: 4)
                                        .background(Color.orange.opacity(0.1))  // 🔧 배경 투명도 (기본: 0.1)
                                        .cornerRadius(8)  // 🔧 모서리 둥글기 (기본: 8)
                                    }
                                }
                            }
                            .padding(.horizontal)  // 🔧 헤더 좌우 여백 (기본: 시스템 표준)
                            .padding(.bottom, 16)  // 🔧 헤더 하단 여백 (기본: 16)
                        }
                        .background(Color(UIColor.systemBackground))  // 헤더 배경: 시스템 기본 배경색
                        .zIndex(1)  // 헤더가 목록 위에 표시되도록 z-index 설정

                        // 저장된 항목 목록 (스크롤 가능)
                        SavedTableListView(
                            selectedShapeID: $selectedShapeID,
                            shapeIDToScrollTo: $shapeIDToScrollTo
                        )
                            .padding(.top, 8)  // 🔧 헤더와 목록 사이 간격 (기본: 8)
                            .zIndex(0)  // 목록은 헤더 아래에 표시
                    }
                    // 🔧 오버레이 전체 크기 설정
                    .frame(maxWidth: .infinity)  // 너비: 화면 전체
                    .frame(height: min(geometry.size.height * 0.5, 500))  // 🔧 높이: 화면의 50% 또는 최대 500px
                    .background(.ultraThinMaterial)  // 블러 효과 배경 (시스템 머티리얼)
                    .clipShape(RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .phone ? 40 : 16))
                    // 🔧 모서리 둥글기: 아이폰 40, 아이패드 세로 모드 16
                    .shadow(radius: 10)  // 🔧 그림자 반경 (기본: 10)
                    .offset(y: dragOffset)  // 드래그 시 아래로 이동
                    // 🔧 애니메이션: 드래그 중이 아닐 때만 스프링 애니메이션 적용
                    .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    // response: 애니메이션 지속 시간 (0.3초)
                    // dampingFraction: 탄성 정도 (0.8 = 약간 튕김)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                }
                                // 아래로만 드래그 가능 (음수 방지)
                                dragOffset = max(0, gesture.translation.height)
                            }
                            .onEnded { gesture in
                                isDragging = false
                                // dismissThreshold(100px) 이상 드래그하면 오버레이 닫기
                                if gesture.translation.height > dismissThreshold {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isPresented = false
                                    }
                                    dragOffset = 0
                                } else {
                                    // 임계값 미만이면 원위치
                                    dragOffset = 0
                                }
                            }
                    )
                    // 🔧 오버레이 위치 조정 (화면 가장자리로부터의 거리)
                    .padding(.horizontal, 16)  // 좌우 여백 (기본: 16)
                    .padding(.bottom, 16)  // 하단 여백 (기본: 16)
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: isPresented) { oldValue, newValue in
            if newValue {
                dragOffset = 0  // 열릴 때 항상 초기화
            }
        }
    }
}



// MARK: - Settings Overlay View (설정 오버레이)
/// 아이패드: 화면 좌측에 표시
/// 아이폰: 화면 하단에서 올라옴, 위로 드래그하여 확장 가능
struct SettingsOverlayView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = SettingViewModel()

    /// 드래그 시 이동 거리 (픽셀 단위)
    @State private var dragOffset: CGFloat = 0

    /// 현재 드래그 중인지 여부
    @State private var isDragging = false

    /// 색상 선택기 표시 여부
    @State private var showColorPicker = false

    /// 🔧 아이폰 설정창 높이 비율 (0.5 = 50%, 0.9 = 90%)
    /// - 기본: 0.5 (화면의 50%)
    /// - 확장: 0.9 (화면의 90%)
    @State private var sheetHeight: CGFloat = 0.5

    /// 🔧 오버레이를 닫기 위한 최소 드래그 거리 (기본: 100px)
    /// - 아이패드: 오른쪽으로 100px 이상 드래그하면 닫힘
    /// - 아이폰: 아래로 100px 이상 드래그하면 닫힘
    private let dismissThreshold: CGFloat = 100

    /// 🔧 위로 드래그 시 확장되는 임계값 (기본: -50px)
    /// - 아이폰 전용: 위로 50px 이상 드래그하면 90%로 확장
    private let expandThreshold: CGFloat = -50

    var body: some View {
        GeometryReader { geometry in
            if UIDevice.current.userInterfaceIdiom == .pad {
                // ===== 아이패드 레이아웃: 화면 좌측에서 나타남 =====
                HStack {
                    VStack(spacing: 0) {
                        // 드래그 핸들과 헤더를 포함하는 상단 영역
                        VStack(spacing: 0) {
                            // 🔧 드래그 핸들 (상단 중앙의 가로 막대)
                            RoundedRectangle(cornerRadius: 2.5)  // 🔧 모서리 둥글기 (기본: 2.5)
                                .fill(Color(UIColor.systemGray3))  // 색상 (systemGray3 = 중간 회색)
                                .frame(width: 40, height: 5)  // 🔧 크기: 너비 40, 높이 5
                                .padding(.top, 12)  // 🔧 상단 여백 (기본: 12)
                                .padding(.bottom, 8)  // 🔧 하단 여백 (기본: 8)

                            // 🔧 헤더 영역 (제목만 표시)
                            HStack {
                                Text(NSLocalizedString("main.settings.title", comment: "Settings title"))
                                    .font(.title)  // 폰트: title (큰 크기)
                                    .fontWeight(.bold)  // 두께: bold (굵게)

                                Spacer()
                            }
                            .padding(.horizontal)  // 🔧 헤더 좌우 여백 (기본: 시스템 표준)
                            .padding(.bottom, 4)  // 🔧 헤더 하단 여백 (기본: 4)
                        }
                        .background(Color(UIColor.systemBackground))  // 헤더 배경: 시스템 기본 배경색
                        .zIndex(1)  // 헤더가 설정 내용 위에 표시되도록 z-index 설정

                        // 설정 내용 (스크롤 가능한 설정 옵션들)
                        NavigationView {
                            SettingView(
                                viewModel: viewModel,
                                showColorPicker: $showColorPicker
                            )
                            .zIndex(0)  // 설정 내용은 헤더 아래에 표시
                        }
                        .navigationViewStyle(StackNavigationViewStyle())  // 스택 네비게이션 스타일 적용
                        .ignoresSafeArea(.all, edges: .top)  // 상단 세이프 에어리어 무시
                    }
                    // 🔧 오버레이 전체 크기 설정
                    .frame(width: min(geometry.size.width * 0.4, 400))  // 너비: 화면의 40% 또는 최대 400px
                    .frame(maxHeight: geometry.size.height * 0.8)  // 🔧 최대 높이: 화면의 80%
                    .background(.ultraThinMaterial)  // 블러 효과 배경 (시스템 머티리얼)
                    .clipShape(RoundedRectangle(cornerRadius: 16))  // 🔧 모서리 둥글기 (기본: 16)
                    .shadow(radius: 10)  // 🔧 그림자 반경 (기본: 10)
                    .offset(x: dragOffset)  // 드래그 시 오른쪽으로 이동
                    // 🔧 애니메이션: 드래그 중이 아닐 때만 스프링 애니메이션 적용
                    .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    // response: 애니메이션 지속 시간 (0.3초)
                    // dampingFraction: 탄성 정도 (0.8 = 약간 튕김)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                }
                                // 오른쪽으로만 드래그 가능 (음수 방지)
                                dragOffset = max(0, gesture.translation.width)
                            }
                            .onEnded { gesture in
                                isDragging = false
                                // dismissThreshold(100px) 이상 드래그하면 오버레이 닫기
                                if gesture.translation.width > dismissThreshold {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isPresented = false
                                    }
                                    dragOffset = 0
                                } else {
                                    // 임계값 미만이면 원위치
                                    dragOffset = 0
                                }
                            }
                    )
                    // 🔧 오버레이 위치 조정 (화면 가장자리로부터의 거리)
                    .padding(.leading, 20)  // 좌측 여백 (기본: 20)
                    .padding(.top, 40)  // 상단 여백 (기본: 40)
                    .padding(.bottom, 0)  // 하단 여백 (기본: 0)
                    
                    Spacer()
                }
            } else {
                // ===== 아이폰 레이아웃: 화면 하단에서 올라옴, 위로 드래그 가능 =====
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 0) {
                        // 드래그 핸들과 헤더를 포함하는 상단 영역
                        VStack(spacing: 0) {
                            // 🔧 드래그 핸들 (상단 중앙의 가로 막대)
                            RoundedRectangle(cornerRadius: 2.5)  // 🔧 모서리 둥글기 (기본: 2.5)
                                .fill(Color(UIColor.systemGray3))  // 색상 (systemGray3 = 중간 회색)
                                .frame(width: 40, height: 5)  // 🔧 크기: 너비 40, 높이 5
                                .padding(.top, 12)  // 🔧 상단 여백 (기본: 12)
                                .padding(.bottom, 8)  // 🔧 하단 여백 (기본: 8)

                            // 🔧 헤더 영역 (제목만 표시)
                            HStack {
                                Text(NSLocalizedString("main.settings.title", comment: "Settings title"))
                                    .font(.title)  // 폰트: title (큰 크기)
                                    .fontWeight(.bold)  // 두께: bold (굵게)

                                Spacer()
                            }
                            .padding(.horizontal)  // 🔧 헤더 좌우 여백 (기본: 시스템 표준)
                            .padding(.bottom, 4)  // 🔧 헤더 하단 여백 (기본: 4)
                        }
                        .background(Color(UIColor.systemBackground))  // 헤더 배경: 시스템 기본 배경색
                        .zIndex(1)  // 헤더가 설정 내용 위에 표시되도록 z-index 설정

                        // 설정 내용 (스크롤 가능한 설정 옵션들)
                        NavigationView {
                            SettingView(
                                viewModel: viewModel,
                                showColorPicker: $showColorPicker
                            )
                            .zIndex(0)  // 설정 내용은 헤더 아래에 표시
                        }
                        .navigationViewStyle(StackNavigationViewStyle())  // 스택 네비게이션 스타일 적용
                        .ignoresSafeArea(.all, edges: .top)  // 상단 세이프 에어리어 무시
                    }
                    // 🔧 오버레이 전체 크기 설정
                    .frame(maxWidth: .infinity)  // 너비: 화면 전체
                    // 🔧 높이 계산: (화면 높이 × sheetHeight) - dragOffset
                    // sheetHeight = 0.5 (50%) 또는 0.9 (90%)
                    // dragOffset = 드래그 중 이동 거리
                    .frame(height: max(geometry.size.height * sheetHeight - dragOffset, 0))
                    .background(.ultraThinMaterial)  // 블러 효과 배경 (시스템 머티리얼)
                    .clipShape(RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .phone ? 40 : 16))
                    // 🔧 모서리 둥글기: 아이폰 40, 아이패드 세로 모드 16
                    .shadow(radius: 10)  // 🔧 그림자 반경 (기본: 10)
                    // 🔧 높이 변경 애니메이션 (드래그 중이 아닐 때만)
                    .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: sheetHeight)
                    // 🔧 드래그 오프셋 애니메이션 (드래그 중이 아닐 때만)
                    .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    // response: 애니메이션 지속 시간 (0.3초)
                    // dampingFraction: 탄성 정도 (0.8 = 약간 튕김)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                }
                                // 🔧 드래그 방향: 위로 = 음수, 아래로 = 양수
                                // 아래로만 드래그 가능하도록 음수 방지
                                dragOffset = max(0, gesture.translation.height)
                            }
                            .onEnded { gesture in
                                isDragging = false
                                let translation = gesture.translation.height

                                // 🔧 경우 1: 위로 드래그 (-50px 이상) + 현재 높이 < 70% → 90%로 확장
                                if translation < expandThreshold && sheetHeight < 0.7 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        sheetHeight = 0.9  // 90%로 확장
                                    }
                                    dragOffset = 0
                                }
                                // 🔧 경우 2: 아래로 많이 드래그 (100px 이상) → 오버레이 닫기
                                else if translation > dismissThreshold {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isPresented = false
                                    }
                                    dragOffset = 0
                                    sheetHeight = 0.5  // 다음에 열릴 때를 위해 50%로 초기화
                                }
                                // 🔧 경우 3: 아래로 조금 드래그 + 현재 높이 > 70% → 50%로 축소
                                else if translation > 0 && sheetHeight > 0.7 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        sheetHeight = 0.5  // 50%로 축소
                                    }
                                    dragOffset = 0
                                }
                                // 🔧 경우 4: 그 외 (임계값 미만) → 원위치
                                else {
                                    dragOffset = 0
                                }
                            }
                    )
                    // 🔧 오버레이 위치 조정 (화면 가장자리로부터의 거리)
                    .padding(.horizontal, 16)  // 좌우 여백 (기본: 16)
                    .padding(.bottom, 16)  // 하단 여백 (기본: 16)
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: isPresented) { oldValue, newValue in
            if newValue {
                dragOffset = 0  // 열릴 때 항상 초기화
                sheetHeight = 0.5  // 아이폰: 기본 높이로 초기화
            }
        }
        .sheet(isPresented: $showColorPicker) {
            ColorPickerView(
                selected: ColorManager.shared.firstShapeColor,
                onColorSelected: { color in
                    // 선택된 색상 처리
                    ColorManager.shared.defaultColor = color
                    showColorPicker = false
                }
            )
            .presentationDetents(
                UIDevice.current.userInterfaceIdiom == .pad 
                ? [.fraction(0.87)] // 0.7 * 1.2 = 0.84
                : [.fraction(0.6)]
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showPatchNotesSheet) {
            PatchNotesView(
                patchNotes: viewModel.patchNotes,
                isLoading: viewModel.isLoadingPatchNotes
            )
        }
        .alert(NSLocalizedString("settings.deleteExpiredShapes.alert.title", comment: "Delete expired shapes alert title"), isPresented: $viewModel.showDeleteExpiredShapesAlert) {
            Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                viewModel.deleteExpiredShapes()
            }
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("settings.deleteExpiredShapes.alert.message", comment: "Delete expired shapes alert message"))
        }
        .sheet(isPresented: $viewModel.showAppInfoSheet) {
            AppInfoView()
        }
        .onAppear {
            viewModel.requestLocation()
            // KP 데이터는 앱 시작 시 이미 받아왔으므로 재요청 안함
        }
    }
}

// MARK: - Preview Helper
struct MainTabViewPreview: View {
    @State private var isSavedSheetPresented = false
    
    var body: some View {
        MainTabView()
            .onAppear {
                // 프리뷰용 더미 데이터 설정
                let dummyShapes = [
                    ShapeModel(
                        title: "드론 비행 구역 A",
                        shapeType: .circle,
                        baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                        radius: 500.0,
                        address: "서울특별시 중구 세종대로 110",
                        createdAt: Date(),
                        deletedAt: nil,
                        flightStartDate: Date(),
                        flightEndDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                        color: "#FF6B6B"
                    ),
                    ShapeModel(
                        title: "헬기 착륙장",
                        shapeType: .circle,
                        baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                        radius: 300.0,
                        address: "서울특별시 강남구 테헤란로 152",
                        createdAt: Date(),
                        deletedAt: nil,
                        flightStartDate: Date(),
                        flightEndDate: Calendar.current.date(byAdding: .day, value: 15, to: Date()),
                        color: "#4ECDC4"
                    ),
                    ShapeModel(
                        title: "공사 현장",
                        shapeType: .circle,
                        baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                        radius: 800.0,
                        address: "서울특별시 마포구 와우산로 94",
                        createdAt: Date(),
                        deletedAt: nil,
                        flightStartDate: Date(),
                        flightEndDate: Calendar.current.date(byAdding: .day, value: 60, to: Date()),
                        color: "#45B7D1"
                    ),
                    ShapeModel(
                        title: "이벤트 공간",
                        shapeType: .circle,
                        baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                        radius: 200.0,
                        address: "서울특별시 종로구 종로 1",
                        createdAt: Date(),
                        deletedAt: nil,
                        flightStartDate: Date(),
                        flightEndDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                        color: "#96CEB4"
                    ),
                    ShapeModel(
                        title: "보안 구역",
                        shapeType: .circle,
                        baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                        radius: 100000.0,
                        address: "서울특별시 용산구 이태원로 27",
                        createdAt: Date(),
                        deletedAt: nil,
                        flightStartDate: Date(),
                        flightEndDate: Calendar.current.date(byAdding: .day, value: 90, to: Date()),
                        color: "#FFEAA7"
                    ),
                    ShapeModel(
                        title: "만료된 도형",
                        shapeType: .circle,
                        baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                        radius: 150.0,
                        address: "서울특별시 서초구 서초대로 396",
                        createdAt: Date(),
                        deletedAt: nil,
                        flightStartDate: Date(),
                        flightEndDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()), // 5일 전 만료
                        color: "#8E8E93"
                    )
                ]
                
                ShapeFileStore.shared.shapes = dummyShapes
            }
    }
}

// MARK: - Simple Preview for Saved Tab
struct SavedTabPreview: View {
    @State private var isSavedSheetPresented = true
    
    var body: some View {
        ZStack {
            Color.gray.opacity(0.1)
                .ignoresSafeArea()
            
            VStack {
                Text("저장 탭 프리뷰")
                    .font(.title)
                    .padding()
                
                Button("저장 목록 열기") {
                    isSavedSheetPresented = true
                }
                .padding()
            }
        }
        .overlay(
            Group {
                if isSavedSheetPresented {
                    SavedListOverlayView(
                        selectedShapeID: .constant(nil),
                        isPresented: $isSavedSheetPresented,
                        shapeIDToScrollTo: .constant(nil)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        )
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isSavedSheetPresented)
        .onAppear {
            // 프리뷰용 더미 데이터 설정
            let dummyShapes = [
                ShapeModel(
                    title: "드론 비행 구역 A",
                    shapeType: .circle,
                    baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                    radius: 500.0,
                    address: "서울특별시 중구 세종대로 110",
                    createdAt: Date(),
                    deletedAt: nil,
                    flightStartDate: Date(),
                    flightEndDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                    color: "#FF6B6B"
                ),
                ShapeModel(
                    title: "헬기 착륙장",
                    shapeType: .circle,
                    baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                    radius: 300.0,
                    address: "서울특별시 강남구 테헤란로 152",
                    createdAt: Date(),
                    deletedAt: nil,
                    flightStartDate: Date(),
                    flightEndDate: Calendar.current.date(byAdding: .day, value: 15, to: Date()),
                    color: "#4ECDC4"
                ),
                ShapeModel(
                    title: "공사 현장",
                    shapeType: .circle,
                    baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                    radius: 800.0,
                    address: "서울특별시 마포구 와우산로 94",
                    createdAt: Date(),
                    deletedAt: nil,
                    flightStartDate: Date(),
                    flightEndDate: Calendar.current.date(byAdding: .day, value: 60, to: Date()),
                    color: "#45B7D1"
                ),
                ShapeModel(
                    title: "이벤트 공간",
                    shapeType: .circle,
                    baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                    radius: 200.0,
                    address: "서울특별시 종로구 종로 1",
                    createdAt: Date(),
                    deletedAt: nil,
                    flightStartDate: Date(),
                    flightEndDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                    color: "#96CEB4"
                ),
                ShapeModel(
                    title: "보안 구역",
                    shapeType: .circle,
                    baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                    radius: 100000.0,
                    address: "서울특별시 용산구 이태원로 27",
                    createdAt: Date(),
                    deletedAt: nil,
                    flightStartDate: Date(),
                    flightEndDate: Calendar.current.date(byAdding: .day, value: 90, to: Date()),
                    color: "#FFEAA7"
                ),
                ShapeModel(
                    title: "만료된 도형",
                    shapeType: .circle,
                    baseCoordinate: CoordinateManager(latitude: 37.5665, longitude: 126.9780),
                    radius: 150.0,
                    address: "서울특별시 서초구 서초대로 396",
                    createdAt: Date(),
                    deletedAt: nil,
                    flightStartDate: Date(),
                    flightEndDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()), // 5일 전 만료
                    color: "#8E8E93"
                )
            ]
            
            ShapeFileStore.shared.shapes = dummyShapes
        }
    }
}

// MARK: - Push Notification Popup View (푸시 알림 팝업)
/// 푸시 알림 탭 시 화면 중앙에 표시되는 팝업
struct PushNotificationPopupView: View {
    let notification: PushNotificationData
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // 반투명 배경 (터치 시 닫기)
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // 팝업 카드
            VStack(spacing: 20) {
                // 아이콘
                Image(systemName: "bell.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .padding(.top, 8)

                // 제목
                Text(notification.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.primary)

                // 내용
                Text(notification.body)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 확인 버튼
                Button(action: {
                    onDismiss()
                }) {
                    Text(NSLocalizedString("common.confirm", comment: "Confirm"))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 400 : 320)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
}

#Preview("Main Tab View") {
    MainTabViewPreview()
}

#Preview("Saved Tab") {
    SavedTabPreview()
}
