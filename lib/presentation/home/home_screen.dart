import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/ble/ble_connection_state.dart';
import '../../core/ble/ble_service.dart';
import '../../core/geocoding/reverse_geocoding_client.dart';
import '../../core/location/location_service.dart';
import '../../core/routing/route_models.dart';
import '../../core/routing/tmap_route_client.dart';
import '../../domain/session/trip_state.dart';
import '../navigating/navigating_screen.dart';
import '../widgets/glove_status_chip.dart';

/// 목적지 입력(온보딩) 화면. (FE-1, FE-2)
///
/// 지도를 탭해 목적지를 찍으면 그 자리에서 TMAP 보행경로를 미리 불러와 폴리라인·
/// 거리·시간·주소를 보여준다. 실제 턴바이턴 안내(라이브 내비게이션 지도)는 범위 밖 —
/// 이동 중에는 장갑 햅틱 + [NavigatingScreen]의 단순 명령 표시로 충분하다는 전제.
/// 주소 검색 UI는 이후 확장 지점.
///
/// [공부 포인트 — StatefulWidget]
/// Flutter 위젯은 크게 StatelessWidget(한 번 그려지면 안 바뀌는 UI, 예:
/// GloveStatusChip)과 StatefulWidget(시간이 지나면서 내부 값이 바뀌고 그때마다
/// 다시 그려져야 하는 UI)으로 나뉜다. 이 화면은 "지도 위치, 목적지, 로딩 상태"
/// 등이 사용자 조작에 따라 계속 바뀌므로 StatefulWidget이다. 실제 상태와
/// 로직은 아래 `_HomeScreenState` 클래스에 들어있다 — HomeScreen 자체는
/// "이 상태 클래스를 만들어달라"는 껍데기 역할만 한다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _fallbackCenter = LatLng(37.5665, 126.9780); // 서울시청 — GPS 확보 전 기본 중심

  // 지도를 코드에서 직접 제어(특정 좌표로 이동시키기 등)하기 위한 컨트롤러.
  final _mapController = MapController();

  // 화면에 필요한 모든 상태값. setState()를 호출해야만 화면이 실제로
  // 다시 그려진다는 점이 StatefulWidget의 핵심 규칙이다 — 아래 이 값들을
  // 그냥 대입만 하면(setState 없이) 값은 바뀌지만 화면엔 반영되지 않는다.
  LatLng? _currentLocation;
  String? _locationError;

  LatLng? _destination;
  WalkingRoute? _previewRoute;
  bool _loadingRoute = false;
  String? _routeError;

  String? _destinationAddress;
  bool _loadingAddress = false;

  String? _tripError;
  bool _starting = false;

  /// [공부 포인트 — initState] StatefulWidget이 화면에 처음 삽입될 때 딱
  /// 한 번 호출되는 생명주기(lifecycle) 메서드. "화면이 뜨자마자 해야 할 일"
  /// (여기서는 현재 위치 조회 시작)을 여기에 둔다. build()는 화면이 다시
  /// 그려질 때마다 반복 호출되므로 여기에 이런 일회성 초기화 로직을 두면 안 된다.
  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  /// 현재 위치를 조회해서 지도 중심을 그쪽으로 옮긴다.
  Future<void> _loadCurrentLocation() async {
    // context.read<T>(): Provider에 등록된 서비스를 "지금 이 순간" 한 번
    // 꺼내오는 것. context.watch와 달리 값이 바뀌어도 이 위젯을 다시
    // 그리게 만들지 않는다 — 여기서는 함수 호출 시점에 한 번만 서비스가
    // 필요하므로 watch가 아니라 read를 쓴다.
    final location = context.read<LocationService>();
    try {
      final hasPermission = await location.ensurePermission();
      if (!hasPermission) {
        setState(() => _locationError = '위치 권한이 필요합니다.');
        return;
      }
      final point = await location.getCurrentLocation();
      final latLng = LatLng(point.lat, point.lng); // 우리 GeoPoint → flutter_map의 LatLng로 변환
      setState(() {
        _currentLocation = latLng;
        _locationError = null;
      });
      _mapController.move(latLng, 16); // 지도 중심을 현재 위치로, 줌 레벨 16으로 이동
    } catch (e) {
      setState(() => _locationError = '현재 위치를 가져오지 못했습니다.');
    }
  }

  /// 지도를 탭했을 때 호출된다 — 그 지점을 목적지로 정하고, 주소와 경로
  /// 미리보기를 동시에 가져오기 시작한다.
  Future<void> _onMapTapped(LatLng point) async {
    final origin = _currentLocation;
    setState(() {
      _destination = point;
      _previewRoute = null;
      _routeError = null;
      _tripError = null;
      _destinationAddress = null;
      _loadingAddress = true;
      _loadingRoute = origin != null;
    });

    // 주소 조회와 경로 조회는 서로 독립적이라 동시에 진행한다.
    // [공부 포인트] Future.wait는 여러 비동기 작업을 "동시에 시작해서 모두
    // 끝날 때까지 기다리는" 함수다. 만약 여기서 await _fetchAddress(...) 다음에
    // await _fetchPreviewRoute(...)를 순서대로 했다면 둘의 소요 시간이
    // 합산되지만(예: 각 500ms면 총 1초), Future.wait로 동시에 돌리면 둘 중
    // 오래 걸리는 것 기준(500ms)으로 끝난다.
    final futures = <Future<void>>[_fetchAddress(point)];
    if (origin != null) {
      futures.add(_fetchPreviewRoute(origin, point));
    } else {
      setState(() => _routeError = '현재 위치를 아직 확인하지 못해 경로를 미리 볼 수 없습니다.');
    }
    await Future.wait(futures);
  }

  /// 좌표 → 주소 변환을 요청하고 결과를 상태에 반영한다.
  Future<void> _fetchAddress(LatLng point) async {
    try {
      final geocoder = context.read<ReverseGeocodingClient>();
      final address = await geocoder.reverseGeocode(lat: point.latitude, lng: point.longitude);
      // [공부 포인트 — mounted 체크] await 이후에는 그 사이에 사용자가
      // 이 화면을 나가버렸을 수도 있다(위젯이 "unmount"됨). 이미 사라진
      // 위젯에 setState를 호출하면 에러가 난다. 그래서 비동기 작업 뒤에
      // setState를 부르기 전엔 항상 `if (!mounted) return;`으로 먼저 확인한다.
      if (!mounted) return;
      setState(() => _destinationAddress = address);
    } catch (e) {
      if (!mounted) return;
      setState(() => _destinationAddress = null); // 실패 시 좌표로 폴백 표시
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  /// 경로 미리보기를 요청하고 결과를 상태에 반영한다.
  Future<void> _fetchPreviewRoute(LatLng origin, LatLng destination) async {
    try {
      final routeClient = context.read<RouteClient>();
      final route = await routeClient.fetchWalkingRoute(
        origin: GeoPoint(origin.latitude, origin.longitude),
        destination: GeoPoint(destination.latitude, destination.longitude),
      );
      if (!mounted) return;
      setState(() {
        _previewRoute = route;
        _loadingRoute = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routeError = '경로를 불러오지 못했습니다.';
        _loadingRoute = false;
      });
    }
  }

  /// "연결하기" 버튼 핸들러. 실패하면 화면 하단에 스낵바(SnackBar)로 알린다.
  Future<void> _connectGlove() async {
    final ble = context.read<GloveBleService>();
    try {
      await ble.connect();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('장갑 연결 실패: $e')),
      );
    }
  }

  /// "출발" 버튼 핸들러. TripSession.startTrip을 호출해서 실제 내비게이션
  /// 루프를 시작시키고, 성공하면 NavigatingScreen으로 화면을 전환한다.
  Future<void> _startTrip() async {
    final destination = _destination;
    final route = _previewRoute;
    if (destination == null || route == null) return; // 방어적 가드 — 버튼이 비활성화되어 있어 사실상 도달 안 함

    setState(() {
      _tripError = null;
      _starting = true;
    });

    final session = context.read<TripSession>();
    try {
      final current = _currentLocation;
      await session.startTrip(
        GeoPoint(destination.latitude, destination.longitude),
        previewRoute: route, // 이미 받아둔 경로를 재사용 (TMAP 중복 호출 방지)
        fallbackOrigin: current == null ? null : GeoPoint(current.latitude, current.longitude),
      );
      if (!mounted) return;
      // Navigator.push: 새 화면을 스택에 쌓아 올린다(뒤로가기 하면 이 화면으로 돌아옴).
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NavigatingScreen()),
      );
    } catch (e) {
      setState(() => _tripError = '$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // context.watch<T>(): read와 달리 이 서비스(T)의 상태가 바뀔 때마다
    // 이 build()가 다시 호출되도록 "구독"한다. GloveBleService의
    // connectionState 자체는 스트림이라 여기서 watch할 필요는 없지만,
    // 이 위젯 트리 안에서 GloveBleService 인스턴스를 계속 참조하기 위해
    // 받아온다 (isConnected 같은 동기 값 확인용).
    final ble = context.watch<GloveBleService>();
    final theme = Theme.of(context);
    // 우리 도메인 모델(GeoPoint)을 flutter_map이 이해하는 LatLng 리스트로 변환.
    final routePoints = _previewRoute?.points
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);

    return Scaffold(
      // [공부 포인트 — Stack] 지도를 화면 전체에 깔고, 그 위에 상태 pill·
      // 버튼·하단 패널을 "레이어처럼" 겹쳐 쌓는다. Stack의 자식들은 기본적으로
      // 왼쪽 위 기준으로 겹쳐지고, Positioned로 감싸면 특정 위치에 고정할 수 있다.
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? _fallbackCenter,
              initialZoom: 16,
              onTap: (_, point) => _onMapTapped(point), // 지도 탭 이벤트 핸들러 연결
            ),
            children: [
              // 실제 지도 이미지(타일)를 그려주는 레이어. OpenStreetMap은
              // 무료 공개 타일 서버라 별도 API 키 없이 바로 쓸 수 있다.
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'mobility_assist_app',
              ),
              // 경로선을 그리는 레이어. 흰색 굵은 선을 먼저 깔고 그 위에
              // 얇은 색선을 겹쳐서 그리면 지도 배경과 대비되는 "테두리 효과"가 난다.
              if (routePoints != null && routePoints.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: routePoints, strokeWidth: 8, color: Colors.white),
                  Polyline(
                    points: routePoints,
                    strokeWidth: 5,
                    color: theme.colorScheme.primary,
                  ),
                ]),
              // 마커(핀) 레이어: 현재 위치는 파란 점, 목적지는 빨간 핀 아이콘.
              MarkerLayer(markers: [
                if (_currentLocation != null)
                  Marker(
                    point: _currentLocation!,
                    width: 24,
                    height: 24,
                    child: const _CurrentLocationDot(),
                  ),
                if (_destination != null)
                  Marker(
                    point: _destination!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter, // 핀의 "뾰족한 끝"이 실제 좌표를 가리키게
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.redAccent,
                      size: 40,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
                    ),
                  ),
              ]),
            ],
          ),
          // 지도 위 왼쪽 상단에 떠 있는 "현재 위치 확인됨" 같은 상태 표시 pill.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _StatusPill(
                    icon: Icons.my_location,
                    label: _currentLocation != null
                        ? '현재 위치 확인됨'
                        : (_locationError ?? '현재 위치 확인 중…'),
                    isError: _locationError != null,
                  ),
                ],
              ),
            ),
          ),
          // 지도를 현재 위치로 다시 이동시키는 플로팅 버튼.
          Positioned(
            right: 12,
            bottom: 232, // 하단 패널(_RoutePanel)에 가려지지 않도록 그 위쪽에 배치
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: '현재 위치로 이동',
              onPressed: _currentLocation == null
                  ? null // 아직 위치를 모르면 버튼 비활성화(회색 처리)
                  : () => _mapController.move(_currentLocation!, 16),
              child: const Icon(Icons.my_location),
            ),
          ),
          // 화면 하단에 고정된 정보/액션 패널.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _RoutePanel(
              destination: _destination,
              destinationAddress: _destinationAddress,
              loadingAddress: _loadingAddress,
              route: _previewRoute,
              loadingRoute: _loadingRoute,
              routeError: _routeError,
              tripError: _tripError,
              starting: _starting,
              bleState: ble,
              onConnectGlove: _connectGlove,
              // 목적지/경로가 아직 없거나 출발 처리 중이면 버튼을 비활성화(null 전달).
              onStart: _previewRoute == null || _starting ? null : _startTrip,
            ),
          ),
        ],
      ),
    );
  }
}

