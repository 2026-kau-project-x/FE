import 'dart:math' as math;

import '../../core/routing/route_models.dart';

/// 현재 위치가 경로 polyline에서 너무 많이 벗어났는지 판단한다. (FE-7)
///
/// TripSession이 GPS 위치가 갱신될 때마다 이걸 호출해서, 벗어났다고 판단되면
/// CommandEngine의 정상 명령 대신 NavigationCommand.offRoute("잘못된 경로로
/// 진행중")를 장갑에 보낸다.
class OffRouteDetector {
  const OffRouteDetector({this.thresholdMeters = 25});

  /// 경로에서 이 거리(m)를 초과해서 벗어나면 "이탈"로 판단한다.
  /// GPS 자체 오차(특히 실내·건물 사이 등)를 고려해 여유를 좀 뒀다.
  final double thresholdMeters;

  /// 현재 위치에서 경로 polyline까지의 "최단 거리"가 thresholdMeters를
  /// 넘는지 확인한다. 경로는 여러 개의 좌표(points)로 이어진 꺾은선이므로,
  /// 각 구간(선분)마다 최단 거리를 구해서 그중 제일 작은 값을 쓴다 —
  /// 즉 "경로 전체 중 나와 가장 가까운 지점까지의 거리"를 구하는 것.
  bool isOffRoute(GeoPoint current, WalkingRoute route) {
    if (route.points.length < 2) return false;

    var minDistance = double.infinity;
    for (var i = 0; i < route.points.length - 1; i++) {
      final d = _distanceToSegment(current, route.points[i], route.points[i + 1]);
      if (d < minDistance) minDistance = d;
    }
    return minDistance > thresholdMeters;
  }

  /// 점(p)과 선분(a-b) 사이의 최단 거리(m)를 계산한다.
  ///
  /// [공부 포인트 — 왜 이렇게 복잡하게 계산하나]
  /// "점과 선분 사이 최단거리"는 평면 기하학에서는 벡터 투영(projection)으로
  /// 간단히 풀리는 문제지만, 위도·경도는 각도 단위라 그대로 평면 좌표처럼
  /// 계산하면 왜곡이 생긴다(위도가 높아질수록 경도 1도의 실제 거리가 줄어듦).
  /// 그래서 이 구간에서만 위경도를 "지역 평면 좌표(미터 단위)"로 근사 변환한
  /// 뒤, 그 위에서 일반적인 벡터 투영 공식을 적용한다. 보행 스케일(수십~수백m)
  /// 에서는 이 근사가 충분히 정확하고, 매번 Haversine을 여러 번 호출하는 것보다
  /// 훨씬 가벼운 연산이다.
  static double _distanceToSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
    // 위도 1도 ≈ 111.32km는 지구 어디서나 거의 일정하지만, 경도 1도의 실제
    // 거리는 위도에 따라 cos(위도)만큼 줄어든다(적도에서 멀어질수록 경도선
    // 간격이 좁아지기 때문). latRef는 a와 b의 중간 위도를 기준으로 삼는다.
    final latRef = (a.lat + b.lat) / 2 * math.pi / 180;
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(latRef);

    // 위경도를 "미터 단위의 평면 좌표"로 변환 (x=경도 방향, y=위도 방향)
    final ax = a.lng * mPerDegLng, ay = a.lat * mPerDegLat;
    final bx = b.lng * mPerDegLng, by = b.lat * mPerDegLat;
    final px = p.lng * mPerDegLng, py = p.lat * mPerDegLat;

    final dx = bx - ax, dy = by - ay;
    if (dx == 0 && dy == 0) return p.distanceTo(a); // a와 b가 같은 점인 퇴화 케이스

    // p에서 선분 a-b로 내린 수선의 발이 선분 안쪽 어디에 위치하는지를
    // 0(=a)~1(=b) 사이 비율(t)로 구한다. clamp로 0~1 밖으로 못 나가게 막는
    // 이유: 수선의 발이 선분 바깥으로 벗어나면(연장선상) 그건 의미가 없고,
    // 그 경우엔 그냥 가장 가까운 끝점(a 또는 b)까지의 거리를 써야 하기 때문.
    var t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    t = t.clamp(0.0, 1.0);

    final projX = ax + t * dx, projY = ay + t * dy; // 선분 위의 가장 가까운 점
    final ddx = px - projX, ddy = py - projY;
    return math.sqrt(ddx * ddx + ddy * ddy);
  }
}
