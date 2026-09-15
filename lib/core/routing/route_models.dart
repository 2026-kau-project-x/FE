import 'dart:math' as math;

class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// 두 지점 사이 거리(m). Haversine.
  double distanceTo(GeoPoint other) {
    const earthRadiusM = 6371000.0;
    final dLat = _deg2rad(other.lat - lat);
    final dLng = _deg2rad(other.lng - lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat)) *
            math.cos(_deg2rad(other.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _deg2rad(double deg) => deg * math.pi / 180;
}

/// 경로 상의 안내지점(TMAP Guide Point) 하나.
///
/// 좌표만으로 각도를 재계산하지 않고 TMAP이 내려주는 turnType을 그대로 보존한다 —
/// 실제 응답으로 검증해본 결과 polyline 각도 기반 자체 판정은 보도의 자연스러운
/// 곡률까지 회전으로 오인식해 지나치게 민감했다.
class TurnPoint {
  const TurnPoint({
    required this.location,
    required this.turnType,
    this.description = '',
  });

  final GeoPoint location;

  /// TMAP 보행자 경로 API의 turnType 코드 (예: 11=직진, 13=우회전).
  final int turnType;

  /// TMAP이 제공하는 안내 문구. 커맨드 산출에는 쓰이지 않고 디버깅·UI 표시용.
  final String description;
}

class WalkingRoute {
  const WalkingRoute({
    required this.points,
    required this.turnPoints,
    this.totalDistanceMeters,
    this.totalTimeSeconds,
  });

  /// 경로 polyline (이탈 감지·지도 표시에 사용)
  final List<GeoPoint> points;

  /// 순서대로 정렬된 턴포인트 목록
  final List<TurnPoint> turnPoints;

  /// TMAP이 제공하는 전체 보행 거리(m)/소요시간(초). 없으면 온보딩 화면에 표시하지 않는다.
  final double? totalDistanceMeters;
  final int? totalTimeSeconds;

  GeoPoint get destination => points.last;
}
