import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobility_assist_app/core/routing/route_models.dart';
import 'package:mobility_assist_app/core/routing/tmap_route_client.dart';

/// 실제 네트워크 없이 TMAP 응답을 흉내 내는 Dio. 요청 body 를 캡처한다.
Dio _fakeDio(
  Map<String, dynamic> response,
  void Function(Map<String, dynamic>) onBody,
) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onBody(Map<String, dynamic>.from(options.data as Map));
        handler.resolve(Response(requestOptions: options, data: response));
      },
    ),
  );
  return dio;
}

Map<String, dynamic> _line(String facilityType, num distance) => {
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      [126.97, 37.55],
      [126.98, 37.56],
    ],
  },
  'properties': {'facilityType': facilityType, 'distance': distance},
};

void main() {
  final origin = GeoPoint(37.55, 126.97);
  final destination = GeoPoint(37.56, 126.98);
  final response = {
    'features': [
      {
        'geometry': {
          'type': 'Point',
          'coordinates': [126.97, 37.55],
        },
        'properties': {
          'pointType': 'SP',
          'totalDistance': 500,
          'totalTime': 400,
          'pointIndex': 0,
        },
      },
      _line('11', 120),
      _line('17', 38),
      _line('17', 81),
      _line('15', 21),
    ],
  };

  test('계단 회피(기본)면 searchOption 30 으로 요청한다', () async {
    late Map<String, dynamic> body;
    final client = TmapRouteClient(
      appKey: 'test',
      dio: _fakeDio(response, (b) => body = b),
    );
    await client.fetchWalkingRoute(origin: origin, destination: destination);
    expect(body['searchOption'], '30');
  });

  test('계단 회피를 끄면 searchOption 0 으로 요청한다', () async {
    late Map<String, dynamic> body;
    final client = TmapRouteClient(
      appKey: 'test',
      dio: _fakeDio(response, (b) => body = b),
    );
    await client.fetchWalkingRoute(
      origin: origin,
      destination: destination,
      avoidStairs: false,
    );
    expect(body['searchOption'], '0');
  });

  test('응답의 facilityType 17 구간 길이를 stairsMeters 로 합산한다', () async {
    final client = TmapRouteClient(
      appKey: 'test',
      dio: _fakeDio(response, (_) {}),
    );
    final route = await client.fetchWalkingRoute(
      origin: origin,
      destination: destination,
    );
    expect(route.stairsMeters, 119); // 38 + 81
  });
}
