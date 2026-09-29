import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ble/ble_service.dart';
import '../../core/location/location_service.dart';
import '../../core/routing/route_models.dart';
import '../../core/routing/tmap_route_client.dart';
import '../navigation/command_engine.dart';
import '../navigation/navigation_command.dart';
import '../navigation/off_route_detector.dart';

/// 01장 "공통 이동상태"의 Phase 1 서브셋. Driver 관련 상태(Vehicle Approaching 등)는
/// Phase 4에서 추가된다.
enum TripPhase { idle, routing, navigating, rerouting, arrived }

/// Haptic Navigation Loop 전체를 오케스트레이션(지휘)하는 클래스:
/// GPS 위치 → 경로 → Navigation Command → BLE 전송. (FE-1~FE-8)
///
/// [이 파일이 앱에서 하는 역할]
/// 지금까지 본 다른 클래스들(LocationService, RouteClient, CommandEngine,
/// GloveBleService)은 전부 "한 가지 일만 잘하는" 부품이다. TripSession은
/// 그 부품들을 순서대로 연결해서 실제 사용자 경험(목적지 입력→경로 계산→
/// 걷는 동안 계속 명령을 계산해서 장갑에 보내기)을 만들어내는 지휘자
/// 역할이다. 화면(Screen)들은 이 클래스의 상태를 구독하기만 하고, 실제
/// 로직은 전혀 몰라도 된다.
///
/// [공부 포인트 — ChangeNotifier]
/// `ChangeNotifier`는 Flutter의 상태 관리 기본 도구 중 하나다. 이 클래스를
/// extends하면 `notifyListeners()`라는 메서드를 쓸 수 있는데, 이걸 호출하면
/// "이 객체를 구독 중인 모든 위젯, 다시 그려줘(rebuild)"라는 신호가 나간다.
/// main.dart에서 `ChangeNotifierProvider`로 등록해두면, 화면 쪽에서는
/// `context.watch<TripSession>()`로 구독하거나 `context.read<TripSession>()`
/// 로 한 번만 읽어올 수 있다 (watch는 값이 바뀌면 자동으로 다시 그려지고,
/// read는 그냥 지금 값만 가져오고 구독은 안 한다 — 버튼 클릭 핸들러처럼
/// "지금 이 순간의 값"만 필요할 때 read를 쓴다).
class TripSession extends ChangeNotifier {
  TripSession({
    required this.routeClient,
    required this.locationService,
    required this.bleService,
    this.offRouteDetector = const OffRouteDetector(),
  });

  final RouteClient routeClient;
  final LocationService locationService;
  final GloveBleService bleService;
  final OffRouteDetector offRouteDetector;

  // 아래 필드들은 전부 "private 변수 + public getter" 쌍으로 되어있다.
  // 외부에서는 읽기만 가능하고(getter), 값을 바꾸는 건 이 클래스 내부
  // 로직을 통해서만 가능하게 만든 캡슐화(encapsulation) 패턴이다 — 화면이
  // 실수로 `session.phase = ...` 처럼 상태를 직접 조작해버리는 걸 막는다.

  TripPhase _phase = TripPhase.idle;
  TripPhase get phase => _phase;

  WalkingRoute? _route;
  WalkingRoute? get route => _route;

  GeoPoint? _currentLocation;
  GeoPoint? get currentLocation => _currentLocation;

  NavigationCommand? _currentCommand;
  NavigationCommand? get currentCommand => _currentCommand;

  Object? _lastError;
  Object? get lastError => _lastError;

  CommandEngine? _commandEngine;
  StreamSubscription<GeoPoint>? _locationSub;
  GeoPoint? _destination;

  /// 미리보기 경로의 출발점(탭 당시 GPS)과 실제 출발 시점 GPS가 이 값(m) 이상 벌어지면
  /// 캐시된 경로를 신뢰하지 않고 다시 받아온다. OffRouteDetector 임계값(25m)보다 살짝 크게
  /// 잡아, 어차피 이탈로 오판될 정도의 오차라면 그 전에 걸러낸다.
  static const _previewStaleDistanceM = 30.0;

