import 'package:dio/dio.dart';

/// 좌표(위도·경도)를 사람이 읽을 수 있는 주소 문자열로 변환한다.
/// 온보딩 화면에서 사용자가 지도를 탭해 목적지를 고르면, "여기가 어딘지"를
/// 숫자 좌표가 아니라 실제 주소로 보여주기 위해 쓴다.
///
/// [공부 포인트] tmap_route_client.dart의 RouteClient와 똑같은 패턴이다 —
/// 인터페이스(abstract class) + Mock 구현체 + 실제 API 구현체로 나눠서,
/// TMAP 키 유무에 관계없이 앱의 나머지 부분(HomeScreen)을 개발·테스트할 수
/// 있게 했다.
abstract class ReverseGeocodingClient {
  Future<String> reverseGeocode({required double lat, required double lng});
}

/// TMAP API 키가 없는 동안 UI 파이프라인을 검증하기 위한 목(Mock) 클라이언트.
class MockReverseGeocodingClient implements ReverseGeocodingClient {
  @override
  Future<String> reverseGeocode({required double lat, required double lng}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return '주소 확인 불가 (Mock)';
  }
}

/// SK Open API(TMAP) 리버스지오코딩(좌표→주소 변환) 연동.
///
/// [실제 API 검증] tool/verify_tmap_reverse_geocode.dart 스크립트로 실제 키를
/// 넣어 응답을 직접 확인한 뒤 이 파싱 로직을 작성했다. addressType=A10으로
/// 요청하면 도로명(roadName)·건물번호(buildingIndex)·건물명(buildingName)과
/// 지번주소 구성요소(legalDong, bunji)가 한 번에 같이 온다 — 그래서 도로명이
/// 없는 지점(도로명 주소 체계가 아직 안 잡힌 일부 외곽 지역)을 만나면 지번
/// 주소로 자연스럽게 폴백할 수 있다.
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
        'addressType': 'A10', // 도로명+지번 정보를 함께 받는 옵션
      },
      options: Options(headers: {'appKey': appKey}),
    );

    final info = (response.data as Map<String, dynamic>)['addressInfo'] as Map<String, dynamic>?;
    if (info == null) {
      throw StateError('TMAP 리버스지오코딩 응답에서 주소 정보를 찾지 못했습니다.');
    }
    return _formatAddress(info);
  }

  /// TMAP 응답 필드들을 사람이 읽기 좋은 한 줄 주소 문자열로 조합한다.
  /// 예: "서울특별시 중구 세종대로 99 (덕수궁)"
  String _formatAddress(Map<String, dynamic> info) {
    // 작은 헬퍼 함수를 로컬 변수처럼 정의해서 반복되는 null 처리(값이 없으면
    // 빈 문자열)를 한 곳에 모았다. Dart에서는 함수도 변수처럼 지역적으로
    // 정의해서 쓸 수 있다.
    String field(String key) => (info[key] as String? ?? '').trim();

    final cityDo = field('city_do'); // 시/도 (예: 서울특별시)
    final guGun = field('gu_gun'); // 구/군 (예: 중구)
    final roadName = field('roadName'); // 도로명 (예: 세종대로)
    final buildingIndex = field('buildingIndex'); // 건물번호 (예: 99)
    final buildingName = field('buildingName'); // 건물명 (예: 덕수궁)
    final legalDong = field('legalDong'); // 법정동 (지번주소용, 예: 정동)
    final bunji = field('bunji'); // 지번 (예: 5-1)

    if (roadName.isNotEmpty) {
      // 도로명 주소를 만들 수 있는 경우: "시/도 구/군 도로명 건물번호 (건물명)"
      final building = buildingIndex.isNotEmpty ? ' $buildingIndex' : '';
      final name = buildingName.isNotEmpty ? ' ($buildingName)' : '';
      // where()로 빈 문자열을 걸러내고 join(' ')으로 공백 하나씩만 넣어 합친다
      // — cityDo나 guGun이 혹시 비어있어도 어색한 이중 공백이 안 생긴다.
      final base = [cityDo, guGun, roadName].where((p) => p.isNotEmpty).join(' ');
      return '$base$building$name';
    }

    // 도로명 정보가 없는 지점(일부 외곽 지역)은 지번주소로 폴백.
    final jibun = [legalDong, bunji].where((p) => p.isNotEmpty).join(' ');
    return [cityDo, guGun, jibun].where((p) => p.isNotEmpty).join(' ');
  }
}
