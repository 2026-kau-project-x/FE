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

/// 목적지 입력 화면. (FE-1, FE-2)
///
/// 지도를 탭해 목적지를 찍으면 그 자리에서 TMAP 보행경로를 미리 불러와 폴리라인·
/// 거리·소요시간을 보여준다. 실제 턴바이턴 안내(라이브 내비게이션 지도)는 범위 밖 —
/// 이동 중에는 장갑 햅틱 + [NavigatingScreen]의 단순 명령 표시로 충분하다는 전제.
/// 주소 검색 UI는 이후 확장 지점.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _fallbackCenter = LatLng(37.5665, 126.9780); // 서울시청 — GPS 확보 전 기본 중심

  final _mapController = MapController();

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

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    final location = context.read<LocationService>();
    try {
      final hasPermission = await location.ensurePermission();
      if (!hasPermission) {
        setState(() => _locationError = '위치 권한이 필요합니다.');
        return;
      }
      final point = await location.getCurrentLocation();
      final latLng = LatLng(point.lat, point.lng);
      setState(() {
        _currentLocation = latLng;
        _locationError = null;
      });
      _mapController.move(latLng, 16);
    } catch (e) {
      setState(() => _locationError = '현재 위치를 가져오지 못했습니다.');
    }
  }

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
    final futures = <Future<void>>[_fetchAddress(point)];
    if (origin != null) {
      futures.add(_fetchPreviewRoute(origin, point));
    } else {
      setState(() => _routeError = '현재 위치를 아직 확인하지 못해 경로를 미리 볼 수 없습니다.');
    }
    await Future.wait(futures);
  }

  Future<void> _fetchAddress(LatLng point) async {
    try {
      final geocoder = context.read<ReverseGeocodingClient>();
      final address = await geocoder.reverseGeocode(lat: point.latitude, lng: point.longitude);
      if (!mounted) return;
      setState(() => _destinationAddress = address);
    } catch (e) {
      if (!mounted) return;
      setState(() => _destinationAddress = null); // 실패 시 좌표로 폴백 표시
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

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

  Future<void> _startTrip() async {
    final destination = _destination;
    final route = _previewRoute;
    if (destination == null || route == null) return;

    setState(() {
      _tripError = null;
      _starting = true;
    });

    final session = context.read<TripSession>();
    try {
      final current = _currentLocation;
      await session.startTrip(
        GeoPoint(destination.latitude, destination.longitude),
        previewRoute: route,
        fallbackOrigin: current == null ? null : GeoPoint(current.latitude, current.longitude),
      );
      if (!mounted) return;
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
    final ble = context.watch<GloveBleService>();
    final theme = Theme.of(context);
    final routePoints = _previewRoute?.points
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? _fallbackCenter,
              initialZoom: 16,
              onTap: (_, point) => _onMapTapped(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'mobility_assist_app',
              ),
              if (routePoints != null && routePoints.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: routePoints, strokeWidth: 8, color: Colors.white),
                  Polyline(
                    points: routePoints,
                    strokeWidth: 5,
                    color: theme.colorScheme.primary,
                  ),
                ]),
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
                    alignment: Alignment.topCenter,
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
          Positioned(
            right: 12,
            bottom: 232,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: '현재 위치로 이동',
              onPressed: _currentLocation == null
                  ? null
                  : () => _mapController.move(_currentLocation!, 16),
              child: const Icon(Icons.my_location),
            ),
          ),
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
              onStart: _previewRoute == null || _starting ? null : _startTrip,
            ),
          ),
        ],
      ),
    );
  }
}

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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, this.isError = false});

  final IconData icon;
  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red.shade700 : Colors.blueGrey.shade700;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              const SizedBox(height: 8),
              Text(tripError!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                StreamBuilder<GloveConnectionState>(
                  stream: bleState.connectionState,
                  initialData: GloveConnectionState.disconnected,
                  builder: (context, snapshot) => GloveStatusChip(
                    state: snapshot.data ?? GloveConnectionState.disconnected,
                  ),
                ),
                const Spacer(),
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
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onStart,
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
              Text(
                loadingAddress
                    ? '주소 확인 중…'
                    : destinationAddress ??
                        '${destination!.latitude.toStringAsFixed(5)}, '
                            '${destination!.longitude.toStringAsFixed(5)}',
                style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteLine(TextTheme textTheme) {
    if (loadingRoute) {
      return const Text('경로 확인 중…');
    }
    if (routeError != null) {
      return Text(routeError!, style: const TextStyle(color: Colors.red));
    }

    final r = route;
    if (r == null) return const SizedBox.shrink();

    final minutes = r.totalTimeSeconds != null ? (r.totalTimeSeconds! / 60).ceil() : null;
    final meters = r.totalDistanceMeters?.round();

    return Text(
      minutes != null && meters != null ? '도보 약 $minutes분 · ${meters}m' : '도보 경로',
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
