# DronePass 데이터 계약 — shapes (v1, 2026-08-29)

**진실 원천**: iOS `DronePass/Firebase/ShapeFirebaseStore.swift` (`shapeToFirestoreData` / `parseShapeFromDocument`).
이 문서는 그 코드에서 도출되며, 일치 여부는 `DronePassTests/CrossPlatformFirestoreContractTests.swift`가 `team/fixtures/*.json`을 읽어 자동 검증한다. 변경 절차: iOS가 코드·본 문서·fixture를 갱신 → Android·Web이 자기 테스트를 fixture에 맞춤.

## 문서 경로
`users/{uid}/shapes/{문서ID}` — 문서ID = **대문자 UUID** (`shape.id.uuidString`). 같은 계정(Google/Apple, Firebase Auth) = 같은 `uid` = 같은 데이터 트리. 쓰기는 `setData(merge: true)`.

**서비스 현황(2026-08-30)**: 두 앱 모두 현재 **원(circle)만 생성·서비스**한다. 나머지 3종(rectangle/polygon/polyline)은 과거·미래 데이터 보호를 위해 계약·fixture·파서에 **읽기 호환으로 유지**한다.

## 타입 규약
| 항목 | 규약 |
|---|---|
| 날짜 | 전 필드 Firestore `Timestamp` |
| 좌표 | nested map `{latitude: Double, longitude: Double}` — 쓰기 시 **소수 6자리 반올림** (`(x*1e6).rounded()/1e6`). **GeoPoint 금지**(읽기 시 거부됨) |
| shapeType | 소문자 문자열 `circle` \| `rectangle` \| `polygon` \| `polyline` — 읽기는 `lowercased()` 관용, **미상 값은 해당 문서 skip**(circle로 강제 금지) |
| 숫자 | 읽기는 정수/실수 표현 모두 허용(SDK NSNumber 브리징). 쓰기 시 정수 필드를 Double로 확장하지 말 것 |

## 필드
**필수(쓰기 시 항상 존재)** — id(String, 대문자 UUID·문서ID와 동일) · title(String) · shapeType(String) · baseCoordinate(map) · memo(String, nil→`""`) · address(String, nil→`""`) · createdAt(Timestamp) · flightStartDate(Timestamp) · color(String, `#RRGGBB`) · updatedAt(Timestamp)

**선택(값이 있을 때만 키 존재 — nil이면 키 자체를 쓰지 않음)** — flightEndDate(Timestamp) · deletedAt(Timestamp) · droneId(String) · radius(Double, circle) · secondCoordinate(map, rectangle) · polygonCoordinates(map 배열, polygon) · polylineCoordinates(map 배열, polyline) · height(Double)

## 삭제·충돌
- **소프트삭제**: `deletedAt` tombstone + `updatedAt` 갱신. 물리 삭제 없음.
- **활성 도형은 `deletedAt` 키가 아예 없음**(Android·구 iOS). null 값 쿼리로 활성을 거르면 안 됨 — 전체 로드 후 메모리 필터.
- **충돌 해결**: LWW = `updatedAt`.

## 읽기 관용 규칙 (파서가 실제 허용하는 것)
- 파싱 필수 guard: `id`(UUID 파싱 가능) · `title` · `shapeType`(유효값) · `baseCoordinate`(lat/lng Double) · `color` · 시작일(`flightStartDate` 또는 `startedAt`). 실패 시 해당 문서 skip.
- 레거시 폴백: `flightStartDate`←`startedAt`, `flightEndDate`←`expireDate`, `createdAt` 부재→`flightStartDate` 값 사용(+백그라운드 마이그레이션 기록), `updatedAt` 부재→`createdAt` 값 사용.
- `memo`/`address` 부재 허용(읽기 시 nil).
- rectangle의 `secondCoordinate`, polygon/polyline의 좌표 배열이 부재/불량이어도 문서는 파싱됨(해당 값만 nil/누락).

## fixture 규약 (`team/fixtures/*.json`)
파일 1개 = Firestore 문서 1개: `{"documentId": "<대문자 UUID>", "fields": {...}}`.
`Timestamp`는 JSON으로 직렬화할 수 없으므로 `{"_seconds": <Int>, "_nanoseconds": <Int>}` 객체로 표기한다(Firestore Admin SDK 직렬화 관례 — Web Node 툴킷 호환). 테스트 로더가 이 객체를 `Timestamp`로 치환한 뒤 파서에 투입한다. 그 외 값은 JSON 그대로가 곧 문서 값이다.

| 파일 | 검증 대상 |
|---|---|
| shape-circle / rectangle / polygon / polyline.json | 도형 4종 정본 형태(필수+타입별 선택 필드) |
| shape-soft-deleted.json | deletedAt tombstone |
| shape-android-active.json | Android 작성 형태: deletedAt 키 부재 + 정수형 radius/height |
| shape-legacy.json | 구 iOS 데이터: startedAt/expireDate, createdAt·updatedAt·memo·address 부재 |
