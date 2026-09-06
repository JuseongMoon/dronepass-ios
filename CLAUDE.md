# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요
DronePass는 드론 비행 허가지 시각화 및 지도 메모 iOS 어플리케이션입니다. Swift + SwiftUI로 개발되었으며, 네이버 지도와 Firebase를 핵심 기술로 사용합니다.

## 중요한 설정 파일
- `Info.plist`: 네이버 지도 클라이언트 ID, 권한 설정
- `GoogleService-Info.plist`: Firebase 설정
- `DronePass.entitlements`: 앱 권한 설정 (Push Notifications 포함)
- `.cursor/rules/dronepassrules.mdc`: iOS 개발 가이드라인

## 개발 시 주의사항
- 모든 UI는 SwiftUI로 개발 (UIKit은 특별한 경우만)
- Firebase 규칙에 따라 데이터 접근 권한 확인
- 네이버 지도 API 사용량 고려
- VWorld API 호출 제한 및 인증키 관리
- 실시간 동기화 시 충돌 해결 로직 확인
- iOS 17.6+ 타겟팅 (최신 SwiftUI 기능 활용 가능)
- 푸시 알림 테스트 시 실제 디바이스 필요

## 관리자 페이지 (Admin Web)
관리자 페이지는 별도의 React 웹 프로젝트입니다. 빌드·배포 절차는 `admin-deploy` 스킬 참조.