  /// 출발 절차 전체를 시작한다: 권한 확인 → 현재 위치 확보 → 경로 확보 →
  /// GPS 스트림 구독 시작. HomeScreen의 "출발" 버튼이 이 메서드를 호출한다.
  ///
  /// [previewRoute]를 넘기면 TMAP을 다시 호출하지 않고 그대로 사용한다 — 단, 미리보기 당시
  /// GPS와 실제 출발 시점 GPS가 너무 다르면(실내 GPS 오차 등으로 한 발짝도 안 걸었는데
  /// "경로 이탈"로 오판되는 걸 막기 위해) 그때는 새로 받아온다.
  ///
  /// [fallbackOrigin]은 "출발" 시점에 GPS 단발 조회가 실패했을 때(예: kCLErrorLocationUnknown)
  /// 대신 쓸 최근 위치다. LocationService 자체적으로도 마지막 위치로 폴백을 시도하지만,
  /// 웹 환경에서는 플랫폼 캐시가 없어 그마저도 실패할 수 있어 — 온보딩 화면이 이미 확보해둔
  /// 위치를 앱 레벨에서 한 번 더 보험으로 넘겨받는다.
  ///
  /// [공부 포인트 — try/catch/rethrow] 이 메서드는 실패하면 화면에 에러를
  /// 보여줘야 하는데(HomeScreen이 catch해서 _tripError로 표시), 동시에
  /// 여기서도 `_phase`를 idle로 되돌리고 `_lastError`를 기록해야 한다.
  /// 그래서 catch 블록에서 우리 쪽 정리(cleanup)를 한 다음 `rethrow`로
  /// 같은 예외를 그대로 다시 던져서, 호출한 쪽도 알 수 있게 한다.
  Future<void> startTrip(
    GeoPoint destination, {
    WalkingRoute? previewRoute,
    GeoPoint? fallbackOrigin,
  }) async {
    _destination = destination;
    _lastError = null;
    _phase = TripPhase.routing;
    notifyListeners(); // "경로 계산 중" 상태로 화면을 즉시 갱신

    try {
      final hasPermission = await locationService.ensurePermission();
      if (!hasPermission) {
        throw StateError('위치 권한이 필요합니다.');
      }

      // GPS 단발 조회 실패 시 fallbackOrigin으로 대체하는 마지막 방어선.
      // `late final`은 "이 시점엔 아직 값이 없지만, try/catch 중 어느
      // 한쪽에서든 딱 한 번만 값이 대입될 것을 보장한다"는 선언이다 —
      // 일반 final처럼 재대입은 막으면서도, 대입 시점을 조건문 뒤로 미룰 수 있다.
      late final GeoPoint origin;
      try {
        origin = await locationService.getCurrentLocation();
      } catch (e) {
        if (fallbackOrigin == null) rethrow;
        origin = fallbackOrigin;
      }
      _currentLocation = origin;

      // previewRoute가 있어도, 그 경로의 출발점과 지금 위치가 너무 다르면
      // (시간이 꽤 지났거나 GPS가 튄 경우) 낡은 캐시를 믿지 않고 새로 받는다.
      final canReusePreview = previewRoute != null &&
          origin.distanceTo(previewRoute.points.first) <= _previewStaleDistanceM;
      final route = canReusePreview
          ? previewRoute
          : await routeClient.fetchWalkingRoute(origin: origin, destination: destination);
      _route = route;
      _commandEngine = CommandEngine(route);

      _phase = TripPhase.navigating;
      notifyListeners();

      // 이전에 구독 중이던 스트림이 있으면 먼저 정리하고 새로 구독한다
      // (reroute()로 재시작하는 경우를 대비).
      await _locationSub?.cancel();
      _locationSub = locationService.watchLocation().listen(
        _onLocationUpdate,
        onError: (Object e) {
          // GPS 신호 일시 유실(예: kCLErrorLocationUnknown)은 다음 유효한 위치 업데이트가
          // 오면 자연히 복구된다 — 스트림을 끊지 않고 이번 업데이트만 무시한다.
          debugPrint('위치 스트림 에러(무시하고 계속 수신): $e');
        },
      );
    } catch (e) {
      _lastError = e;
      _phase = TripPhase.idle;
      notifyListeners();
      rethrow;
    }
  }

