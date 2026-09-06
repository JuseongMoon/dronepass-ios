//
//  SettingManager.swift
//  DronePass
//
//  Created by 문주성 on 5/25/25.
//
// 이사검증완료

import Foundation
import UIKit              // UIApplication 사용을 위한 프레임워크
import UserNotifications   // iOS의 푸시 알림(로컬 알림 포함) 기능을 사용하기 위한 프레임워크
import CoreLocation       // 위치정보(위도/경도 등)를 다루기 위한 프레임워크
import Combine           // ObservableObject 사용을 위한 프레임워크

/// 앱 전체에서 알림 및 설정 관련 기능을 담당하는 싱글톤 객체입니다.
/// (이 객체를 통해 알림, 일출/일몰 스케줄링, 종료일 알림 관리 등 수행)
@MainActor
final class SettingManager: ObservableObject {
    // 전역에서 공유해서 사용하기 위한 싱글톤 인스턴스 생성
    static let shared = SettingManager()

    /// Combine 구독 저장소
    private var cancellables = Set<AnyCancellable>()

    /// 일출/일몰 전환용 타이머
    private var sunEventTimer: DispatchWorkItem?

    /// 외부에서 새로운 인스턴스를 만들지 못하도록 private으로 선언(싱글톤 패턴)
    private init() {
        // 객체가 처음 생성될 때 알림 권한을 요청합니다.
        requestNotificationPermission()
        initializeAppLanguage() // 초기화 시 앱 언어 설정 (한국 현지 기능보다 먼저)
        loadCloudBackupSetting() // 초기화 시 클라우드 백업 설정 로드
        loadDroneCategorySetting() // 초기화 시 드론 카테고리 설정 로드
        loadKeepScreenAwakeSetting() // 초기화 시 화면 켜놓기 설정 로드
        loadKoreaFeaturesSetting() // 초기화 시 한국 특화 기능 설정 로드
        setupLocationObserver() // 위치 업데이트 관찰 설정
        setupWeatherObserver() // WeatherManager 데이터 변경 자동 감지 설정
        setupTimeUpdateTimer() // 1분마다 남은 시간 업데이트 타이머 설정
        restoreNotificationSchedules() // 앱 시작 시 기존 알림 설정 복구
    }

    // MARK: - 종료일 알림 관련 프로퍼티

    /// 종료일 알림 활성화 여부를 저장하는 UserDefaults 키(문자열 상수)
    private let endDateAlarmKey = "endDateAlarmEnabled"

