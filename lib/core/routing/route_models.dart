import 'dart:math' as math;

/// 위도·경도 한 쌍을 표현하는 값 객체(value object).
///
/// [공부 포인트] flutter_map 같은 지도 라이브러리는 이미 자기 자신의 좌표 타입
/// (LatLng)을 갖고 있는데, 왜 굳이 GeoPoint를 또 만들었을까? 우리 앱의 핵심
/// 로직(경로 계산, 경로 이탈 판단, BLE 명령 산출 등)까지 특정 지도 라이브러리의
/// 타입에 종속시키고 싶지 않아서다. 나중에 지도 라이브러리를 바꾸더라도
/// core/domain 레이어는 전혀 손댈 필요가 없다. 화면(presentation) 레이어에서만
/// LatLng ↔ GeoPoint를 서로 변환해서 쓴다 (home_screen.dart 참고).
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// 두 지점 사이의 실제 지표면 거리(m)를 계산한다. Haversine 공식 —
  /// 지구를 완벽한 구(sphere)로 근사해서 위도·경도 두 점 사이 거리를 구하는
  /// 표준적인 방법이다. 단거리(보행 스케일)에서는 오차가 무시할 만큼 작다.
  double distanceTo(GeoPoint other) {
    const earthRadiusM = 6371000.0; // 지구 평균 반지름(m)
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

/// 경로 상의 안내지점(TMAP 용어로 Guide Point) 하나 — "여기서 이런 동작을
/// 해야 한다"를 나타내는 지점.
///
/// [설계 배경 — 왜 좌표 각도를 직접 계산하지 않는가]
/// 처음 구현할 때는 polyline 좌표들의 진행 방향이 얼마나 꺾이는지를 직접
/// 계산해서 "여기서 회전했다"를 판단하려고 했다. 그런데 실제 TMAP 응답으로
/// 검증해보니, 보도가 자연스럽게 살짝 휘어지는 구간(도로 곡률)까지 전부
/// "회전"으로 오인식해서 같은 구간에서 좌표 기반 계산은 20개의 회전을
/// 찾아냈지만 진짜 회전은 11개뿐이었다. 그래서 좌표를 우리가 재해석하지
/// 않고, TMAP이 이미 계산해서 내려주는 공식 turnType 값을 그대로 신뢰하는
/// 방식으로 설계를 바꿨다 (tmap_route_client.dart, command_engine.dart 참고).
class TurnPoint {
  const TurnPoint({
    required this.location,
    required this.turnType,
    this.description = '',
  });

  final GeoPoint location;

  /// TMAP 보행자 경로 API의 turnType 코드 (예: 11=직진, 13=우회전, 211=횡단보도).
  /// 실제 값 → NavigationCommand(장갑에 보낼 7종 명령) 매핑은 CommandEngine이
  /// 전담한다 — 이 모델 클래스는 "TMAP이 뭐라고 했는지"만 순수하게 담아둔다.
  final int turnType;

  /// TMAP이 제공하는 사람이 읽는 안내 문구 (예: "OO 사거리에서 우회전").
  /// 명령(Command) 산출 로직에는 전혀 쓰이지 않고, 디버깅 출력이나 향후
  /// UI 표시용으로만 들고 있는 부가 정보다.
  final String description;
}

/// 목적지까지의 보행 경로 전체를 담는 모델. TMAP 응답이든 테스트용 Mock
/// 데이터든, 이 모델로 변환된 이후로는 앱의 나머지 코드가 출처를 신경 쓸
/// 필요가 없다 (RouteClient 인터페이스와 함께 보면 이해가 쉽다).
class WalkingRoute {
  const WalkingRoute({
    required this.points,
    required this.turnPoints,
    this.totalDistanceMeters,
    this.totalTimeSeconds,
  });

  /// 경로를 이루는 좌표들의 연속(polyline). 지도에 선을 그리거나(home_screen.dart),
  /// 사용자가 경로에서 얼마나 벗어났는지 판단(off_route_detector.dart)하는 데 쓰인다.
  final List<GeoPoint> points;

  /// 실제로 방향 안내가 필요한 지점들만 순서대로 모아둔 목록.
  /// points는 보통 수십~수백 개인데 turnPoints는 그중 실제 갈림길·교차로에
  /// 해당하는 몇 개뿐이다.
  final List<TurnPoint> turnPoints;

  /// TMAP이 함께 제공하는 전체 보행 거리(m)/예상 소요시간(초).
  /// MockRouteClient 등 일부 구현에서는 값이 없을 수 있어 nullable로 뒀고,
  /// 온보딩 화면(home_screen.dart)에서는 null이면 그냥 해당 표시를 생략한다.
  final double? totalDistanceMeters;
  final int? totalTimeSeconds;

  /// 편의 getter: 경로의 마지막 좌표 = 목적지. points가 비어있지 않다는
  /// 전제 하에 안전하다 (TmapRouteClient가 빈 경로면 애초에 예외를 던진다).
  GeoPoint get destination => points.last;
}
