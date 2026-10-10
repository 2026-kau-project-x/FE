// 실제 BE 서버와 HttpTripApiClient 의 계약(요청·응답 형태)이 맞는지 확인하는 1회성 CLI 스크립트.
//
// 실행 전: BE 리포에서 서버를 띄워둘 것 (BE/README.md 참고)
//   alembic upgrade head && uvicorn app.main:app --port 8000
//
//   dart run tool/verify_be_trip_flow.dart                         # env.json 의 BE_BASE_URL, 없으면 localhost:8000
//   dart run tool/verify_be_trip_flow.dart http://10.0.2.2:8000    # 주소 직접 지정
//
// 앱이 실제로 보내는 순서(생성 → WALKING → WAITING → WALKING → RENDEZVOUS → COMPLETED)를
// 그대로 흉내 내고, 마지막에 허용되지 않는 전이가 409 로 거절되는지도 본다.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobility_assist_app/core/backend/trip_api_client.dart';
import 'package:mobility_assist_app/core/routing/route_models.dart';

String _baseUrl(List<String> args) {
  if (args.isNotEmpty) return args.first;
  final file = File('env.json');
  if (file.existsSync()) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final url = json['BE_BASE_URL'] as String?;
    if (url != null && url.isNotEmpty) return url;
  }
  return 'http://localhost:8000';
}

void main(List<String> args) async {
  final baseUrl = _baseUrl(args);
  print('BE: $baseUrl');
  final api = HttpTripApiClient(baseUrl: baseUrl);

  try {
    final id = await api.createTrip(
      origin: const GeoPoint(37.5500, 126.9900),
      destination: const GeoPoint(37.5520, 126.9900),
      destinationName: '검증 스크립트 목적지',
    );
    print('이동 생성: id=$id');

    for (final s in [
      BackendTripStatus.walking,
      BackendTripStatus.waiting,
      BackendTripStatus.walking,
      BackendTripStatus.rendezvous,
      BackendTripStatus.completed,
    ]) {
      await api.updateStatus(id, s);
      print('  → ${s.wire} OK');
    }

    try {
      await api.updateStatus(id, BackendTripStatus.walking); // COMPLETED → WALKING 은 금지
      print('실패: 잘못된 전이가 허용됐습니다');
      exitCode = 1;
    } on DioException catch (e) {
      print('잘못된 전이 거절 확인: HTTP ${e.response?.statusCode} (409 기대)');
      if (e.response?.statusCode != 409) exitCode = 1;
    }
  } on DioException catch (e) {
    print('BE 호출 실패: ${e.type} ${e.message ?? ''} — 서버가 떠 있는지 확인하세요.');
    exitCode = 1;
  }
}
