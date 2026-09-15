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

/// Haptic Navigation Loop 전체를 오케스트레이션한다:
/// GPS 위치 → 경로 → Navigation Command → BLE 전송. (FE-1~FE-8)
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

  /// [previewRoute]를 넘기면 TMAP을 다시 호출하지 않고 그대로 사용한다 — 단, 미리보기 당시
  /// GPS와 실제 출발 시점 GPS가 너무 다르면(실내 GPS 오차 등으로 한 발짝도 안 걸었는데
  /// "경로 이탈"로 오판되는 걸 막기 위해) 그때는 새로 받아온다.
  ///
  /// [fallbackOrigin]은 "출발" 시점에 GPS 단발 조회가 실패했을 때(예: kCLErrorLocationUnknown)
  /// 대신 쓸 최근 위치다. LocationService 자체적으로도 마지막 위치로 폴백을 시도하지만,
  /// 웹 환경에서는 플랫폼 캐시가 없어 그마저도 실패할 수 있어 — 온보딩 화면이 이미 확보해둔
  /// 위치를 앱 레벨에서 한 번 더 보험으로 넘겨받는다.
  Future<void> startTrip(
    GeoPoint destination, {
    WalkingRoute? previewRoute,
    GeoPoint? fallbackOrigin,
  }) async {
    _destination = destination;
    _lastError = null;
    _phase = TripPhase.routing;
    notifyListeners();

    try {
      final hasPermission = await locationService.ensurePermission();
      if (!hasPermission) {
        throw StateError('위치 권한이 필요합니다.');
      }

      late final GeoPoint origin;
      try {
        origin = await locationService.getCurrentLocation();
      } catch (e) {
        if (fallbackOrigin == null) rethrow;
        origin = fallbackOrigin;
      }
      _currentLocation = origin;

      final canReusePreview = previewRoute != null &&
          origin.distanceTo(previewRoute.points.first) <= _previewStaleDistanceM;
      final route = canReusePreview
          ? previewRoute
          : await routeClient.fetchWalkingRoute(origin: origin, destination: destination);
      _route = route;
      _commandEngine = CommandEngine(route);

      _phase = TripPhase.navigating;
      notifyListeners();

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

  Future<void> _onLocationUpdate(GeoPoint point) async {
    _currentLocation = point;
    final route = _route;
    final engine = _commandEngine;
    if (route == null || engine == null) return;

    final NavigationCommand command;
    if (offRouteDetector.isOffRoute(point, route)) {
      command = NavigationCommand.offRoute;
      _phase = TripPhase.rerouting;
    } else {
      command = engine.evaluate(point);
      _phase = command == NavigationCommand.arrived
          ? TripPhase.arrived
          : TripPhase.navigating;
    }

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
      await _locationSub?.cancel();
    }
  }

  /// 경로 이탈 시 사용자가 명시적으로 재탐색을 요청한다. (FE-7)
  /// v0.1은 전체 경로를 현재 위치 기준으로 다시 계산하는 단순한 방식이다.
  Future<void> reroute() async {
    final destination = _destination;
    if (destination == null) return;
    await _locationSub?.cancel();
    await startTrip(destination);
  }

  void endTrip() {
    _locationSub?.cancel();
    _phase = TripPhase.idle;
    _route = null;
    _commandEngine = null;
    _currentCommand = null;
    _destination = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }
}
