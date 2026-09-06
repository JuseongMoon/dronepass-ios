//
//  SettingView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//

import SwiftUI
import CoreLocation
import Solar
import Combine // Added for Combine

/// 앱에서 지원하는 언어
enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"

    var displayName: String {
        switch self {
        case .korean: return NSLocalizedString("settings.language.korean", comment: "Korean")
        case .english: return NSLocalizedString("settings.language.english", comment: "English")
        }
    }
}

struct SettingView: View {
    @ObservedObject var viewModel: SettingViewModel
    @ObservedObject var settingManager = SettingManager.shared
    @Binding var showColorPicker: Bool

    @State private var showLoginSheet = false
    @State private var showTermsAndPolicies = false
    @State private var navigateToProfile = false
    @State private var showProfileSheet = false
    @State private var showDroneManagementSheet = false
    @State private var showLanguageChangeAlert = false
    @State private var showKoreaFeaturesOnAlert = false
    @State private var showKoreaFeaturesOffAlert = false
    @State private var selectedLanguage: AppLanguage = {
        if let savedLanguage = UserDefaults.standard.string(forKey: "AppLanguage"),
           let language = AppLanguage(rawValue: savedLanguage) {
            return language
        }
        // 저장된 값 없으면 시스템 언어 기반 (한국어=korean, 그 외=english)
        let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        return systemLanguage == "ko" ? .korean : .english
    }()

