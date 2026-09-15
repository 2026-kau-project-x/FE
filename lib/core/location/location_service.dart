import 'package:geolocator/geolocator.dart';

import '../routing/route_models.dart';

/// GPS 현재 위치 획득 및 스트림. (FE-1)
class LocationService {
  /// 위치 권한 확인/요청. 거부되면 false.
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

  /// 현재 위치 단발 조회. GPS가 일시적으로 위치를 못 잡으면(예: kCLErrorLocationUnknown)
  /// 곧바로 실패시키지 않고, 캐시된 마지막 위치가 있으면 그걸로 대체한다 — "출발"
  /// 버튼을 눌렀는데 순간적인 GPS 글리치로 아예 시작을 못 하는 상황을 막기 위함.
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
        // 마지막 위치 조회 자체가 지원되지 않거나 실패하면 원래 에러를 그대로 던진다.
      }
      rethrow;
    }
  }

  /// 보행 중 실시간 위치 갱신 스트림. 5m 이동마다 업데이트.
  Stream<GeoPoint> watchLocation() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    return Geolocator.getPositionStream(locationSettings: settings)
        .map((p) => GeoPoint(p.latitude, p.longitude));
  }
}