  /// GPS 위치가 갱신될 때마다(watchLocation 스트림) 호출되는 콜백.
  /// 이 함수가 사실상 "걷는 동안 반복되는 심장 박동"이다: 위치 → 이탈
  /// 여부 확인 → (정상이면) 다음 명령 계산 → 바뀌었으면 장갑에 전송.
  Future<void> _onLocationUpdate(GeoPoint point) async {
    _currentLocation = point;
    final route = _route;
    final engine = _commandEngine;
    if (route == null || engine == null) return; // 아직 경로가 없으면 할 일이 없음

    final NavigationCommand command;
    if (offRouteDetector.isOffRoute(point, route)) {
      // 경로 이탈이 CommandEngine의 정상 판단보다 항상 우선한다.
      command = NavigationCommand.offRoute;
      _phase = TripPhase.rerouting;
    } else {
      command = engine.evaluate(point);
      _phase = command == NavigationCommand.arrived
          ? TripPhase.arrived
          : TripPhase.navigating;
    }

    // [공부 포인트] 명령이 "바뀌었을 때만" 화면 갱신과 BLE 전송을 한다.
    // GPS 스트림은 5m마다 계속 이벤트를 내는데, 그때마다 똑같은 "직진"을
    // 반복 전송하면 BLE 대역폭과 장갑 배터리를 낭비한다. 이전 명령과 다를
    // 때만 실제로 무언가를 하는 것이 효율적이다.
    if (command != _currentCommand) {
      _currentCommand = command;
      notifyListeners();

      if (bleService.isConnected) {
        try {
          await bleService.sendCommand(command);
        } catch (e) {
          // 장갑 전송 실패는 명령 자체를 되돌리지 않는다 — 다음 위치 업데이트에서
          // 명령이 바뀌면 자연히 재전송되고, 연결이 끊긴 경우는 UI가 연결상태로 알려준다.
          debugPrint('BLE 명령 전송 실패: $e');
        }
      }
    }

    if (command == NavigationCommand.arrived) {
      await _locationSub?.cancel(); // 도착했으니 더 이상 위치를 추적할 필요 없음
    }
  }

  /// 경로 이탈 시 사용자가 명시적으로 재탐색을 요청한다. (FE-7)
  /// v0.1은 전체 경로를 현재 위치 기준으로 다시 계산하는 단순한 방식이다
  /// (전체 재탐색이라 previewRoute/fallbackOrigin을 안 넘겨서 항상 TMAP을
  /// 새로 호출한다 — 이탈 상황 자체가 이미 "경로가 안 맞다"는 뜻이므로
  /// 캐시를 재사용할 이유가 없다).
  Future<void> reroute() async {
    final destination = _destination;
    if (destination == null) return;
    await _locationSub?.cancel();
    await startTrip(destination);
  }

  /// 사용자가 "안내 종료"를 누르거나 도착했을 때 모든 상태를 초기 상태로 되돌린다.
  void endTrip() {
    _locationSub?.cancel();
    _phase = TripPhase.idle;
    _route = null;
    _commandEngine = null;
    _currentCommand = null;
    _destination = null;
    notifyListeners();
  }

  /// ChangeNotifier가 요구하는 정리(cleanup) 메서드. 이 객체(Provider)가
  /// 앱 트리에서 제거될 때 자동 호출된다 — 살아있는 스트림 구독을 여기서
  /// 반드시 취소해야 메모리 누수와 "화면이 닫혔는데 콜백이 계속 도는" 버그를 막는다.
  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }
}
