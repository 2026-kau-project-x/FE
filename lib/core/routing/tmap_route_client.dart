import 'package:dio/dio.dart';

import 'route_models.dart';

/// 목적지까지의 보행경로를 가져오는 인터페이스. (FE-2)
abstract class RouteClient {
  Future<WalkingRoute> fetchWalkingRoute({
    required GeoPoint origin,
    required GeoPoint destination,
  });
}

/// TMAP API 키가 없는 동안 커맨드 엔진·BLE 파이프라인을 먼저 검증하기 위한 목 클라이언트.
/// origin→destination 중간에 우회전 1개를 가진 가짜 경로를 반환한다.
class MockRouteClient implements RouteClient {
  @override
  Future<WalkingRoute> fetchWalkingRoute({
    required GeoPoint origin,
    required GeoPoint destination,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

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

/// SK Open API(TMAP) 보행자 경로 API 연동.
///
/// 실제 appKey로 검증 완료 (tool/verify_tmap_route.dart). 응답은 GeoJSON
/// FeatureCollection이며 두 종류의 feature를 담고 있다:
/// - LineString: 경로 polyline 좌표 (이탈 감지용)
/// - Point (pointType: SP/GP/EP): 안내지점. properties.turnType이 공식 회전
///   코드를 담고 있어 좌표 각도를 재계산할 필요가 없다. 이 중 실제 회전 판단이
///   필요한 GP(Guide Point)만 [TurnPoint]로 변환한다 — SP(출발)·EP(도착)는
///   CommandEngine이 거리 기반으로 별도 처리한다.
class TmapRouteClient implements RouteClient {
  TmapRouteClient({required this.appKey, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://apis.openapi.sk.com'));

  final String appKey;
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
        'reqCoordType': 'WGS84GEO',
        'resCoordType': 'WGS84GEO',
        'searchOption': '0',
      },
    );

    final geoJson = response.data as Map<String, dynamic>;
    final points = _extractPoints(geoJson);
    if (points.isEmpty) {
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

  /// SP(출발) 포인트에 실려오는 전체 거리(m)/시간(초) 요약값.
  (double?, int?) _extractSummary(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? const [];
    for (final feature in features) {
      final properties = (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>?;
      if (properties?['pointType'] == 'SP') {
        final distance = (properties?['totalDistance'] as num?)?.toDouble();
        final time = (properties?['totalTime'] as num?)?.toInt();
        return (distance, time);
      }
    }
    return (null, null);
  }

  List<GeoPoint> _extractPoints(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? const [];
    final points = <GeoPoint>[];

    for (final feature in features) {
      final geometry = (feature as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
      if (geometry == null || geometry['type'] != 'LineString') continue;

      final coordinates = geometry['coordinates'] as List<dynamic>;
      for (final coord in coordinates) {
        final c = coord as List<dynamic>;
        // GeoJSON은 [lng, lat] 순서
        points.add(GeoPoint((c[1] as num).toDouble(), (c[0] as num).toDouble()));
      }
    }
    return points;
  }

  List<TurnPoint> _extractTurnPoints(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? const [];
    // (pointIndex, TurnPoint) — feature 배열 순서에 기대지 않고 pointIndex로 정렬한다.
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
    indexed.sort((a, b) => a.$1.compareTo(b.$1));
    return indexed.map((e) => e.$2).toList();
  }
}
