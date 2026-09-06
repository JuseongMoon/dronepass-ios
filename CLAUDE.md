# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요
DronePass는 드론 비행 허가지 시각화 및 지도 메모 iOS 어플리케이션입니다. Swift + SwiftUI로 개발되었으며, 네이버 지도와 Firebase를 핵심 기술로 사용합니다.

## 중요한 설정 파일
- `Info.plist`: 권한 설정과 API 키 **자리표시자**.
  네이버·VWorld 키는 `$(NAVER_MAP_API_KEY)` `$(NAVER_MAP_API_KEY_SECRET)` `$(VWORLD_API_KEY)`
  형태로 적혀 있고, 빌드 시 빌드 설정이 실제 값으로 치환합니다.
  **이 파일에 키 값을 직접 쓰지 않습니다.** 자리표시자를 실제 값으로 바꾸는 편집은 금지입니다.
- `DronePass/Config/Secrets.xcconfig`: 위 키의 실제 값. `.gitignore`에 등록되어 커밋되지 않습니다.
  `Secrets.xcconfig.example`을 복사해 로컬에서 채웁니다. 키 값을 저장소 어디에도 남기지 않습니다.
- `GoogleService-Info.plist`: Firebase 클라이언트 설정.
  저장소에 포함되어 있으며, 이 파일은 **클라이언트 식별자**(앱 ID·프로젝트 ID·API 키)일 뿐
  비밀값이 아닙니다. 실제 접근 통제는 서버 쪽 Firestore·Storage 보안 규칙이 담당합니다.
  반대로 **Firebase 서비스 계정 키(admin SDK JSON)는 절대 저장소에 두지 않습니다** —
  그것은 보안 규칙을 우회하는 진짜 시크릿입니다.
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

## 공개 저장소 규칙

이 저장소는 공개되어 있다. 커밋한 것은 되돌려도 남는다.

- **시크릿 금지** — API 키·토큰·서명 키(`*.jks`/`*.p12`)·서비스 계정 키·실제 사용자 데이터를 커밋하지 않는다.
  값은 **`DronePass/Config/Secrets.xcconfig`** 에만 두고 저장소에는 `*.example`만 올린다.
  소스·plist·manifest·주석·커밋 메시지 어디에도 값을 쓰지 않는다.
  이미 올렸다면 되돌리는 것으로 끝내지 말고 **키를 폐기·재발급**한다.
  **예외** — Firebase 클라이언트 설정(`GoogleService-Info.plist`, `google-services.json`, `AIzaSy…`)과
  OAuth public client ID는 Google이 앱 바이너리 내장을 전제로 문서화한 **식별자**이며 비밀이 아니다.
  커밋해도 되고 재발급 대상이 아니다. 접근 통제는 Firestore 보안 규칙과 API 키의 `apiTargets`·앱 제한이 담당한다.
  **단 서비스 계정 키·Admin SDK 자격증명·서명 키는 이 예외에 해당하지 않는다.**
- **내부 정보 금지** — 로컬 절대경로(`/Users/…`), 저장소 밖 파일 참조, 관리자 URL,
  인프라 식별자(버킷·배포 ID·계정 번호), 개인 기기 식별자(UDID·시리얼),
  릴리스 진행 상태와 스토어 콘솔 절차는 문서에 남기지 않는다.
- **내부 문서 위치** — 가격 전략·미출시 기획·운영 절차·서버 계약은 저장소에 두지 않는다.
  로컬에 두고 gitignore 하되 **그 판단 근거를 이 문서에 적어** 다음 세션이 되돌리지 않게 한다.
  gitignore된 경로를 코드 주석이나 문서에서 참조하지 않는다 — 방문자에게는 끊어진 링크다.
- **문서 정확성** — 여기 적힌 버전·경로·명령·구조가 코드와 다르면 코드가 아니라 문서를 고친다.
  배포 타깃과 언어 버전은 프로젝트 기본값이 아니라 **앱 타깃의 실제 값**을 확인해 적는다.
- **브랜치** — 에이전트 작업 브랜치는 머지 후 지운다. 원격에 실험 브랜치를 남기지 않는다.
  **처음 push 하는 순간 그 브랜치의 문서·메모도 함께 공개된다.**
- **`main`에 force-push 하지 않는다.** 공개된 히스토리를 다시 쓰면 클론·포크한 쪽이 깨진다.
  (예외: 시크릿 제거 — 이때도 키 폐기가 먼저다.)
- **push 전 확인** — `git fetch origin && git status -sb`로 원격이 앞섰는지 보고, 앞섰으면 덮지 말고 rebase 한다.
  `git log origin/main..HEAD --stat`으로 올라갈 파일 전체를 확인해 무관한 파일을 분리하고,
  `git diff`에서 키·절대경로·기기 식별자가 없는지 본다. **`git add .` 금지.**
