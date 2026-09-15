import 'package:flutter_test/flutter_test.dart';
import 'package:mobility_assist_app/core/routing/route_models.dart';
import 'package:mobility_assist_app/domain/navigation/command_engine.dart';
import 'package:mobility_assist_app/domain/navigation/navigation_command.dart';
import 'package:mobility_assist_app/domain/navigation/off_route_detector.dart';

void main() {
  group('CommandEngine', () {
    test('턴포인트에서 먼 위치에서는 직진을 반환한다', () {
      final route = WalkingRoute(
        points: [const GeoPoint(37.0, 127.0), const GeoPoint(37.01, 127.01)],
        turnPoints: [
          const TurnPoint(location: GeoPoint(37.005, 127.005), turnType: 13),
        ],
      );
      final engine = CommandEngine(route);
      final command = engine.evaluate(const GeoPoint(37.0, 127.0));
      expect(command, NavigationCommand.straight);
    });

    test('turnType 13(우회전)이면 우회전으로 분류한다', () {
      final turnLocation = const GeoPoint(37.0001, 127.0001);
      final route = WalkingRoute(
        points: [const GeoPoint(37.0, 127.0), const GeoPoint(37.001, 127.001)],
        turnPoints: [TurnPoint(location: turnLocation, turnType: 13)],
      );
      final engine = CommandEngine(route);
      final command = engine.evaluate(turnLocation);
      expect(command, NavigationCommand.turnRight);
    });

    test('turnType 16(사잇길 계열)이면 사잇길좌회전으로 분류한다', () {
      final turnLocation = const GeoPoint(37.0001, 127.0001);
      final route = WalkingRoute(
        points: [const GeoPoint(37.0, 127.0), const GeoPoint(37.001, 127.001)],
        turnPoints: [TurnPoint(location: turnLocation, turnType: 16)],
      );
      final engine = CommandEngine(route);
      final command = engine.evaluate(turnLocation);
      expect(command, NavigationCommand.altTurnLeft);
    });

    test('turnType 211(횡단보도 등 시설 안내)은 직진으로 취급한다', () {
      final turnLocation = const GeoPoint(37.0001, 127.0001);
      final route = WalkingRoute(
        points: [const GeoPoint(37.0, 127.0), const GeoPoint(37.001, 127.001)],
        turnPoints: [TurnPoint(location: turnLocation, turnType: 211)],
      );
      final engine = CommandEngine(route);
      final command = engine.evaluate(turnLocation);
      expect(command, NavigationCommand.straight);
    });

    test('목적지 근처에서는 도착을 반환한다', () {
      final destination = const GeoPoint(37.0, 127.0);
      final route = WalkingRoute(points: [destination], turnPoints: const []);
      final engine = CommandEngine(route);
      final command = engine.evaluate(destination);
      expect(command, NavigationCommand.arrived);
    });
  });

  group('OffRouteDetector', () {
    test('경로 위에 있으면 이탈로 보지 않는다', () {
      const detector = OffRouteDetector(thresholdMeters: 20);
      final route = WalkingRoute(
        points: [const GeoPoint(37.0, 127.0), const GeoPoint(37.01, 127.0)],
        turnPoints: const [],
      );
      expect(detector.isOffRoute(const GeoPoint(37.005, 127.0), route), isFalse);
    });

    test('경로에서 임계값 이상 벗어나면 이탈로 판단한다', () {
      const detector = OffRouteDetector(thresholdMeters: 20);
      final route = WalkingRoute(
        points: [const GeoPoint(37.0, 127.0), const GeoPoint(37.01, 127.0)],
        turnPoints: const [],
      );
      // 위경도 0.001도 ≈ 111m 동쪽으로 이탈
      expect(detector.isOffRoute(const GeoPoint(37.005, 127.001), route), isTrue);
    });
  });
}
