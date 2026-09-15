import 'package:flutter_test/flutter_test.dart';

import 'package:mobility_assist_app/core/ble/ble_service.dart';
import 'package:mobility_assist_app/core/geocoding/reverse_geocoding_client.dart';
import 'package:mobility_assist_app/core/location/location_service.dart';
import 'package:mobility_assist_app/core/routing/tmap_route_client.dart';
import 'package:mobility_assist_app/main.dart';

void main() {
  testWidgets('홈 화면이 목적지 입력 폼과 함께 뜬다', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(
      locationService: LocationService(),
      bleService: GloveBleService(),
      routeClient: MockRouteClient(),
      geocodingClient: MockReverseGeocodingClient(),
    ));

    expect(find.text('출발'), findsOneWidget);
    expect(find.text('장갑 연결 안 됨'), findsOneWidget);
    expect(find.text('지도를 탭해서 목적지를 선택하세요'), findsOneWidget);
  });
}
