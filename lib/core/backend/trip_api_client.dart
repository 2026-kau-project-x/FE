import 'package:dio/dio.dart';

import '../routing/route_models.dart';

/// BE(FastAPI, BE 리포)의 이동(Trip) API와 통신하는 클라이언트.
///
/// [이 파일이 앱에서 하는 역할]
/// Phase 1 앱은 TMAP을 직접 불러서 혼자 안내하지만, 서버(BE)도 "지금 이 사용자가
/// 어떤 상태(걷는 중/대기/합류)인지" 알아야 Phase 4에서 운전자 앱·이동지원차량
/// 배차·KPI 대시보드를 붙일 수 있다. 그래서 앱의 상태 변화를 BE에 "보고"한다.
/// 이 보고가 실패해도 장갑 안내에는 아무 영향이 없어야 한다(안전 우선) —
/// 실패 처리는 domain/session/backend_trip_sync.dart 가 맡는다.
///
/// BE 계약 (BE/README.md):
/// - POST  /api/v1/trips               → 이동 생성, 응답의 id 를 이후 호출에 사용
/// - PATCH /api/v1/trips/{id}/status   → 상태 전이 (허용 안 되는 전이는 409)
abstract class TripApiClient {
  /// 이동을 만들고 BE가 발급한 trip id 를 돌려준다.
  Future<int> createTrip({
    required GeoPoint origin,
    required GeoPoint destination,
    String? destinationName,
  });

  Future<void> updateStatus(int tripId, BackendTripStatus status);
}

/// BE `TripStatus`(app/services/trip_state.py)와 1:1 대응하는 값.
/// REQUESTED 는 생성 시 BE가 자동으로 넣으므로 앱이 보낼 일이 없어 뺐다.
///
/// [공부 포인트 — enhanced enum] Dart 2.17부터 enum 도 필드·생성자를 가질 수 있다.
/// 각 값에 서버로 보낼 문자열(wire)을 붙여두면, 화면/로직 코드에서는 오타 걱정 없는
/// enum 을 쓰고 직렬화할 때만 문자열로 바꾸면 된다.
enum BackendTripStatus {
  walking('WALKING'),
  waiting('WAITING'),
  rendezvous('RENDEZVOUS'),
  completed('COMPLETED'),
  cancelled('CANCELLED');

  const BackendTripStatus(this.wire);
  final String wire;
}

/// dio 로 실제 BE를 호출하는 구현체.
///
/// [baseUrl 예시]
/// - 웹(Chrome)·Windows 데스크톱: http://localhost:8000
/// - Android 에뮬레이터: http://10.0.2.2:8000 (에뮬레이터 안의 localhost 는 에뮬레이터 자신이다)
/// - 실기기: 같은 Wi-Fi 의 PC IP (예: http://192.168.0.10:8000)
class HttpTripApiClient implements TripApiClient {
  HttpTripApiClient({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              // 서버가 느리거나 꺼져 있을 때 오래 붙잡혀 있지 않도록 짧게 잡는다
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 5),
            ));

  final Dio _dio;

  @override
  Future<int> createTrip({
    required GeoPoint origin,
    required GeoPoint destination,
    String? destinationName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/trips',
      data: {
        'origin': {'lat': origin.lat, 'lng': origin.lng},
        'destination': {'lat': destination.lat, 'lng': destination.lng},
        'destination_name': destinationName,
      },
    );
    return (response.data!['id'] as num).toInt();
  }

  @override
  Future<void> updateStatus(int tripId, BackendTripStatus status) async {
    await _dio.patch<void>(
      '/api/v1/trips/$tripId/status',
      data: {'status': status.wire},
    );
  }
}
