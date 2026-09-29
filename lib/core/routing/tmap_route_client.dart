import 'package:dio/dio.dart';

import 'route_models.dart';

/// 목적지까지의 보행경로를 가져오는 "인터페이스". (FE-2)
///
/// [공부 포인트 — 왜 추상 클래스를 따로 뒀나]
/// 이건 Dart/OOP에서 자주 쓰는 "의존성 역전(Dependency Injection)" 패턴이다.
/// 앱의 나머지 코드(TripSession, HomeScreen 등)는 "RouteClient가 뭔지"만
/// 알고, 그게 실제 TMAP API를 부르는지 가짜(Mock) 데이터를 주는지는 전혀
/// 모른다. 덕분에:
///   1. TMAP API 키가 없어도 MockRouteClient로 앱 전체 파이프라인(경로→명령
///      →BLE 전송)을 미리 개발·테스트할 수 있었다.
///   2. 나중에 다른 지도 API로 바꾸고 싶으면 이 인터페이스를 구현하는 새
///      클래스만 만들면 되고, 그걸 쓰는 쪽 코드는 한 줄도 안 바뀐다.
///   3. 테스트 코드에서도 실제 네트워크 호출 없이 가짜 구현을 넣어 테스트할
///      수 있다.
/// main.dart에서 TMAP_APP_KEY 유무에 따라 둘 중 뭘 쓸지 결정한다.
abstract class RouteClient {
  Future<WalkingRoute> fetchWalkingRoute({
    required GeoPoint origin,
    required GeoPoint destination,
  });
}

/// TMAP API 키가 없는 동안 Command Engine·BLE 파이프라인을 먼저 검증하기
/// 위한 목(Mock) 클라이언트. 실제 네트워크 호출 없이 origin→destination
/// 중간에 우회전 1개가 있는 가짜 경로를 즉시 만들어 돌려준다.
class MockRouteClient implements RouteClient {
  @override
  Future<WalkingRoute> fetchWalkingRoute({
    required GeoPoint origin,
    required GeoPoint destination,
  }) async {
    // 실제 API처럼 약간의 지연을 흉내 내서, 로딩 상태 UI(스피너 등)도
    // 자연스럽게 테스트해볼 수 있게 한다.
    await Future.delayed(const Duration(milliseconds: 300));

    // 출발-목적지의 정중앙 지점을 하나 만들고, 거기서 한 번 우회전하는
    // 아주 단순한 가짜 경로를 구성한다.
    final mid = GeoPoint(
      origin.lat + (destination.lat - origin.lat) * 0.5,
      origin.lng + (destination.lng - origin.lng) * 0.5,
    );
    final distance = origin.distanceTo(mid) + mid.distanceTo(destination);

    return WalkingRoute(
      points: [origin, mid, destination],
      turnPoints: [
        TurnPoint(location: mid, turnType: 13, description: '우회전 (Mock)'),
      ],
      totalDistanceMeters: distance,
      totalTimeSeconds: (distance / 1.2).round(), // 평균 보행속도 약 1.2m/s 가정
    );
  }
}

