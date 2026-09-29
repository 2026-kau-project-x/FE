import 'package:geolocator/geolocator.dart';

import '../routing/route_models.dart';

/// 기기 GPS 관련 기능을 한 곳에 모아둔 서비스. (FE-1)
/// `geolocator` 패키지(Flutter에서 위치 정보를 다루는 표준 라이브러리)를
/// 감싸서, 앱의 나머지 코드는 geolocator의 API를 직접 알 필요가 없게 만든다.
class LocationService {
  /// 위치 권한을 확인하고, 아직 물어본 적 없으면 요청까지 한다.
  ///
  /// [공부 포인트] 모바일 OS의 위치 권한은 3단계로 나뉜다: denied(거부/미결정),
  /// deniedForever(영구 거부 — 앱이 다시 물어볼 수 없고 사용자가 설정 앱에서
  /// 직접 켜야 함), whileInUse/always(허용). 여기서는 "거부 상태면 한 번
  /// 요청해보고, 그래도 영구 거부면 포기"라는 흐름을 구현했다. 위치 서비스
  /// 자체(기기의 GPS 기능)가 꺼져있는 경우도 별도로 체크한다 — 권한은
  /// "이 앱이 위치를 봐도 되는가"이고, 위치 서비스는 "기기 자체가 GPS를
  /// 쓸 수 있는 상태인가"라서 서로 다른 문제다.
  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// 현재 위치를 "한 번만" 조회한다 (스트림이 아니라 Future — 즉 결과가
  /// 한 번 오고 끝).
  ///
  /// [실전에서 겪은 문제와 해결] GPS는 가끔 일시적으로 위치를 못 잡는다
  /// (macOS/iOS에서는 kCLErrorLocationUnknown이라는 에러로 나타남 — 특히
  /// 건물 안이거나 막 권한을 허용한 직후에 자주 발생). 처음엔 이걸 처리
  /// 안 해서 "출발" 버튼을 눌렀을 때 이 에러가 그대로 화면에 빨간 글씨로
  /// 튀어나오는 버그가 있었다. 지금은 실패하면 바로 포기하지 않고,
  /// `getLastKnownPosition()`(OS가 캐시해둔 마지막 위치)으로 한 번 더
  /// 시도해본다 — 완전 최신 위치는 아니어도 없는 것보다 낫다는 판단.
  Future<GeoPoint> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return GeoPoint(lastKnown.latitude, lastKnown.longitude);
        }
      } catch (_) {
        // getLastKnownPosition 자체가 플랫폼에 따라 지원되지 않거나(예: 웹)
        // 실패할 수도 있다 — 이 경우엔 폴백을 포기하고 원래 에러를 그대로
        // 던진다(아래 rethrow). 폴백 시도 중 생긴 새 에러로 원래 에러를
        // 덮어버리면 진짜 원인을 알기 어려워지므로, 여기서는 일부러 새
        // 에러를 무시한다.
      }
      rethrow;
    }
  }

  /// 보행 중 위치가 바뀔 때마다 계속 값을 흘려보내는 스트림.
  ///
  /// [공부 포인트] 위의 getCurrentLocation()은 "지금 위치 한 번 줘"라면,
  /// 이건 "위치 바뀔 때마다 나한테 알려줘"다. distanceFilter: 5는 "5m
  /// 이상 움직였을 때만 새 이벤트를 발생시켜라"는 뜻 — 제자리에 서있는데
  /// GPS 잡음으로 미세하게 좌표가 흔들릴 때마다 이벤트가 쏟아지는 걸
  /// 막아준다. TripSession이 이 스트림을 구독(listen)해서 CommandEngine에
  /// 새 위치를 넘기는 방식으로 전체 내비게이션 루프가 돌아간다.
  Stream<GeoPoint> watchLocation() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    return Geolocator.getPositionStream(locationSettings: settings)
        .map((p) => GeoPoint(p.latitude, p.longitude));
  }
}
