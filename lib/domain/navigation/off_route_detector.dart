import 'dart:math' as math;

import '../../core/routing/route_models.dart';

/// 현재 위치가 경로 polyline에서 [thresholdMeters] 이상 벗어났는지 판단한다. (FE-7)
class OffRouteDetector {
  const OffRouteDetector({this.thresholdMeters = 25});

  final double thresholdMeters;

  bool isOffRoute(GeoPoint current, WalkingRoute route) {
    if (route.points.length < 2) return false;

    var minDistance = double.infinity;
    for (var i = 0; i < route.points.length - 1; i++) {
      final d = _distanceToSegment(current, route.points[i], route.points[i + 1]);
      if (d < minDistance) minDistance = d;
    }
    return minDistance > thresholdMeters;
  }

  /// 점-선분 최단거리(m). 위경도를 현지 평면좌표로 근사 투영해서 계산한다
  /// (보행 스케일에서는 충분히 정확하고, Haversine 반복 계산보다 훨씬 가볍다).
  static double _distanceToSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
    final latRef = (a.lat + b.lat) / 2 * math.pi / 180;
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(latRef);

    final ax = a.lng * mPerDegLng, ay = a.lat * mPerDegLat;
    final bx = b.lng * mPerDegLng, by = b.lat * mPerDegLat;
    final px = p.lng * mPerDegLng, py = p.lat * mPerDegLat;

    final dx = bx - ax, dy = by - ay;
    if (dx == 0 && dy == 0) return p.distanceTo(a);

    var t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    t = t.clamp(0.0, 1.0);

    final projX = ax + t * dx, projY = ay + t * dy;
    final ddx = px - projX, ddy = py - projY;
    return math.sqrt(ddx * ddx + ddy * ddy);
  }
}
