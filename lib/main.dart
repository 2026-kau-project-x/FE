import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/ble/ble_service.dart';
import 'core/geocoding/reverse_geocoding_client.dart';
import 'core/location/location_service.dart';
import 'core/routing/tmap_route_client.dart';
import 'domain/session/trip_state.dart';
import 'presentation/home/home_screen.dart';

/// 앱의 진입점(entry point) 파일. Flutter 앱은 항상 `main()` 함수부터 실행된다.
///
/// [이 파일이 하는 일 — 의존성 주입(Dependency Injection)의 "조립 지점"]
/// core 폴더의 각 서비스(LocationService, GloveBleService, RouteClient,
/// ReverseGeocodingClient)를 여기서 "딱 한 번씩" 생성하고, Provider를 통해
/// 화면 트리 전체에서 꺼내 쓸 수 있게 등록한다. 이렇게 생성을 한 곳에
/// 모아두면(다른 화면 코드에서 `LocationService()`를 아무 데서나 새로 만들지
/// 않으면) 앱 전체가 항상 "같은" 서비스 인스턴스를 공유하게 되고, 테스트할
/// 때도 이 조립 부분만 가짜(Mock)로 바꿔치기하면 된다 (test/widget_test.dart
/// 참고).

/// 빌드/실행 시 `--dart-define=TMAP_APP_KEY=xxx`로 주입.
/// 비어있으면 Mock 클라이언트들로 동작 — TMAP 키 없이도 Command Engine·BLE
/// 파이프라인 전체를 검증할 수 있다.
///
/// [공부 포인트] `String.fromEnvironment`는 런타임이 아니라 "빌드 시점"에
/// 값이 결정되는 특수한 상수다. 그래서 API 키처럼 소스코드에 직접 적으면
/// 안 되는 값을 커밋하지 않고도 빌드 커맨드(`--dart-define`)로 주입할 수
/// 있다 — 이 프로젝트에서는 `env.json` 파일(gitignore 처리됨)에 키를 넣고
/// `--dart-define-from-file=env.json` 옵션으로 넘긴다.
const _tmapAppKey = String.fromEnvironment('TMAP_APP_KEY');

void main() {
  final locationService = LocationService();
  final bleService = GloveBleService();
  // 키가 있으면 진짜 TMAP 클라이언트를, 없으면 Mock을 쓴다 — 두 클래스 모두
  // 같은 RouteClient 인터페이스를 구현하므로 이 한 줄만 갈아끼우면 된다.
  final routeClient = _tmapAppKey.isEmpty
      ? MockRouteClient()
      : TmapRouteClient(appKey: _tmapAppKey);
  final geocodingClient = _tmapAppKey.isEmpty
      ? MockReverseGeocodingClient()
      : TmapReverseGeocodingClient(appKey: _tmapAppKey);

  runApp(MyApp(
    locationService: locationService,
    bleService: bleService,
    routeClient: routeClient,
    geocodingClient: geocodingClient,
  ));
}

/// 앱의 최상위 위젯. 여기서 Provider들을 등록해서 그 아래 모든 화면이
/// `context.watch<T>()` / `context.read<T>()`로 서비스에 접근할 수 있게 한다.
class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.locationService,
    required this.bleService,
    required this.routeClient,
    required this.geocodingClient,
  });

  final LocationService locationService;
  final GloveBleService bleService;
  final RouteClient routeClient;
  final ReverseGeocodingClient geocodingClient;

  @override
  Widget build(BuildContext context) {
    // [공부 포인트 — MultiProvider]
    // `provider` 패키지는 Flutter의 대표적인 상태 관리 라이브러리다.
    // `Provider<T>.value`는 "이미 만들어둔 객체를 그냥 트리에 등록만"
    // 하는 것이고(생성은 이미 main()에서 끝났으므로), `ChangeNotifierProvider`는
    // "이 안에서 새로 만들고, 그 객체가 notifyListeners()를 부를 때마다
    // 구독자들을 다시 그려주는" 특별한 버전이다. TripSession만 상태가
    // 시시각각 바뀌면서 화면을 다시 그려야 하는 대상이라 ChangeNotifierProvider를 쓴다.
    return MultiProvider(
      providers: [
        Provider<LocationService>.value(value: locationService),
        Provider<GloveBleService>.value(value: bleService),
        Provider<RouteClient>.value(value: routeClient),
        Provider<ReverseGeocodingClient>.value(value: geocodingClient),
        ChangeNotifierProvider<TripSession>(
          create: (_) => TripSession(
            routeClient: routeClient,
            locationService: locationService,
            bleService: bleService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Assistive Mobility',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const HomeScreen(), // 앱이 시작하면 보여줄 첫 화면
      ),
    );
  }
}
