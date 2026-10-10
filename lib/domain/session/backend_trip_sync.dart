import 'package:flutter/foundation.dart';

import '../../core/backend/trip_api_client.dart';
import '../../core/routing/route_models.dart';
import 'trip_state.dart';

/// 앱의 TripPhase 변화를 BE 이동 상태로 "보고"하는 동기화기.
///
/// [상태 매핑] (앱 TripPhase → BE TripStatus)
/// - 출발(navigating 진입)      → 이동 생성(REQUESTED) 후 WALKING
/// - 경로 이탈(rerouting)        → WAITING
/// - 재탐색 후 다시 navigating   → WALKING   (이동은 새로 만들지 않고 같은 id 유지)
/// - 도착(arrived)               → RENDEZVOUS (Phase 1은 목적지 = 합류 지점으로 간주)
/// - 안내 종료: 도착했으면 COMPLETED, 도중에 끝냈으면 CANCELLED
///
/// [설계 원칙 — 보고는 안내를 절대 막지 않는다]
/// 1. 모든 메서드는 기다리지(await) 않아도 되게 "던져두고(fire-and-forget)" 끝난다.
///    GPS 콜백 안에서 서버 응답을 기다리면 장갑 명령이 늦어질 수 있기 때문이다.
/// 2. 대신 요청 순서는 지켜야 한다(생성 → WALKING → WAITING …). 그래서 내부에
///    Future 체인(_queue)을 두고 앞 요청이 끝난 뒤 다음 요청을 보낸다.
/// 3. 네트워크 오류는 로그만 남기고 삼킨다. 생성이 실패하면 그 이동은 보고를 포기한다.
class BackendTripSync {
  BackendTripSync(this._api);

  final TripApiClient _api;

  int? _tripId;
  BackendTripStatus? _lastSent;

  /// [공부 포인트 — Future 체인으로 순서 보장]
  /// `_queue = _queue.then(...)` 을 반복하면 작업들이 한 줄로 이어진다. 각 작업은
  /// 앞 작업이 끝나야 시작되므로, 비동기 HTTP 요청이라도 보낸 순서대로 서버에 도착한다.
  Future<void> _queue = Future.value();

  /// 테스트에서 "지금까지 쌓인 보고가 다 끝날 때까지" 기다리기 위한 getter.
  Future<void> get idle => _queue;

  int? get tripId => _tripId;

  /// 출발 또는 재탐색이 끝나 안내가 (다시) 시작됐을 때.
  void tripStarted({
    required GeoPoint origin,
    required GeoPoint destination,
    String? destinationName,
  }) {
    _enqueue(() async {
      // 재탐색(reroute)도 startTrip 을 다시 타지만, 같은 이동이므로 새로 만들지 않는다
      _tripId ??= await _api.createTrip(
        origin: origin,
        destination: destination,
        destinationName: destinationName,
      );
    });
    _send(BackendTripStatus.walking);
  }

  /// GPS 업데이트로 TripPhase 가 바뀌었을 때.
  void phaseChanged(TripPhase phase) {
    switch (phase) {
      case TripPhase.navigating:
        _send(BackendTripStatus.walking);
      case TripPhase.rerouting:
        _send(BackendTripStatus.waiting);
      case TripPhase.arrived:
        _send(BackendTripStatus.rendezvous);
      case TripPhase.idle:
      case TripPhase.routing:
        break; // BE 에 대응하는 상태가 없음
    }
  }

  /// "안내 종료" 시. 다음 출발은 새 이동으로 기록되도록 상태를 비운다.
  void tripEnded({required bool arrived}) {
    _send(arrived ? BackendTripStatus.completed : BackendTripStatus.cancelled);
    _enqueue(() async {
      _tripId = null;
      _lastSent = null;
    });
  }

  /// 직전에 보낸 상태와 같으면 건너뛴다 (BE 에서 같은 상태로의 전이는 409).
  void _send(BackendTripStatus status) {
    _enqueue(() async {
      final id = _tripId;
      if (id == null || status == _lastSent) return; // 생성 실패했거나 중복
      await _api.updateStatus(id, status);
      _lastSent = status;
    });
  }

  void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) async {
      try {
        await job();
      } catch (e) {
        debugPrint('BE 이동 상태 보고 실패(안내는 계속): $e');
      }
    });
  }
}
