import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobility_assist_app/core/backend/trip_api_client.dart';
import 'package:mobility_assist_app/core/ble/ble_service.dart';
import 'package:mobility_assist_app/core/location/location_service.dart';
import 'package:mobility_assist_app/core/routing/route_models.dart';
import 'package:mobility_assist_app/core/routing/tmap_route_client.dart';
import 'package:mobility_assist_app/domain/session/trip_state.dart';

/// TripSession 이 앱 상태 변화를 BE 에 올바른 순서로 보고하는지 검증한다.
/// 실제 GPS·서버 대신 가짜(Fake) 객체를 끼워서, 위치를 우리가 원하는 대로 흘려보낸다.

/// 호출 기록만 남기는 가짜 BE 클라이언트.
class FakeTripApi implements TripApiClient {
  FakeTripApi({this.failCreate = false});

  final bool failCreate;
  final calls = <String>[];

  @override
  Future<int> createTrip({
    required GeoPoint origin,
    required GeoPoint destination,
    String? destinationName,
  }) async {
    if (failCreate) throw Exception('BE 꺼짐');
    calls.add('create:$destinationName');
    return 42;
  }

  @override
  Future<void> updateStatus(int tripId, BackendTripStatus status) async {
    calls.add('$tripId:${status.wire}');
  }
}

/// 권한은 항상 허용, 현재 위치는 고정, 위치 스트림은 테스트가 직접 add 하는 가짜 GPS.
class FakeLocationService extends LocationService {
  FakeLocationService(this.origin);

  final GeoPoint origin;
  final controller = StreamController<GeoPoint>.broadcast();

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<GeoPoint> getCurrentLocation() async => origin;

  @override
  Stream<GeoPoint> watchLocation() => controller.stream;
}

// MockRouteClient 는 출발지→목적지 직선(중간에 꺾이는 점 1개) 경로를 만든다. 남북 약 220 m.
const origin = GeoPoint(37.5500, 126.9900);
const destination = GeoPoint(37.5520, 126.9900);
const onRoute = GeoPoint(37.5505, 126.9900);
const offRoute = GeoPoint(37.5510, 126.9910); // 경로에서 동쪽으로 약 88 m (이탈 임계 25 m 초과)
const backOnRoute = GeoPoint(37.5512, 126.9900);

void main() {
  late FakeLocationService location;

  setUp(() => location = FakeLocationService(origin));
  tearDown(() => location.controller.close());

  TripSession newSession(TripApiClient api) => TripSession(
        routeClient: MockRouteClient(),
        locationService: location,
        bleService: GloveBleService(),
        tripApi: api,
      );

  /// 위치 하나를 흘려보내고, 앱 처리 + BE 보고가 끝날 때까지 기다린다.
  Future<void> walkTo(TripSession session, GeoPoint p) async {
    location.controller.add(p);
    await pumpEventQueue();
    await session.backendIdle;
  }

  test('출발→이탈→복귀→도착→종료 순서대로 BE 상태가 보고된다', () async {
    final api = FakeTripApi();
    final session = newSession(api);

    await session.startTrip(destination, destinationName: '테스트 목적지');
    await walkTo(session, onRoute); // 계속 WALKING 이라 추가 보고 없음
    await walkTo(session, offRoute);
    await walkTo(session, backOnRoute);
    await walkTo(session, destination);
    expect(session.phase, TripPhase.arrived);

    session.endTrip();
    await session.backendIdle;

    expect(api.calls, [
      'create:테스트 목적지',
      '42:WALKING',
      '42:WAITING',
      '42:WALKING',
      '42:RENDEZVOUS',
      '42:COMPLETED',
    ]);
  });

  test('재탐색은 이동을 새로 만들지 않고, 도중 종료는 CANCELLED', () async {
    final api = FakeTripApi();
    final session = newSession(api);

    await session.startTrip(destination);
    await walkTo(session, offRoute);
    await session.reroute(); // 경로를 다시 받아 navigating 으로 복귀
    await session.backendIdle;
    session.endTrip();
    await session.backendIdle;

    expect(api.calls, [
      'create:null',
      '42:WALKING',
      '42:WAITING',
      '42:WALKING',
      '42:CANCELLED',
    ]);
  });

  test('BE 가 꺼져 있어도 안내는 그대로 동작한다', () async {
    final api = FakeTripApi(failCreate: true);
    final session = newSession(api);

    await session.startTrip(destination);
    await walkTo(session, offRoute);
    expect(session.phase, TripPhase.rerouting); // 안내 로직은 정상
    await walkTo(session, destination);
    expect(session.phase, TripPhase.arrived);
    expect(api.calls, isEmpty); // 생성 실패 → 이후 보고는 포기
  });
}