    var body: some View {
        List {
            /// 내 정보 Section
            Section {
                if viewModel.isLoggedIn {
                    Button {
                        showProfileSheet = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("settings.profile.my", comment: "My Profile"))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                } else {
                    Button {
                        showLoginSheet = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("settings.profile.login", comment: "Sign In / Sign Up"))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }

                Button {
                    showDroneManagementSheet = true
                } label: {
                    HStack {
                        Text(NSLocalizedString("settings.drone.manage", comment: "Manage My Drones"))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            } header: {
                Text(NSLocalizedString("settings.section.myInfo", comment: "My Info"))
            }
            
            // 비행 환경 Section
            Section {
                // KP 지수 버튼
                Button(action: {
                    viewModel.showKPForecastSheet = true
                }) {
                    HStack {
                        Text(String(format: NSLocalizedString("settings.kp.current", comment: "Current KP Index"), viewModel.currentKPString))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 날씨 버튼
                Button(action: {
                    viewModel.showWeatherInfoSheet = true
                }) {
                    HStack {
                        Text(NSLocalizedString("settings.weather.current", comment: "Current Weather"))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(NSLocalizedString("settings.section.flightEnvironment", comment: "Flight Environment"))
            }
            
            // 알림 Section
            Section {
                Toggle(isOn: $viewModel.isEndDateAlarmEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.notification.shapeExpiry", comment: "Shape expiration notifications"))
                        Text(NSLocalizedString("settings.notification.shapeExpiry.desc", comment: "Receive notifications 7 days before shape expiration."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: viewModel.isEndDateAlarmEnabled) { oldValue, newValue in
                    SettingManager.shared.isEndDateAlarmEnabled = newValue
                }

                Toggle(isOn: $viewModel.isSunriseAlarmEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.notification.sunrise", comment: "Sunrise notifications"))
                        Text(NSLocalizedString("settings.notification.sunrise.desc", comment: "Receive notifications 30 and 10 minutes before sunrise."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: viewModel.isSunriseAlarmEnabled) { oldValue, newValue in
                    SettingManager.shared.isSunriseAlarmEnabled = newValue
                }

                Toggle(isOn: $viewModel.isSunsetAlarmEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.notification.sunset", comment: "Sunset notifications"))
                        Text(NSLocalizedString("settings.notification.sunset.desc", comment: "Receive notifications 30 and 10 minutes before sunset."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: viewModel.isSunsetAlarmEnabled) { oldValue, newValue in
                    SettingManager.shared.isSunsetAlarmEnabled = newValue
                }
            } header: {
                Text(NSLocalizedString("settings.section.notifications", comment: "Notifications"))
            }
            
            // 지도 표시 Section
            Section {
                Toggle(isOn: $viewModel.isKeepScreenAwakeEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.screen.keepOn", comment: "Keep screen on"))
                        Text(NSLocalizedString("settings.screen.keepOn.desc", comment: "Screen won\'t turn off automatically while using the app."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: viewModel.isKeepScreenAwakeEnabled) { oldValue, newValue in
                    SettingManager.shared.isKeepScreenAwakeEnabled = newValue
                }

                Toggle(isOn: $viewModel.isHideNotStartedShapesEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.shape.hideBeforeStart", comment: "Hide shapes before start date"))
                        Text(NSLocalizedString("settings.shape.hideBeforeStart.desc", comment: "Hide shapes that haven\'t started yet from list and map."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: viewModel.isHideNotStartedShapesEnabled) { oldValue, newValue in
                    SettingManager.shared.isHideNotStartedShapesEnabled = newValue
                }

                Toggle(isOn: $viewModel.isHideExpiredShapesEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.shape.hideExpired", comment: "Hide expired shapes"))
                        Text(NSLocalizedString("settings.shape.hideExpired.desc", comment: "Hide expired shapes from list and map."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: viewModel.isHideExpiredShapesEnabled) { oldValue, newValue in
                    SettingManager.shared.isHideExpiredShapesEnabled = newValue
                }

                Button(role: .destructive) {
                    viewModel.showDeleteExpiredShapesAlert = true
                } label: {
                    Text(NSLocalizedString("settings.shape.deleteExpired", comment: "Delete all expired shapes"))
                }
            } header: {
                Text(NSLocalizedString("settings.section.mapDisplay", comment: "Map Display"))
            }
            
            // 앱 Section
            Section {
                // 언어 설정
                Picker(NSLocalizedString("settings.language", comment: "Language"), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: selectedLanguage) { oldValue, newValue in
                    // 언어 변경 저장
                    UserDefaults.standard.set(newValue.rawValue, forKey: "AppLanguage")
                    UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
                    UserDefaults.standard.synchronize()

                    // 알림 표시
                    showLanguageChangeAlert = true
                }

                // 한국 특화 기능 토글
                Toggle(NSLocalizedString("settings.koreaFeatures.toggle", comment: "Korea-specific Features"),
                       isOn: $settingManager.isKoreaFeaturesEnabled)
                    .onChange(of: settingManager.isKoreaFeaturesEnabled) { _, newValue in
                        // 켤 때도 끌 때도 오버레이 모두 끄기 (체크 해제 상태로 시작)
                        NotificationCenter.default.post(name: Notification.Name("HideAllFlightZones"), object: nil)

                        if newValue {
                            showKoreaFeaturesOnAlert = true
                        } else {
                            showKoreaFeaturesOffAlert = true
                        }
                    }

                Button {
                    viewModel.showAppInfoSheet = true
                } label: {
                    Text(NSLocalizedString("settings.appInfo", comment: "App Info"))
                }

                Button {
                    viewModel.fetchAndShowPatchNotes()
                } label: {
                    Text(NSLocalizedString("settings.patchNotes", comment: "Patch Notes"))
                }
            } header: {
                Text(NSLocalizedString("settings.section.app", comment: "App"))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // 모든 기기에서 sheet로 LoginView 표시
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
        .sheet(isPresented: $showProfileSheet) {
            NavigationView {
                ProfileView()
            }
        }
        .sheet(isPresented: $showDroneManagementSheet) {
            NavigationView {
                DroneListView()
            }
        }
        .sheet(isPresented: $viewModel.showKPForecastSheet) {
            KPForecastView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $viewModel.showWeatherInfoSheet) {
            WeatherForecastView()
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        .onAppear {
            // 언어 변경 알림 감지
            NotificationCenter.default.addObserver(forName: Notification.Name("LanguageChanged"), object: nil, queue: .main) { _ in
                showLanguageChangeAlert = true
            }
        }
        .alert(NSLocalizedString("settings.language.restart.title", comment: "Language changed title"), isPresented: $showLanguageChangeAlert) {
            Button(NSLocalizedString("common.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("settings.language.restart.message", comment: "Language changed message"))
        }
        .alert(NSLocalizedString("settings.koreaFeatures.alert.on.title", comment: "Korea Features Enabled"), isPresented: $showKoreaFeaturesOnAlert) {
            Button(NSLocalizedString("common.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("settings.koreaFeatures.alert.on.message", comment: "Korea features on message"))
        }
        .alert(NSLocalizedString("settings.koreaFeatures.alert.off.title", comment: "Korea Features Disabled"), isPresented: $showKoreaFeaturesOffAlert) {
            Button(NSLocalizedString("common.ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("settings.koreaFeatures.alert.off.message", comment: "Korea features off message"))
        }
    }
}




// MARK: - ViewModel
@MainActor
final class SettingViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var sunriseTime: String = "-"
    @Published var sunriseSuffix: String = ""
    @Published var sunriseSuffixColor: Color = .primary
    
    @Published var sunsetTime: String = "-"
    @Published var sunsetSuffix: String = ""
    @Published var sunsetSuffixColor: Color = .primary
    
    @Published var isEndDateAlarmEnabled: Bool = SettingManager.shared.isEndDateAlarmEnabled
    @Published var isSunriseAlarmEnabled: Bool = SettingManager.shared.isSunriseAlarmEnabled
    @Published var isSunsetAlarmEnabled: Bool = SettingManager.shared.isSunsetAlarmEnabled
    @Published var isHideNotStartedShapesEnabled: Bool = SettingManager.shared.isHideNotStartedShapesEnabled
    @Published var isHideExpiredShapesEnabled: Bool = SettingManager.shared.isHideExpiredShapesEnabled
    @Published var isKeepScreenAwakeEnabled: Bool = SettingManager.shared.isKeepScreenAwakeEnabled
    @Published var selectedColor: Color = .blue
    
    @Published var showDeleteExpiredShapesAlert = false
    @Published var showAppInfoSheet = false
    @Published var showPatchNotesSheet = false
    @Published var patchNotes: [FetchWebDocuments.PatchNote] = []
    @Published var isLoadingPatchNotes = false
    @Published var isLoggedIn: Bool = AppleLoginManager.shared.isLogin // 로그인 상태 관리

    // KP 지수 관련
    @Published var currentKPString: String = "-"
    @Published var currentKPLevel: String = NSLocalizedString("settings.kp.loading", comment: "Loading")
    @Published var showKPForecastSheet = false

    // 날씨 정보 관련
    @Published var currentTemperature: String = "-"
    @Published var currentWindSpeed: String = "-"
    @Published var showWeatherInfoSheet = false

    private var loginCancellable: AnyCancellable?
    private var patchNotesCancellables: Set<AnyCancellable> = []
    private var kpIndexCancellables: Set<AnyCancellable> = []
    private var weatherCancellables: Set<AnyCancellable> = []
    var webDocuments = FetchWebDocuments()
    private let kpIndexManager = KPIndexManager.shared
    private let weatherManager = WeatherManager.shared
    private var kpFetchTask: Task<Void, Never>?

    var appInfoText: String {
        let features = AppInfo.Description.features.map { "• \($0)" }.joined(separator: "\n")
        return """
        Ver. \(AppInfo.Version.current)

        \(AppInfo.Description.intro)

        [주요 기능]
        \(features)

        \(AppInfo.Description.contact)
        """
    }

    private let locationManager = CLLocationManager()
    private var timer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        // LoginManager의 isLogin을 구독하여 isLoggedIn과 동기화
        loginCancellable = AppleLoginManager.shared.$isLogin
            .receive(on: RunLoop.main)
            .assign(to: \Self.isLoggedIn, on: self)

        // FetchWebDocuments의 상태를 구독하여 동기화
        webDocuments.$showPatchNotesSheet
            .receive(on: RunLoop.main)
            .assign(to: \Self.showPatchNotesSheet, on: self)
            .store(in: &patchNotesCancellables)

        webDocuments.$patchNotes
            .receive(on: RunLoop.main)
            .assign(to: \Self.patchNotes, on: self)
            .store(in: &patchNotesCancellables)

        webDocuments.$isLoadingPatchNotes
            .receive(on: RunLoop.main)
            .assign(to: \Self.isLoadingPatchNotes, on: self)
            .store(in: &patchNotesCancellables)

        // KPIndexManager 구독
        setupKPIndexSubscription()

        // WeatherManager 구독
        setupWeatherSubscription()
    }

    func startKPDataFetch() {
        // 이미 실행 중인 Task가 있으면 취소
        kpFetchTask?.cancel()

        // 새 Task 생성 및 저장
        kpFetchTask = Task { [weak self] in
            guard let self = self else { return }
            print("🚀 SettingViewModel: KP 데이터 가져오기 시작")
            await self.kpIndexManager.fetchKPData(forceRefresh: true)
        }
    }

    private func setupKPIndexSubscription() {
        // 현재 KP 값 구독
        kpIndexManager.$currentKP
            .receive(on: RunLoop.main)
            .sink { [weak self] kpData in
                guard let self = self, let kpData = kpData else {
                    self?.currentKPString = "-"
                    self?.currentKPLevel = NSLocalizedString("settings.kp.noData", comment: "No data")
                    return
                }
                self.currentKPString = String(format: "%.1f", kpData.kp)
                self.currentKPLevel = KPLevel.level(from: kpData.kp).rawValue
            }
            .store(in: &kpIndexCancellables)
    }

    private func setupWeatherSubscription() {
        // 온도 구독
        weatherManager.$temperature
            .receive(on: RunLoop.main)
            .sink { [weak self] temperature in
                guard let self = self else { return }
                if let temperature = temperature {
                    self.currentTemperature = String(format: "%.1f°C", temperature)
                } else {
                    self.currentTemperature = "-"
                }
            }
            .store(in: &weatherCancellables)

        // 풍속 구독
        weatherManager.$windSpeed
            .receive(on: RunLoop.main)
            .sink { [weak self] windSpeed in
                guard let self = self else { return }
                if let windSpeed = windSpeed {
                    self.currentWindSpeed = String(format: "%.1f m/s", windSpeed)
                } else {
                    self.currentWindSpeed = "-"
                }
            }
            .store(in: &weatherCancellables)
    }

    func fetchAndShowPatchNotes() {
        webDocuments.fetchAndShowPatchNotes()
    }
    
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateSunriseSunset(for: location)
        startTimer(location: location)
    }
    
    private func startTimer(location: CLLocation) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateSunriseSunset(for: location)
        }
    }
    
    private func updateSunriseSunset(for location: CLLocation) {
        let now = Date()
        let calendar = Calendar.current

        guard let solarToday = Solar(for: now, coordinate: location.coordinate),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let solarTomorrow = Solar(for: tomorrow, coordinate: location.coordinate)
        else {
            sunriseTime = NSLocalizedString("settings.suntime.unavailable", comment: "Unavailable")
            sunsetTime = NSLocalizedString("settings.suntime.unavailable", comment: "Unavailable")
            sunriseSuffix = ""
            sunsetSuffix = ""
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.amSymbol = NSLocalizedString("settings.suntime.am", comment: "AM")
        dateFormatter.pmSymbol = NSLocalizedString("settings.suntime.pm", comment: "PM")
        dateFormatter.dateFormat = NSLocalizedString("settings.suntime.format", comment: "a h:mm")
        dateFormatter.timeZone = TimeZone.current

        // 일출/일몰 시간 가져오기
        let sunriseToday = solarToday.sunrise
        let sunsetToday = solarToday.sunset
        let sunriseTomorrow = solarTomorrow.sunrise

        // Helper 함수
        func formatTimeString(hour: Int, minute: Int) -> String {
            if hour > 0 {
                return String(format: NSLocalizedString("settings.suntime.remaining.hourMinute", comment: "%d hours %d minutes remaining"), hour, minute)
            } else {
                return String(format: NSLocalizedString("settings.suntime.remaining.minute", comment: "%d minutes remaining"), minute)
            }
        }

        // 일출 계산: 항상 다음 일출까지 남은 시간 표시
        if let sunriseToday = sunriseToday, now < sunriseToday {
            // 오늘 일출 전: 일출까지 남은 시간
            let diff = Int(sunriseToday.timeIntervalSince(now))
            let hour = diff / 3600
            let minute = (diff % 3600) / 60
            sunriseTime = dateFormatter.string(from: sunriseToday)
            sunriseSuffix = formatTimeString(hour: hour, minute: minute)
            sunriseSuffixColor = .red
        } else if let sunriseTomorrow = sunriseTomorrow {
            // 오늘 일출 후 또는 일출이 없는 경우: 내일 일출까지 남은 시간
            let diff = Int(sunriseTomorrow.timeIntervalSince(now))
            let hour = diff / 3600
            let minute = (diff % 3600) / 60
            sunriseTime = dateFormatter.string(from: sunriseTomorrow)
            sunriseSuffix = formatTimeString(hour: hour, minute: minute)
            sunriseSuffixColor = .red
        }

        // 일몰 계산: 항상 다음 일몰까지 남은 시간 표시
        if let sunsetToday = sunsetToday, now < sunsetToday {
            // 오늘 일몰 전: 일몰까지 남은 시간
            let diff = Int(sunsetToday.timeIntervalSince(now))
            let hour = diff / 3600
            let minute = (diff % 3600) / 60
            sunsetTime = dateFormatter.string(from: sunsetToday)
            sunsetSuffix = formatTimeString(hour: hour, minute: minute)
            sunsetSuffixColor = .red
        } else {
            // 오늘 일몰 후: 내일 일몰 시간이 필요
            let sunsetTomorrow = solarTomorrow.sunset
            if let sunsetTomorrow = sunsetTomorrow {
                let diff = Int(sunsetTomorrow.timeIntervalSince(now))
                let hour = diff / 3600
                let minute = (diff % 3600) / 60
                sunsetTime = dateFormatter.string(from: sunsetTomorrow)
                sunsetSuffix = formatTimeString(hour: hour, minute: minute)
                sunsetSuffixColor = .red
            }
        }
    }
    
    func setEndDateAlarmEnabled(_ value: Bool) {
        SettingManager.shared.isEndDateAlarmEnabled = value
        isEndDateAlarmEnabled = value
    }

    func setSunriseAlarmEnabled(_ value: Bool) {
        SettingManager.shared.isSunriseAlarmEnabled = value
        isSunriseAlarmEnabled = value
    }

    func setSunsetAlarmEnabled(_ value: Bool) {
        SettingManager.shared.isSunsetAlarmEnabled = value
        isSunsetAlarmEnabled = value
    }

    func deleteExpiredShapes() {
        SettingManager.shared.deleteExpiredShapes()
    }
}

extension View {
    @ViewBuilder
    func applyNavigationViewStyle(_ horizontalSizeClass: UserInterfaceSizeClass?) -> some View {
        if horizontalSizeClass == .regular {
            self.navigationViewStyle(DoubleColumnNavigationViewStyle())
        } else {
            self.navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

// ViewModifier를 위한 if extension
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    SettingView(viewModel: SettingViewModel(), showColorPicker: .constant(false))
}

