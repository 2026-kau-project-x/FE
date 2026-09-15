import 'package:dio/dio.dart';

/// 좌표를 사람이 읽을 수 있는 주소로 변환한다. (온보딩 목적지 표시용)
abstract class ReverseGeocodingClient {
  Future<String> reverseGeocode({required double lat, required double lng});
}

/// TMAP API 키가 없는 동안 UI 파이프라인을 검증하기 위한 목 클라이언트.
class MockReverseGeocodingClient implements ReverseGeocodingClient {
  @override
  Future<String> reverseGeocode({required double lat, required double lng}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return '주소 확인 불가 (Mock)';
  }
}

/// SK Open API(TMAP) 리버스지오코딩 연동.
///
/// 실제 appKey로 검증 완료 (tool/verify_tmap_reverse_geocode.dart). addressType=A10
/// 응답에는 도로명(roadName)·건물번호(buildingIndex)·건물명(buildingName)과 지번주소
/// 요소가 함께 오는데, 도로명이 없는 지점(일부 외곽 지역)을 대비해 지번주소로 폴백한다.
class TmapReverseGeocodingClient implements ReverseGeocodingClient {
  TmapReverseGeocodingClient({required this.appKey, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://apis.openapi.sk.com'));

  final String appKey;
  final Dio _dio;

  @override
  Future<String> reverseGeocode({required double lat, required double lng}) async {
    final response = await _dio.get(
      '/tmap/geo/reversegeocoding',
      queryParameters: {
        'version': 1,
        'lat': lat,
        'lon': lng,
        'coordType': 'WGS84GEO',
        'addressType': 'A10',
      },
      options: Options(headers: {'appKey': appKey}),
    );

    final info = (response.data as Map<String, dynamic>)['addressInfo'] as Map<String, dynamic>?;
    if (info == null) {
      throw StateError('TMAP 리버스지오코딩 응답에서 주소 정보를 찾지 못했습니다.');
    }
    return _formatAddress(info);
  }

  String _formatAddress(Map<String, dynamic> info) {
    String field(String key) => (info[key] as String? ?? '').trim();

    final cityDo = field('city_do');
    final guGun = field('gu_gun');
    final roadName = field('roadName');
    final buildingIndex = field('buildingIndex');
    final buildingName = field('buildingName');
    final legalDong = field('legalDong');
    final bunji = field('bunji');

    if (roadName.isNotEmpty) {
      final building = buildingIndex.isNotEmpty ? ' $buildingIndex' : '';
      final name = buildingName.isNotEmpty ? ' ($buildingName)' : '';
      final base = [cityDo, guGun, roadName].where((p) => p.isNotEmpty).join(' ');
      return '$base$building$name';
    }

    // 도로명 정보가 없는 지점(일부 외곽 지역)은 지번주소로 폴백.
    final jibun = [legalDong, bunji].where((p) => p.isNotEmpty).join(' ');
    return [cityDo, guGun, jibun].where((p) => p.isNotEmpty).join(' ');
  }
}