    /// 종료일 알림 활성화 여부를 저장/불러오기 위한 프로퍼티
    /// - get: UserDefaults에서 불러옴
    /// - set: UserDefaults에 저장, 값이 true면 알림 스케줄링/false면 알림 해제
    var isEndDateAlarmEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: endDateAlarmKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: endDateAlarmKey)
            if newValue {
                // 설정 ON: 모든 도형에 대해 알림 스케줄링
                let shapes = ShapeFileStore.shared.shapes
                scheduleEndDateAlarms(for: shapes)
            } else {
                // 해제 시 알림 모두 제거
                removeEndDateAlarms()
            }
        }
    }

    /// 종료일 알림 상세 설명 텍스트(설정화면 등에 사용)
    var endDateAlarmDetailText: String {
        isEndDateAlarmEnabled ? "도형의 종료일이 다가오면 알림을 받습니다." : "알림이 꺼져 있습니다."
    }

    // MARK: - 일출/일몰 알림 관련 프로퍼티

    /// 일출 알림 활성화 여부를 저장하는 UserDefaults 키
    private let sunriseAlarmKey = "sunriseAlarmEnabled"

    /// 일몰 알림 활성화 여부를 저장하는 UserDefaults 키
    private let sunsetAlarmKey = "sunsetAlarmEnabled"

    /// 일출 알림 활성화 여부 프로퍼티 (UserDefaults에 저장/불러오기)
    var isSunriseAlarmEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: sunriseAlarmKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: sunriseAlarmKey)
            if newValue {
                if let location = LocationManager.shared.currentLocation {
                    // 현재 위치가 있다면 일출 알림 예약
                    scheduleSunriseSunsetAlarms(for: location.coordinate)
                }
            } else {
                // 비활성화시 일출 알림 삭제
                removeSunriseAlarms()
            }
        }
    }

    /// 일몰 알림 활성화 여부 프로퍼티 (UserDefaults에 저장/불러오기)
    var isSunsetAlarmEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: sunsetAlarmKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: sunsetAlarmKey)
            if newValue {
                if let location = LocationManager.shared.currentLocation {
                    // 현재 위치가 있다면 일몰 알림 예약
                    scheduleSunriseSunsetAlarms(for: location.coordinate)
                }
            } else {
                // 비활성화시 일몰 알림 삭제
                removeSunsetAlarms()
            }
        }
    }

    /// 일출 알림 상세 설명 텍스트
    var sunriseAlarmDetailText: String {
        isSunriseAlarmEnabled ? "일출 30분전, 10분전 알림을 받습니다." : "알림이 꺼져 있습니다."
    }

    /// 일몰 알림 상세 설명 텍스트
    var sunsetAlarmDetailText: String {
        isSunsetAlarmEnabled ? "일몰 30분전, 10분전 알림을 받습니다." : "알림이 꺼져 있습니다."
    }

    // MARK: - 일출/일몰 UI 표시용 프로퍼티

    /// 오늘 일출 시간 (항상 오늘)
    @Published var todaySunrise: Date?

    /// 오늘 일몰 시간 (항상 오늘)
    @Published var todaySunset: Date?

    /// 내일 일출 시간 (항상 내일)
    @Published var tomorrowSunrise: Date?

    /// 현재 낮/밤 여부 (true: 낮, false: 밤)
    @Published var isDaytime: Bool = true

    /// 일출/일몰 아이콘 이름 (낮이면 일몰 아이콘, 밤이면 일출 아이콘)
    var sunEventIconName: String {
        isDaytime ? "sunset.fill" : "sunrise.fill"
    }

    /// 다음 일출/일몰까지 남은 시간을 HH:MM 형식으로 반환 (1분마다 자동 업데이트)
    @Published var timeUntilNextSunEvent: String = "--:--"

    // MARK: - 만료된 도형 숨기기 관련 프로퍼티

    /// 만료된 도형 숨기기 활성화 여부를 저장하는 UserDefaults 키
    private let hideExpiredShapesKey = "hideExpiredShapesEnabled"

    /// 만료된 도형 숨기기 활성화 여부 프로퍼티 (UserDefaults에 저장/불러오기)
    var isHideExpiredShapesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: hideExpiredShapesKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideExpiredShapesKey)
            // 설정 변경 시 지도 오버레이 리로드 알림 전송
            NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
        }
    }

    // MARK: - 시작 전 도형 숨기기 관련 프로퍼티

    /// 시작 전 도형 숨기기 활성화 여부를 저장하는 UserDefaults 키
    private let hideNotStartedShapesKey = "hideNotStartedShapesEnabled"

    /// 시작 전 도형 숨기기 활성화 여부 프로퍼티 (UserDefaults에 저장/불러오기)
    var isHideNotStartedShapesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: hideNotStartedShapesKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideNotStartedShapesKey)
            // 설정 변경 시 지도 오버레이 리로드 알림 전송
            NotificationCenter.default.post(name: Notification.Name("ReloadMapOverlays"), object: nil)
        }
    }

    // MARK: - 클라우드 백업 관련 프로퍼티

    /// 클라우드 백업 활성화 여부를 저장하는 UserDefaults 키
    private let cloudBackupKey = "cloudBackupEnabled"

    /// 클라우드 백업 활성화 여부 프로퍼티 (UserDefaults에 저장/불러오기)
    @Published var isCloudBackupEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isCloudBackupEnabled, forKey: cloudBackupKey)
        }
    }

    // MARK: - 화면 항상 켜놓기 설정

    /// 화면 항상 켜놓기 활성화 여부를 저장하는 UserDefaults 키
    private let keepScreenAwakeKey = "keepScreenAwakeEnabled"

    /// 화면 항상 켜놓기 활성화 여부 프로퍼티 (UserDefaults에 저장/불러오기)
    var isKeepScreenAwakeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: keepScreenAwakeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: keepScreenAwakeKey)
            // 메인 스레드에서 실행 (UI 관련 설정)
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = newValue
                print("✅ 화면 항상 켜놓기: \(newValue ? "활성화" : "비활성화")")
            }
        }
    }

    // MARK: - 드론 카테고리 설정

    /// 드론 카테고리를 저장하는 UserDefaults 키
    private let droneCategoryKey = "selectedDroneCategory"

    /// 선택된 드론 카테고리 (기본값: 3급 드론)
    @Published var selectedDroneCategory: DroneCategory = .class3 {
        didSet {
            UserDefaults.standard.set(selectedDroneCategory.rawValue, forKey: droneCategoryKey)
            print("✅ 드론 카테고리 변경: \(selectedDroneCategory.rawValue)")
        }
    }

    // MARK: - 앱 언어 설정

    /// 앱 언어 설정 키
    private let appLanguageKey = "AppLanguage"

    /// 앱 첫 실행 시 시스템 언어에 따라 앱 언어 초기화
    /// - 시스템 언어가 한국어: 한국어로 설정
    /// - 그 외: 영어로 설정
    private func initializeAppLanguage() {
        // 이미 언어가 설정되어 있으면 스킵
        if UserDefaults.standard.string(forKey: appLanguageKey) != nil {
            print("✅ 앱 언어 이미 설정됨")
            return
        }

        // 시스템 언어 확인
        let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let appLanguage = systemLanguage == "ko" ? "ko" : "en"

        // 앱 언어 설정 저장
        UserDefaults.standard.set(appLanguage, forKey: appLanguageKey)
        UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        print("✅ 앱 언어 초기화: \(appLanguage == "ko" ? "한국어" : "영어") (시스템 언어: \(systemLanguage))")
    }

    // MARK: - 한국 특화 기능 설정

    /// 한국 특화 기능(드론 공역 UI) 활성화 여부를 저장하는 UserDefaults 키
    private let koreaFeaturesEnabledKey = "KoreaFeaturesEnabled"

    /// 한국 특화 기능 활성화 여부
    /// - 한국어: 기본 true
    /// - 영어: 기본 false
    @Published var isKoreaFeaturesEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isKoreaFeaturesEnabled, forKey: koreaFeaturesEnabledKey)
            print("✅ 한국 특화 기능 변경: \(isKoreaFeaturesEnabled ? "활성화" : "비활성화")")
        }
    }

    /// 초기화 시 UserDefaults에서 값 불러오기
    private func loadCloudBackupSetting() {
        // 처음 설치 시에는 기본값을 false로 설정
        if !UserDefaults.standard.bool(forKey: "\(cloudBackupKey)_initialized") {
            UserDefaults.standard.set(false, forKey: cloudBackupKey)
            UserDefaults.standard.set(true, forKey: "\(cloudBackupKey)_initialized")
        }

        isCloudBackupEnabled = UserDefaults.standard.bool(forKey: cloudBackupKey)
        print("✅ 클라우드 백업 설정 로드: \(isCloudBackupEnabled ? "활성화" : "비활성화")")
    }

    /// UserDefaults에서 드론 카테고리 설정 로드
    private func loadDroneCategorySetting() {
        if let savedCategory = UserDefaults.standard.string(forKey: droneCategoryKey),
           let category = DroneCategory(rawValue: savedCategory) {
            selectedDroneCategory = category
            print("✅ 드론 카테고리 로드: \(category.rawValue)")
        } else {
            // 기본값: 3급 드론 (보수적 접근)
            selectedDroneCategory = .class3
            UserDefaults.standard.set(selectedDroneCategory.rawValue, forKey: droneCategoryKey)
            print("✅ 드론 카테고리 기본값 설정: 3급 드론")
        }
    }

    /// UserDefaults에서 화면 켜놓기 설정 로드
    private func loadKeepScreenAwakeSetting() {
        let isEnabled = UserDefaults.standard.bool(forKey: keepScreenAwakeKey)
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = isEnabled
            print("✅ 화면 항상 켜놓기 설정 로드: \(isEnabled ? "활성화" : "비활성화")")
        }
    }

    /// UserDefaults에서 한국 특화 기능 설정 로드
    /// - 앱 첫 실행 시: 언어에 따라 기본값 설정 (한국어=ON, 영어=OFF)
    /// - 이후: 저장된 값 사용 (언어 변경에 영향받지 않음)
    private func loadKoreaFeaturesSetting() {
        // 키가 설정된 적 없으면 (첫 실행) 언어에 따라 기본값 설정
        if UserDefaults.standard.object(forKey: koreaFeaturesEnabledKey) == nil {
            // 앱 내부 언어 설정 확인 (없으면 시스템 언어 사용)
            let isKorean: Bool
            if let appLanguage = UserDefaults.standard.string(forKey: "AppLanguage") {
                isKorean = appLanguage == "ko"
            } else {
                isKorean = Locale.current.language.languageCode?.identifier == "ko"
            }
            isKoreaFeaturesEnabled = isKorean
            print("✅ 한국 특화 기능 기본값 설정: \(isKorean ? "활성화" : "비활성화")")
        } else {
            // 이미 설정된 값 사용 (언어 변경에 영향받지 않음)
            isKoreaFeaturesEnabled = UserDefaults.standard.bool(forKey: koreaFeaturesEnabledKey)
            print("✅ 한국 특화 기능 로드: \(isKoreaFeaturesEnabled ? "활성화" : "비활성화")")
        }
    }

    /// 앱 시작 시 기존 알림 설정을 복구하여 알림 재스케줄링
    private func restoreNotificationSchedules() {
        print("🔔 앱 시작 시 알림 설정 복구 시작...")

        // 도형 만료일 알림 복구
        if isEndDateAlarmEnabled {
            let shapes = ShapeFileStore.shared.shapes
            scheduleEndDateAlarms(for: shapes)
            print("✅ 도형 만료일 알림 복구 완료: \(shapes.count)개 도형")
        }

        // 일출/일몰 알림 복구 (위치 및 날씨 정보가 준비되면 실행)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if let location = LocationManager.shared.currentLocation {
                if self.isSunriseAlarmEnabled || self.isSunsetAlarmEnabled {
                    self.scheduleSunriseSunsetAlarms(for: location.coordinate)
                    print("✅ 일출/일몰 알림 복구 완료")
                }
            } else {
                print("⚠️ 위치 정보 없음 - 일출/일몰 알림 복구 대기 중")
            }
        }
    }

    // MARK: - 위치 업데이트 관찰

    /// LocationManager의 위치 업데이트를 관찰하여 일출/일몰 정보를 자동 갱신
    private func setupLocationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocationUpdate(_:)),
            name: NSNotification.Name("LocationDidUpdate"),
            object: nil
        )
    }

    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let location = notification.userInfo?["location"] as? CLLocation else { return }
        // scheduleNextSunEventTimer() 내부에서 updateSunriseSunsetInfo() 호출하여 모든 정보 업데이트
        scheduleNextSunEventTimer()
        print("📍 위치 업데이트: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }

    /// WeatherManager의 일출/일몰 데이터 변경을 자동으로 감지하여 SettingManager 업데이트
    private func setupWeatherObserver() {
        Publishers.CombineLatest3(
            WeatherManager.shared.$sunriseTime,
            WeatherManager.shared.$sunsetTime,
            WeatherManager.shared.$tomorrowSunriseTime
        )
        .debounce(for: 0.3, scheduler: RunLoop.main)  // 연속 변경 방지
        .sink { [weak self] sunrise, sunset, tomorrowSunrise in
            guard let self = self else { return }

            // nil 체크: 일출/일몰이 모두 있을 때만 업데이트
            guard let sunrise = sunrise, let sunset = sunset else {
                print("⏳ WeatherManager 일출/일몰 데이터 대기 중...")
                return
            }

            print("🔄 WeatherManager 데이터 변경 감지 → SettingManager 자동 동기화 시작")

            // 🔧 SwiftUI State 변경 경고 방지: @Published 속성 업데이트를 다음 런루프로 연기
            DispatchQueue.main.async {
                // 일출/일몰 데이터 직접 업데이트
                self.todaySunrise = sunrise
                self.todaySunset = sunset
                self.tomorrowSunrise = tomorrowSunrise

                // 낮/밤 판단
                let now = Date()
                let previousIsDaytime = self.isDaytime
                self.isDaytime = (now >= sunrise && now < sunset)

                if previousIsDaytime != self.isDaytime {
                    print("🔄 낮/밤 상태 변경: \(previousIsDaytime ? "낮" : "밤") → \(self.isDaytime ? "낮" : "밤")")
                }

                // 남은 시간 업데이트
                self.updateRemainingTime()

                // 날씨 데이터 갱신 시 일출/일몰 알림도 갱신
                if let location = LocationManager.shared.currentLocation {
                    if self.isSunriseAlarmEnabled || self.isSunsetAlarmEnabled {
                        self.scheduleSunriseSunsetAlarms(for: location.coordinate)
                        print("🔔 날씨 데이터 갱신으로 인한 알림 재스케줄링 완료")
                    }
                }

                print("✅ WeatherManager → SettingManager 자동 동기화 완료")
                print("   - 오늘 일출: \(self.todaySunrise?.formatted(date: .omitted, time: .shortened) ?? "nil")")
                print("   - 오늘 일몰: \(self.todaySunset?.formatted(date: .omitted, time: .shortened) ?? "nil")")
                print("   - 내일 일출: \(self.tomorrowSunrise?.formatted(date: .omitted, time: .shortened) ?? "nil")")
                print("   - 낮/밤: \(self.isDaytime ? "낮" : "밤")")
            }
        }
        .store(in: &cancellables)
    }

    // MARK: - 일출/일몰 남은 시간 타이머

    /// 1분마다 남은 시간을 업데이트하는 타이머 설정 + 일출/일몰 정확한 시간 타이머
    private func setupTimeUpdateTimer() {
        // 1분(60초)마다 남은 시간 업데이트
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateRemainingTime()
            }
            .store(in: &cancellables)

        // 일출/일몰 타이머 예약 (내부에서 updateSunriseSunsetInfo() 호출하여 초기화 포함)
        scheduleNextSunEventTimer()

        print("✅ SettingManager: 타이머 설정 완료 (1분 + 일출/일몰)")
    }

    /// 다음 일출/일몰 시간에 정확히 실행되는 타이머 예약
    private func scheduleNextSunEventTimer() {
        // 기존 타이머 취소
        sunEventTimer?.cancel()
        sunEventTimer = nil

        // 현재 위치 정보로 일출/일몰 정보 및 isDaytime 상태 업데이트
        guard let location = LocationManager.shared.currentLocation else {
            print("⚠️ scheduleNextSunEventTimer: 위치 정보 없음. 타이머 예약 불가")
            return
        }

        // 일출/일몰 정보 및 isDaytime 상태를 항상 최신으로 업데이트
        updateSunriseSunsetInfo(for: location.coordinate)

        let now = Date()
        let nextEventTime: Date?

        // 다음 일출/일몰 이벤트 시간 결정
        if isDaytime {
            // 낮: 다음 이벤트는 오늘 일몰
            nextEventTime = todaySunset
        } else {
            // 밤: 다음 이벤트는 다음 일출 (오늘 일출이 미래면 오늘, 아니면 내일)
            if let todaySunrise = todaySunrise, todaySunrise > now {
                nextEventTime = todaySunrise
            } else {
                nextEventTime = tomorrowSunrise
            }
        }

        guard let eventTime = nextEventTime, eventTime > now else {
            print("⚠️ 다음 일출/일몰 이벤트 시간을 찾을 수 없음. 타이머 예약 실패")
            print("   - isDaytime: \(isDaytime)")
            print("   - todaySunrise: \(todaySunrise?.formatted(date: .omitted, time: .shortened) ?? "nil")")
            print("   - todaySunset: \(todaySunset?.formatted(date: .omitted, time: .shortened) ?? "nil")")
            print("   - tomorrowSunrise: \(tomorrowSunrise?.formatted(date: .omitted, time: .shortened) ?? "nil")")
            return
        }

        let timeInterval = eventTime.timeIntervalSince(now)

        // 정확한 시간에 실행
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleSunEventTransition()
        }
        sunEventTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeInterval, execute: workItem)

        print("✅ 다음 \(isDaytime ? "일몰" : "일출") 타이머 예약: \(eventTime.formatted(date: .omitted, time: .shortened))")
    }

    /// 일출/일몰 전환 시 실행
    private func handleSunEventTransition() {
        print("🌅 일출/일몰 전환 시간 도래!")

        // isDaytime 재계산 및 모든 일출/일몰 정보 업데이트
        if let location = LocationManager.shared.currentLocation {
            updateSunriseSunsetInfo(for: location.coordinate)

            // 일출/일몰 알림 자동 갱신 (다음 일출/일몰 알림 스케줄링)
            if isSunriseAlarmEnabled || isSunsetAlarmEnabled {
                scheduleSunriseSunsetAlarms(for: location.coordinate)
                print("🔔 일출/일몰 전환으로 인한 알림 자동 갱신 완료")
            }
        }

        // 남은 시간 즉시 업데이트
        updateRemainingTime()

        // 다음 일출/일몰 타이머 예약
        scheduleNextSunEventTimer()
    }

    /// 남은 시간만 업데이트 (1분 타이머용)
    private func updateRemainingTime() {
        let now = Date()
        let targetTime: Date?

        // 낮/밤에 따라 다음 이벤트 시간 결정
        if isDaytime {
            // 낮: 오늘 일몰까지
            targetTime = todaySunset
        } else {
            // 밤: 다음 일출까지 (오늘 일출이 아직 안 왔으면 오늘, 이미 지났으면 내일)
            if let todaySunrise = todaySunrise, todaySunrise > now {
                // 오늘 일출이 아직 미래면 오늘 일출 사용
                targetTime = todaySunrise
            } else {
                // 오늘 일출이 이미 지났으면 내일 일출 사용
                targetTime = tomorrowSunrise
            }
        }

        guard let target = targetTime, target > now else {
            timeUntilNextSunEvent = "--:--"
            print("⚠️ updateRemainingTime: 유효한 타겟 시간 없음 (isDaytime: \(isDaytime))")
            return
        }

        let interval = target.timeIntervalSince(now)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        timeUntilNextSunEvent = String(format: "%02d:%02d", hours, minutes)

        // 디버그 로그
        let targetName = isDaytime ? "오늘 일몰" : (todaySunrise ?? Date() > now ? "오늘 일출" : "내일 일출")
        print("⏰ 남은 시간 업데이트: \(targetName)까지 \(hours)시간 \(minutes)분")
    }

    // MARK: - 알림 권한 요청

    /// 앱이 처음 실행되었을 때, 푸시/로컬 알림 사용 권한을 요청하는 함수
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if granted {
                print("알림 권한이 허용되었습니다.")
            } else if let error = error {
                print("알림 권한 요청 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 종료일 알림 스케줄링

    /// 종료일이 가까운 도형(ShapeModel)들을 받아서, 알림을 예약하는 함수
    func scheduleEndDateAlarms(for shapes: [ShapeModel]) {
        guard isEndDateAlarmEnabled else { return }  // 기능이 꺼져있으면 아무것도 안 함

        // 기존 알림 삭제(중복 방지)
        removeEndDateAlarms()

        for shape in shapes {
            scheduleEndDateAlarm(for: shape)
        }
    }

    /// 개별 도형의 종료일 알림을 스케줄링
    func scheduleEndDateAlarm(for shape: ShapeModel) {
        guard isEndDateAlarmEnabled else { return }

        guard let endDate = shape.flightEndDate else { return }  // 종료일이 없으면 skip

        // 종료일 7일 전 알림
        guard let sevenDaysBefore = Calendar.current.date(byAdding: .day, value: -7, to: endDate) else { return }

        // 7일 전이 이미 지난 경우 알림 생성 안 함
        if sevenDaysBefore > Date() {
            scheduleNotification(
                id: "endDate_\(shape.id.uuidString)_7days", // 고유 식별자
                title: "도형 종료일 알림",
                body: "도형 '\(shape.title)'의 종료일이 7일 남았습니다.",
                date: sevenDaysBefore
            )
            print("✅ 알림 예약 완료: \(shape.title) - \(sevenDaysBefore)")
        } else {
            print("⏭️ 알림 생성 건너뜀 (7일 이하 남음): \(shape.title)")
        }
    }

    /// 개별 도형의 종료일 알림 삭제
    func removeEndDateAlarm(for shapeId: UUID) {
        let identifier = "endDate_\(shapeId.uuidString)_7days"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("🗑️ 알림 삭제: \(identifier)")
    }

    /// 종료일 알림 전체 삭제
    private func removeEndDateAlarms() {
        // 모든 pending 알림을 가져와서 "endDate_"로 시작하는 것들만 삭제
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let endDateIdentifiers = requests
                .filter { $0.identifier.hasPrefix("endDate_") }
                .map { $0.identifier }

            if !endDateIdentifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: endDateIdentifiers)
                print("🗑️ 종료일 알림 전체 삭제: \(endDateIdentifiers.count)개")
            }
        }
    }

    // MARK: - 일출/일몰 정보 업데이트

    /// 현재 위치의 위도/경도를 받아 일출/일몰 정보를 업데이트하는 함수
    /// WeatherKit에서 가져온 일출/일몰 데이터를 사용합니다
    ///
    /// **참고**: WeatherManager 데이터 변경 시 setupWeatherObserver()가 자동으로 동기화합니다.
    /// 이 함수는 수동 호출이 필요한 경우에만 사용됩니다.
    func updateSunriseSunsetInfo(for coordinate: CLLocationCoordinate2D) {
        let now = Date()

        print("🌅 ===== 일출/일몰 정보 업데이트 (WeatherKit) =====")
        print("   📍 좌표: \(coordinate.latitude), \(coordinate.longitude)")
        print("   🕐 현재 시간: \(now.formatted(date: .numeric, time: .standard))")

        // WeatherManager에서 일출/일몰 시간 직접 가져오기
        guard let weatherSunrise = WeatherManager.shared.sunriseTime,
              let weatherSunset = WeatherManager.shared.sunsetTime else {
            print("   ⚠️ WeatherManager에서 일출/일몰 데이터를 아직 가져오지 못했습니다.")
            print("🌅 ================================================")
            return
        }

        // 명확하게 분리: 오늘 데이터만 저장
        todaySunrise = weatherSunrise
        todaySunset = weatherSunset
        tomorrowSunrise = WeatherManager.shared.tomorrowSunriseTime

        print("   🌄 오늘 일출: \(todaySunrise?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        print("   🌇 오늘 일몰: \(todaySunset?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        print("   🌄 내일 일출: \(tomorrowSunrise?.formatted(date: .omitted, time: .shortened) ?? "nil")")

        // 낮/밤 판단 (명확한 로직)
        let previousIsDaytime = isDaytime
        isDaytime = (now >= weatherSunrise && now < weatherSunset)

        print("   🔍 낮/밤 판단:")
        print("      - now >= sunrise: \(now >= weatherSunrise)")
        print("      - now < sunset: \(now < weatherSunset)")
        print("      - isDaytime = \(isDaytime)")

        if previousIsDaytime != isDaytime {
            print("🔄 낮/밤 상태 변경: \(previousIsDaytime ? "낮" : "밤") → \(isDaytime ? "낮" : "밤")")
        }

        print("✅ SettingManager: 일출/일몰 정보 업데이트 완료")
        print("   - 최종 낮/밤: \(isDaytime ? "낮" : "밤")")
        print("🌅 ================================================")

        // 일출/일몰 시간이 업데이트되면 남은 시간도 즉시 업데이트
        updateRemainingTime()
    }

    // MARK: - 일출/일몰 알림 스케줄링

    /// 현재 위치의 위도/경도를 받아 일출/일몰 알림을 예약하는 함수
    /// WeatherKit에서 가져온 일출/일몰 데이터를 사용합니다
    func scheduleSunriseSunsetAlarms(for coordinate: CLLocationCoordinate2D) {
        // 일출/일몰 UI 정보도 함께 업데이트
        updateSunriseSunsetInfo(for: coordinate)
        let now = Date()

        // 일출 알림 처리
        if isSunriseAlarmEnabled {
            removeSunriseAlarms()

            // 오늘 일출이 미래면 오늘 일출 알림, 아니면 내일 일출 알림
            if let sunrise = todaySunrise, sunrise > now {
                registerSunriseAlarms(for: sunrise)
            } else if let tomorrow = tomorrowSunrise {
                registerSunriseAlarms(for: tomorrow)
            }
        }

        // 일몰 알림 처리
        if isSunsetAlarmEnabled {
            removeSunsetAlarms()

            // 오늘 일몰이 미래면 오늘 일몰 알림, 아니면 내일 일몰 알림
            if let sunset = todaySunset, sunset > now {
                registerSunsetAlarms(for: sunset)
            } else if let tomorrowSunset = WeatherManager.shared.tomorrowSunsetTime {
                registerSunsetAlarms(for: tomorrowSunset)
            }
        }
    }

    private func registerSunriseAlarms(for sunrise: Date) {
        guard isSunriseAlarmEnabled else { return }
        let thirtyMinBefore = Calendar.current.date(byAdding: .minute, value: -30, to: sunrise)!
        let tenMinBefore = Calendar.current.date(byAdding: .minute, value: -10, to: sunrise)!
        if thirtyMinBefore > Date() {
            scheduleNotification(id: "sunrise_30min", title: "일출 30분 전", body: "일출까지 30분 남았습니다.", date: thirtyMinBefore)
        }
        if tenMinBefore > Date() {
            scheduleNotification(id: "sunrise_10min", title: "일출 10분 전", body: "일출까지 10분 남았습니다.", date: tenMinBefore)
        }
    }

    private func registerSunsetAlarms(for sunset: Date) {
        guard isSunsetAlarmEnabled else { return }
        let thirtyMinBefore = Calendar.current.date(byAdding: .minute, value: -30, to: sunset)!
        let tenMinBefore = Calendar.current.date(byAdding: .minute, value: -10, to: sunset)!
        if thirtyMinBefore > Date() {
            scheduleNotification(id: "sunset_30min", title: "일몰 30분 전", body: "일몰까지 30분 남았습니다.", date: thirtyMinBefore)
        }
        if tenMinBefore > Date() {
            scheduleNotification(id: "sunset_10min", title: "일몰 10분 전", body: "일몰까지 10분 남았습니다.", date: tenMinBefore)
        }
    }

    /// 일출 알림 삭제
    private func removeSunriseAlarms() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let sunriseIdentifiers = requests
                .filter { $0.identifier.hasPrefix("sunrise_") }
                .map { $0.identifier }

            if !sunriseIdentifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: sunriseIdentifiers)
                print("🗑️ 일출 알림 삭제: \(sunriseIdentifiers.count)개")
            }
        }
    }

    /// 일몰 알림 삭제
    private func removeSunsetAlarms() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let sunsetIdentifiers = requests
                .filter { $0.identifier.hasPrefix("sunset_") }
                .map { $0.identifier }

            if !sunsetIdentifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: sunsetIdentifiers)
                print("🗑️ 일몰 알림 삭제: \(sunsetIdentifiers.count)개")
            }
        }
    }
    
    // MARK: - 종료일 지난 도형 일괄 삭제

    /// 앱의 ShapeRepository를 호출하여, 종료일이 지난 도형을 일괄 삭제
    func deleteExpiredShapes() {
        Task {
            do {
                try await ShapeRepository.shared.deleteExpiredShapes()
            } catch {
                print("❌ 만료된 도형 삭제 실패: \(error)")
            }
        }
    }
    
    // MARK: - 알림 예약을 위한 공통 함수

    /// 실질적으로 알림을 예약하는 함수(모든 알림 공통)
    private func scheduleNotification(id: String, title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title              // 알림 제목
        content.body = body                // 알림 본문 메시지
        content.sound = .default           // 기본 알림음

        // 알림이 울릴 시각을 년/월/일/시/분 단위로 분리해서 trigger 생성
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // 알림 요청 객체를 생성해서 시스템에 등록
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("알림 스케줄링 실패: \(error.localizedDescription)")
            }
        }
    }
}
