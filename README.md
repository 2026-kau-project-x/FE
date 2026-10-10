# FE (Flutter 앱)

Project X 사용자 앱. GPS + 목적지 → TMAP 보행자 경로 → 7종 Navigation Command → BLE → 장갑 진동.
설정하면 이동 상태를 BE 에 보고한다 (선택, 꺼도 안내는 그대로 동작).

## 실행
```bash
cp env.json.example env.json        # Windows: copy env.json.example env.json
flutter pub get
flutter run -d chrome --dart-define-from-file=env.json
flutter analyze
flutter test
```

### env.json (gitignore, 커밋 금지)
| 키 | 설명 | 비우면 |
|---|---|---|
| `TMAP_APP_KEY` | TMAP 앱키 | Mock 경로·주소로 동작 |
| `BE_BASE_URL` | BE 주소 (예: `http://localhost:8000`) | BE 보고 끔 (앱 단독) |
| `BE_API_KEY` | BE `.env` 의 `API_KEY` 와 같은 값 (`X-API-Key` 헤더) | 헤더 안 보냄 (BE 인증 꺼진 상태용) |

`BE_BASE_URL` 은 실행 환경마다 다르다:
- 웹(Chrome)·Windows: `http://localhost:8000`
- Android 에뮬레이터: `http://10.0.2.2:8000` (에뮬레이터 안의 localhost 는 에뮬레이터 자신)
- 실기기: 같은 Wi-Fi 의 PC IP (예: `http://192.168.0.10:8000`) — 디버그 빌드만 평문 HTTP 허용

## 플랫폼
- Windows 에서는 **웹(Chrome)·Android** 로 개발·테스트. BLE 는 Android 실기기에서만 확인 가능 (웹 미지원).
- iOS 빌드는 Mac(Xcode) 필요 — 현재 보류.

## 구조 (`lib/`)
```
main.dart                       DI 조립. env 값 유무로 실제/Mock 클라이언트 선택
core/
  ble/                          장갑 BLE (프로토콜 UUID·명령 바이트, 스캔→연결→Write→ACK)
  location/                     GPS (권한, lastKnown 폴백, 5 m 스트림)
  routing/                      TMAP 보행자 경로 + Mock, GeoPoint/TurnPoint/WalkingRoute
  geocoding/                    좌표 → 도로명주소 (TMAP A10)
  backend/trip_api_client.dart  BE /api/v1/trips 호출 (생성·상태 전이)
domain/
  navigation/                   CommandEngine(도착·룩어헤드 15 m), 7종 명령, 경로이탈(25 m)
                                 이탈은 연속 2회 판정 시 확정 (GPS 튐 오탐 방지, TripSession.offRouteConfirmCount)
  session/trip_state.dart       TripSession: 위치→명령→BLE 를 지휘하는 상태머신
  session/backend_trip_sync.dart 앱 상태 → BE 상태 보고 (순서 보장, 실패해도 안내 계속)
presentation/                   home(지도 탭→경로 미리보기→출발), navigating, widgets
```

### 앱 상태 → BE 상태
| 앱 (TripPhase) | BE (TripStatus) |
|---|---|
| 출발 (navigating 진입) | 이동 생성 → `WALKING` |
| 경로 이탈 (rerouting) | `WAITING` |
| 재탐색 후 복귀 | `WALKING` (같은 이동 유지) |
| 도착 (arrived) | `RENDEZVOUS` |
| 안내 종료 | 도착 후 `COMPLETED` / 도중 `CANCELLED` |

## 검증 도구 (`tool/`, env.json 을 직접 읽음)
```bash
dart run tool/verify_tmap_route.dart            # TMAP 경로 실제 응답 확인 (키 필요)
dart run tool/verify_tmap_reverse_geocode.dart  # TMAP 역지오코딩 (키 필요)
dart run tool/verify_be_trip_flow.dart          # 실제 BE 와 상태 전이 계약 확인 (BE 서버 필요)
```

## BLE 계약 (웨어러블 팀과 합의된 가정)
- 기기명 프리픽스 `GLOVE_` (실제 기기명 확인 필요)
- Service `0000ff00-…`, NAV_COMMAND `0000ff01-…`(Write 1 byte), LINK_STATUS `0000ff02-…`(Notify, ACK echo)
- 명령: `01` 직진 · `02` 좌 · `03` 사선좌 · `04` 우 · `05` 사선우 · `06` 도착 · `07` 경로이탈
