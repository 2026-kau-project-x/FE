import '../../core/routing/route_models.dart';
import 'navigation_command.dart';

/// 현재 위치 + 경로를 받아 다음에 내려줄 [NavigationCommand]를 산출한다. (FE-4)
///
/// TMAP이 내려주는 turnType을 그대로 신뢰한다 (좌표 각도 재계산 방식은 보도의
/// 자연스러운 곡률까지 회전으로 오인식해 실제 응답으로 폐기했다).
class CommandEngine {
  CommandEngine(this.route);

  final WalkingRoute route;
  int _nextTurnIndex = 0;

  static const double arrivalThresholdM = 15;
  static const double turnLookaheadM = 15;

  /// 다음 명령 산출. 턴포인트에 근접해 명령을 방출하면 내부적으로 다음 턴포인트로 진행한다.
  NavigationCommand evaluate(GeoPoint current) {
    if (current.distanceTo(route.destination) <= arrivalThresholdM) {
      return NavigationCommand.arrived;
    }

    if (_nextTurnIndex >= route.turnPoints.length) {
      return NavigationCommand.straight;
    }

    final turn = route.turnPoints[_nextTurnIndex];
    final distanceToTurn = current.distanceTo(turn.location);

    if (distanceToTurn <= turnLookaheadM) {
      final command = _fromTurnType(turn.turnType);
      _nextTurnIndex++;
      return command;
    }

    return NavigationCommand.straight;
  }

  /// 경로 재탐색 후 턴포인트 진행 상태를 초기화한다.
  void reset() => _nextTurnIndex = 0;

  /// TMAP turnType → 하드웨어 7종 Navigation Command 매핑.
  ///
  /// 11(직진)/13(우회전)/211~213(횡단보도)은 실제 응답으로 검증됨(tool/verify_tmap_route.dart).
  /// 12(좌회전)·16~19(대각선/사잇길 계열)는 이번 테스트 경로에 해당 케이스가 없어
  /// 공식 문서 기준으로만 매핑했다 — 실제 좌회전·사잇길이 있는 경로로 한 번 더
  /// 검증 필요. 횡단보도·육교·계단 등 시설 안내(211~219)는 하드웨어 7종에 대응
  /// 명령이 없어 우선 직진으로 취급한다 (팀 논의 필요).
  static NavigationCommand _fromTurnType(int turnType) {
    switch (turnType) {
      case 12:
        return NavigationCommand.turnLeft;
      case 13:
        return NavigationCommand.turnRight;
      case 16:
      case 17:
        return NavigationCommand.altTurnLeft;
      case 18:
      case 19:
        return NavigationCommand.altTurnRight;
      default:
        return NavigationCommand.straight;
    }
  }
}
