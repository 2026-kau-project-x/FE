// TMAP 보행자 경로 API 실제 응답 스키마를 검증하기 위한 1회성 CLI 스크립트.
//
// tmap_route_client.dart의 엔드포인트/파라미터는 공식 문서 기준 추정치라
// 실제 키로 한 번 찍어보고 파싱이 맞는지 확인해야 한다.
//
// 실행 전: env.json.example을 복사해 env.json을 만들고 실제 키를 채워둘 것
// (env.json은 .gitignore에 등록되어 있어 커밋되지 않는다).
//
//   dart run tool/verify_tmap_route.dart
//
// 이 SDK의 `dart run`은 --dart-define-from-file을 지원하지 않아 env.json을
// 직접 읽는 방식으로 구현했다 (flutter run은 계속 --dart-define-from-file 사용 가능).
import 'dart:convert';
import 'dart:io';

import 'package:mobility_assist_app/core/routing/route_models.dart';
import 'package:mobility_assist_app/core/routing/tmap_route_client.dart';

String _loadAppKey() {
  final file = File('env.json');
  if (!file.existsSync()) {
    throw StateError(
      'env.json이 없습니다. env.json.example을 복사해서 실제 키를 채워주세요.',
    );
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final key = json['TMAP_APP_KEY'] as String?;
  if (key == null || key.isEmpty || key.contains('교체')) {
    throw StateError('env.json의 TMAP_APP_KEY가 비어있거나 placeholder 그대로입니다.');
  }
  return key;
}

void main() async {
  final String appKey;
  try {
    appKey = _loadAppKey();
  } on StateError catch (e) {
    // ignore: avoid_print
    print(e.message);
    return;
  }

  final origin = GeoPoint(37.5663, 126.9779); // 서울시청
  final destination = GeoPoint(37.5759, 126.9769); // 광화문 방면

  final client = TmapRouteClient(appKey: appKey);

  // ignore: avoid_print
  print('--- TMAP 보행자 경로 요청 중 ---');
  try {
    final route = await client.fetchWalkingRoute(
      origin: origin,
      destination: destination,
    );

    // ignore: avoid_print
    print('polyline 좌표 수: ${route.points.length}');
    // ignore: avoid_print
    print('감지된 turnPoint 수: ${route.turnPoints.length}');

    for (var i = 0; i < route.turnPoints.length; i++) {
      final t = route.turnPoints[i];
      // ignore: avoid_print
      print(
        '[$i] (${t.location.lat}, ${t.location.lng}) '
        'turnType=${t.turnType} "${t.description}"',
      );
    }

    // ignore: avoid_print
    print('\n--- 성공: 파싱 로직이 실제 응답과 호환됩니다 ---');
  } catch (e, st) {
    // ignore: avoid_print
    print('\n--- 실패: 요청/파싱 단계에서 에러 발생 ---');
    // ignore: avoid_print
    print(e);
    // ignore: avoid_print
    print(st);
    // ignore: avoid_print
    print(
      '\nDioException이면 e.response?.data를 찍어 실제 에러 응답(파라미터명 오류 등)을 확인하세요.',
    );
  }
}