/// 현재 위치를 나타내는 파란 점 마커. 지도 앱에서 흔히 보는 "나침반 점" 스타일.
class _CurrentLocationDot extends StatelessWidget {
  const _CurrentLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
    );
  }
}

/// 지도 위에 떠 있는 둥근 알약(pill) 모양의 작은 상태 표시 위젯.
/// GloveStatusChip과 비슷하지만 이건 지도 오버레이 전용이라 Material로
/// 그림자(elevation)를 준다는 점이 다르다.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, this.isError = false});

  final IconData icon;
  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red.shade700 : Colors.blueGrey.shade700;
    return Material(
      elevation: 2, // 살짝 그림자를 줘서 지도 위에 "떠 있는" 느낌을 준다
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min, // Row가 화면 폭 전체가 아니라 내용물 크기만큼만 차지
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// 화면 하단에 고정된 카드형 패널 — 목적지/경로 요약, 장갑 연결 상태,
/// "출발" 버튼을 담는다. StatelessWidget인 이유: 이 위젯 자체는 상태를
/// 갖지 않고, 부모(_HomeScreenState)로부터 모든 값을 파라미터로만 받아서
/// 그리기만 한다 — "바보 위젯(dumb widget)" 패턴이라고도 부른다.
class _RoutePanel extends StatelessWidget {
  const _RoutePanel({
    required this.destination,
    required this.destinationAddress,
    required this.loadingAddress,
    required this.route,
    required this.loadingRoute,
    required this.routeError,
    required this.tripError,
    required this.starting,
    required this.bleState,
    required this.onConnectGlove,
    required this.onStart,
  });

  final LatLng? destination;
  final String? destinationAddress;
  final bool loadingAddress;
  final WalkingRoute? route;
  final bool loadingRoute;
  final String? routeError;
  final String? tripError;
  final bool starting;
  final GloveBleService bleState;
  final VoidCallback onConnectGlove;
  final VoidCallback? onStart; // null이면 버튼이 자동으로 비활성화된다 (FilledButton의 동작)

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), // 위쪽 모서리만 둥글게
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 바텀시트 느낌을 주는 순수 장식용 "손잡이" 막대 (실제 드래그 기능은 없음)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _buildSummary(context),
            if (tripError != null) ...[
              // [공부 포인트] `...`(spread 연산자)는 리스트 안에 다른 리스트의
              // 원소들을 그대로 풀어 넣는다. 여기선 `if` 조건과 결합해서
              // "조건이 참일 때만 이 위젯들을 children 리스트에 추가"하는
              // 흔한 Flutter 패턴이다.
              const SizedBox(height: 8),
              Text(tripError!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                // [공부 포인트 — StreamBuilder] 스트림의 최신 값에 따라
                // 자동으로 다시 그려지는 위젯. GloveBleService.connectionState는
                // 스트림이라서, setState를 직접 호출하지 않아도 새 값이 흐를
                // 때마다 이 부분만 알아서 다시 그려진다. initialData는 아직
                // 스트림에서 아무 값도 안 왔을 때(첫 프레임) 쓸 기본값이다.
                StreamBuilder<GloveConnectionState>(
                  stream: bleState.connectionState,
                  initialData: GloveConnectionState.disconnected,
                  builder: (context, snapshot) => GloveStatusChip(
                    state: snapshot.data ?? GloveConnectionState.disconnected,
                  ),
                ),
                const Spacer(), // 남은 공간을 전부 차지해서 다음 위젯을 오른쪽 끝으로 밀어냄
                if (!bleState.isConnected)
                  TextButton.icon(
                    onPressed: onConnectGlove,
                    icon: const Icon(Icons.bluetooth_searching, size: 18),
                    label: const Text('연결하기'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, // 버튼을 패널 전체 너비로 늘림
              height: 52,
              child: FilledButton.icon(
                onPressed: onStart, // null이면 Flutter가 자동으로 버튼을 비활성화한다
                icon: starting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.navigation),
                label: const Text('출발', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 상단 요약 줄: 목적지 미선택 / 로딩 중 / 에러 / 정상 4가지 상태에 따라
  /// 다른 내용을 그린다. 이런 "상태에 따라 분기해서 다른 위젯을 그리는" 패턴이
  /// Flutter UI 코드에서 아주 흔하다.
  Widget _buildSummary(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (destination == null) {
      return Row(
        children: [
          Icon(Icons.touch_app_outlined, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '지도를 탭해서 목적지를 선택하세요',
              style: textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }

    // 목적지는 있지만 경로 상태(로딩중/에러/완료)에 따라 아이콘 색만 바꾼다.
    final IconData icon;
    final Color iconColor;
    if (loadingRoute) {
      icon = Icons.hourglass_top;
      iconColor = Colors.grey.shade500;
    } else if (routeError != null) {
      icon = Icons.error_outline;
      iconColor = Colors.red;
    } else {
      icon = Icons.directions_walk;
      iconColor = Theme.of(context).colorScheme.primary;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRouteLine(textTheme),
              const SizedBox(height: 2),
              // 주소 로딩 중이면 안내 문구, 로딩이 끝났는데 주소를 못 받았으면
              // 좌표 숫자로 폴백해서라도 뭔가는 보여준다 (완전히 빈 화면보다 낫다).
              Text(
                loadingAddress
                    ? '주소 확인 중…'
                    : destinationAddress ??
                        '${destination!.latitude.toStringAsFixed(5)}, '
                            '${destination!.longitude.toStringAsFixed(5)}',
                style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis, // 주소가 길면 "..."으로 자름
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "도보 약 N분 · Nm" 또는 로딩/에러 문구를 그리는 첫 번째 줄.
  Widget _buildRouteLine(TextTheme textTheme) {
    if (loadingRoute) {
      return const Text('경로 확인 중…');
    }
    if (routeError != null) {
      return Text(routeError!, style: const TextStyle(color: Colors.red));
    }

    final r = route;
    if (r == null) return const SizedBox.shrink(); // 아무것도 그리지 않는 빈 위젯

    final minutes = r.totalTimeSeconds != null ? (r.totalTimeSeconds! / 60).ceil() : null;
    final meters = r.totalDistanceMeters?.round();

    return Text(
      minutes != null && meters != null ? '도보 약 $minutes분 · ${meters}m' : '도보 경로',
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
