// TMAP 리버스지오코딩(좌표→주소) API 실제 응답 스키마 확인용 1회성 스크립트.
// 엔드포인트/파라미터가 문서 기준 추정치라 실제 키로 찍어보고 파싱 형태를 정한다.
//
// 실행: dart run tool/verify_tmap_reverse_geocode.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

String _loadAppKey() {
  final file = File('env.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return json['TMAP_APP_KEY'] as String;
}

Future<void> main() async {
  final appKey = _loadAppKey();
  final dio = Dio(BaseOptions(baseUrl: 'https://apis.openapi.sk.com'));

  // 서울시청 근처 좌표로 테스트
  const lat = 37.5663;
  const lon = 126.9779;

  for (final addressType in ['A10', 'A02', 'A00']) {
    // ignore: avoid_print
    print('=== addressType=$addressType ===');
    try {
      final response = await dio.get(
        '/tmap/geo/reversegeocoding',
        queryParameters: {
          'version': 1,
          'lat': lat,
          'lon': lon,
          'coordType': 'WGS84GEO',
          'addressType': addressType,
        },
        options: Options(headers: {'appKey': appKey}),
      );
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(response.data));
    } catch (e) {
      // ignore: avoid_print
      print('실패: $e');
      if (e is DioException) {
        // ignore: avoid_print
        print('응답 바디: ${e.response?.data}');
      }
    }
    // ignore: avoid_print
    print('');
  }
}
