import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/ble/ble_service.dart';
import 'core/geocoding/reverse_geocoding_client.dart';
import 'core/location/location_service.dart';
import 'core/routing/tmap_route_client.dart';
import 'domain/session/trip_state.dart';
import 'presentation/home/home_screen.dart';

/// 빌드/실행 시 `--dart-define=TMAP_APP_KEY=xxx`로 주입.
/// 비어있으면 Mock 클라이언트들로 동작 — TMAP 키 없이도 Command Engine·BLE
/// 파이프라인 전체를 검증할 수 있다.
const _tmapAppKey = String.fromEnvironment('TMAP_APP_KEY');

void main() {
  final locationService = LocationService();
  final bleService = GloveBleService();
  final routeClient = _tmapAppKey.isEmpty
      ? MockRouteClient()
      : TmapRouteClient(appKey: _tmapAppKey);
  final geocodingClient = _tmapAppKey.isEmpty
      ? MockReverseGeocodingClient()
      : TmapReverseGeocodingClient(appKey: _tmapAppKey);

  runApp(MyApp(
    locationService: locationService,
    bleService: bleService,
    routeClient: routeClient,
    geocodingClient: geocodingClient,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.locationService,
    required this.bleService,
    required this.routeClient,
    required this.geocodingClient,
  });

  final LocationService locationService;
  final GloveBleService bleService;
  final RouteClient routeClient;
  final ReverseGeocodingClient geocodingClient;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LocationService>.value(value: locationService),
        Provider<GloveBleService>.value(value: bleService),
        Provider<RouteClient>.value(value: routeClient),
        Provider<ReverseGeocodingClient>.value(value: geocodingClient),
        ChangeNotifierProvider<TripSession>(
          create: (_) => TripSession(
            routeClient: routeClient,
            locationService: locationService,
            bleService: bleService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Assistive Mobility',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}