/// SK Open API(TMAP) 보행자 경로 API 연동 — 실제 서비스에서 쓰는 구현체.
///
/// [실제 API를 어떻게 검증했나] tool/verify_tmap_route.dart라는 별도 스크립트로
/// 진짜 키를 넣어 한 번 호출해보고, 응답 구조를 직접 눈으로 확인한 뒤에야
/// 이 파싱 로직을 작성했다. 문서만 보고 추측해서 짜지 않은 이유는, 문서와
/// 실제 응답이 미묘하게 다른 경우가 흔하기 때문이다(실제로 turnType 관련
/// 필드 구조가 우리 첫 추측과 달랐다).
///
/// [응답 형식] TMAP은 GeoJSON(지리 정보를 표현하는 표준 JSON 포맷)
/// FeatureCollection을 응답으로 준다. 그 안에는 두 종류의 "feature"가 섞여
/// 있다:
/// - LineString: 실제 걸어야 할 길의 좌표들 (경로 이탈 판단에 사용)
/// - Point (pointType이 SP/GP/EP): 안내가 필요한 특정 지점들.
///   properties.turnType에 "직진/좌회전/우회전" 같은 공식 코드가 이미
///   들어있어서, 우리가 좌표 각도를 직접 계산할 필요가 없다.
///   이 중 실제 회전 판단이 필요한 GP(Guide Point, 경로 중간 지점)만
///   TurnPoint로 변환한다. SP(Start Point, 출발)와 EP(End Point, 도착)는
///   회전 명령이 아니라 CommandEngine이 "목적지까지 거리"로 별도 처리한다.
class TmapRouteClient implements RouteClient {
  TmapRouteClient({required this.appKey, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://apis.openapi.sk.com'));

  final String appKey;

  /// [공부 포인트] `dio`는 Flutter/Dart에서 널리 쓰이는 HTTP 클라이언트
  /// 라이브러리다. 생성자에서 `Dio? dio` 파라미터를 받아서 외부에서 안
  /// 넘겨주면 기본 인스턴스를 새로 만드는 이유는 테스트 용이성 때문이다 —
  /// 테스트 코드에서는 진짜 네트워크 대신 가짜 Dio(mock)를 주입할 수 있다.
  final Dio _dio;

  @override
  Future<WalkingRoute> fetchWalkingRoute({
    required GeoPoint origin,
    required GeoPoint destination,
  }) async {
    final response = await _dio.post(
      '/tmap/routes/pedestrian',
      queryParameters: {'version': 1},
      options: Options(headers: {'appKey': appKey}),
      data: {
        'startX': origin.lng.toString(),
        'startY': origin.lat.toString(),
        'endX': destination.lng.toString(),
        'endY': destination.lat.toString(),
        'startName': '출발지',
        'endName': '목적지',
        'reqCoordType': 'WGS84GEO', // 우리가 흔히 쓰는 위경도(WGS84) 좌표계로 요청
        'resCoordType': 'WGS84GEO', // 응답도 같은 좌표계로 받기
        'searchOption': '0',
      },
    );

    final geoJson = response.data as Map<String, dynamic>;
    final points = _extractPoints(geoJson);
    if (points.isEmpty) {
      // 좌표를 하나도 못 뽑았다는 건 응답 형식이 예상과 다르거나 API가
      // 경로를 못 찾았다는 뜻 — 조용히 빈 경로를 리턴하면 뒤에서 더 이상한
      // 에러로 이어지므로, 원인을 바로 알 수 있게 여기서 명확히 실패시킨다.
      throw StateError('TMAP 응답에서 경로 좌표를 찾지 못했습니다.');
    }

    final summary = _extractSummary(geoJson);
    return WalkingRoute(
      points: points,
      turnPoints: _extractTurnPoints(geoJson),
      totalDistanceMeters: summary.$1,
      totalTimeSeconds: summary.$2,
    );
  }

  /// SP(출발) 포인트의 properties에 함께 실려오는 전체 거리(m)/시간(초) 요약값을 뽑는다.
  ///
  /// [공부 포인트] 리턴 타입 `(double?, int?)`는 Dart 3에서 추가된 "레코드
  /// (record)" 문법이다. 굳이 별도 클래스를 안 만들어도 "값 두 개를 묶어서"
  /// 반환하고 싶을 때 쓴다. 호출하는 쪽에서는 `summary.$1`, `summary.$2`처럼
  /// 순서로 꺼내 쓴다 (자바의 여러 값 반환이 불가능한 것과 대조적으로, 굳이
  /// 튜플 클래스를 새로 정의하지 않아도 되는 게 장점).
  (double?, int?) _extractSummary(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? const [];
    for (final feature in features) {
      final properties = (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>?;
      if (properties?['pointType'] == 'SP') {
        final distance = (properties?['totalDistance'] as num?)?.toDouble();
        final time = (properties?['totalTime'] as num?)?.toInt();
        return (distance, time); // 괄호 안에 값 두 개 = 레코드 리터럴
      }
    }
    return (null, null);
  }

  /// GeoJSON 응답에서 LineString(실제 걸어야 할 길의 좌표) 부분만 뽑아낸다.
  List<GeoPoint> _extractPoints(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? const [];
    final points = <GeoPoint>[];

    for (final feature in features) {
      final geometry = (feature as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
      if (geometry == null || geometry['type'] != 'LineString') continue;

      final coordinates = geometry['coordinates'] as List<dynamic>;
      for (final coord in coordinates) {
        final c = coord as List<dynamic>;
        // [주의] GeoJSON 표준은 좌표 순서가 [경도(lng), 위도(lat)]다 — 우리가
        // 흔히 말하는 "위도, 경도" 순서와 반대라서 여기서 순서를 뒤집어준다.
        // 이걸 놓치면 지도에 완전히 엉뚱한 위치가 찍히는 흔한 버그가 난다.
        points.add(GeoPoint((c[1] as num).toDouble(), (c[0] as num).toDouble()));
      }
    }
    return points;
  }

  /// GeoJSON 응답에서 실제 회전 판단이 필요한 GP(Guide Point)만 뽑아
  /// TurnPoint 목록으로 변환한다.
  List<TurnPoint> _extractTurnPoints(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? const [];
    // (pointIndex, TurnPoint) 쌍의 리스트. 응답의 feature 배열 순서가 항상
    // 경로 진행 순서와 일치한다고 보장할 수 없어서, TMAP이 각 지점에 붙여주는
    // pointIndex 값으로 나중에 다시 정렬한다 — "정렬을 남에게 맡기지 않고
    // 우리가 직접 보장한다"는 방어적 코딩이다.
    final indexed = <(int, TurnPoint)>[];

    for (final feature in features) {
      final f = feature as Map<String, dynamic>;
      final geometry = f['geometry'] as Map<String, dynamic>?;
      final properties = f['properties'] as Map<String, dynamic>?;
      if (geometry == null || geometry['type'] != 'Point') continue;
      if (properties == null || properties['pointType'] != 'GP') continue;

      final coord = geometry['coordinates'] as List<dynamic>;
      indexed.add((
        (properties['pointIndex'] as num).toInt(),
        TurnPoint(
          location: GeoPoint((coord[1] as num).toDouble(), (coord[0] as num).toDouble()),
          turnType: (properties['turnType'] as num).toInt(),
          description: properties['description'] as String? ?? '',
        ),
      ));
    }
    // $1로 레코드의 첫 번째 값(pointIndex)을 기준으로 오름차순 정렬.
    indexed.sort((a, b) => a.$1.compareTo(b.$1));
    return indexed.map((e) => e.$2).toList(); // $2 = TurnPoint만 뽑아서 리스트로
  }
}
