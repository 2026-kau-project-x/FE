import '../../core/routing/route_models.dart';
import 'navigation_command.dart';

/// GPS 위치와 경로 정보를 받아서 "지금 장갑에 어떤 명령을 보내야 하는가"를
/// 결정하는 핵심 로직. (FE-4)
///
/// [이 클래스가 하는 일 한 줄 요약]
/// "현재 내 위치가 다음 회전 지점 근처인가?" 를 계속 확인하다가, 근처에
/// 도달하면 그 지점의 turnType을 NavigationCommand로 변환해서 한 번 방출하고
/// 다음 회전 지점으로 넘어간다. 회전 지점 사이에 있을 땐 계속 "직진"을 낸다.
///
/// [설계 원칙] TMAP이 내려주는 turnType을 그대로 신뢰한다. 이전에는 polyline
/// 좌표의 진입/이탈 각도를 직접 계산해서 회전 여부를 판단했는데, 실제 응답으로
/// 검증해보니 보도의 자연스러운 곡률까지 회전으로 오인식하는 문제가 있어서
/// (오탐지 20개 vs 진짜 11개) 그 방식은 폐기했다. 지금은 각도 계산이 아예 없다.
class CommandEngine {
  CommandEngine(this.route);

  final WalkingRoute route;

  /// 다음에 통과해야 할 turnPoint의 인덱스. evaluate()가 호출될 때마다 위치를
  /// 확인하고, 그 turnPoint에 충분히 가까워지면 이 값을 1 증가시켜 다음
  /// turnPoint로 넘어간다. 즉 이 클래스는 내부에 "지금 몇 번째 회전 지점을
  /// 향해 가고 있는가"라는 상태(state)를 갖고 있는 상태 기계(state machine)다.
  int _nextTurnIndex = 0;

  /// 목적지로부터 이 거리(m) 이내면 "도착"으로 간주한다.
  static const double arrivalThresholdM = 15;

  /// 다음 turnPoint로부터 이 거리(m) 이내에 들어오면 그 지점의 명령을 방출한다.
  /// 정확히 그 좌표에 도달해야만 반응하면 GPS 오차 때문에 놓칠 수 있어서,
  /// 약간의 반경을 두고 "근처에 왔다"로 판단한다.
  static const double turnLookaheadM = 15;

  /// 다음 명령을 산출한다. TripSession이 GPS 위치가 갱신될 때마다(약 5m 이동
  /// 시) 이 메서드를 호출한다 — 즉 이 메서드는 "한 번 실행하고 끝"이 아니라
  /// 사용자가 걷는 동안 반복 호출되는 함수라는 점이 중요하다.
  NavigationCommand evaluate(GeoPoint current) {
    // 1) 목적지에 충분히 가까우면 다른 판단 없이 바로 "도착"
    if (current.distanceTo(route.destination) <= arrivalThresholdM) {
      return NavigationCommand.arrived;
    }

    // 2) 더 이상 남은 turnPoint가 없다 = 마지막 회전을 이미 지나쳐서 목적지까지
    //    쭉 직진하면 되는 구간
    if (_nextTurnIndex >= route.turnPoints.length) {
      return NavigationCommand.straight;
    }

    final turn = route.turnPoints[_nextTurnIndex];
    final distanceToTurn = current.distanceTo(turn.location);

    // 3) 다음 회전 지점에 충분히 가까워졌다 → 그 지점의 명령을 "한 번" 방출하고
    //    내부 포인터를 다음 turnPoint로 넘긴다. (매 호출마다 같은 명령을
    //    반복해서 방출하지 않도록 _nextTurnIndex를 증가시키는 것이 핵심)
    if (distanceToTurn <= turnLookaheadM) {
      final command = _fromTurnType(turn.turnType);
      _nextTurnIndex++;
      return command;
    }

    // 4) 아직 다음 회전 지점과 멀다 → 계속 직진
    return NavigationCommand.straight;
  }

  /// 경로가 재계산됐을 때(TripSession.reroute) 진행 상태를 처음으로 되돌린다.
  /// 새 경로는 turnPoint 목록도 새로 생기므로, 이전 경로에서 "몇 번째까지
  /// 지나왔는지"는 의미가 없어지기 때문이다.
  void reset() => _nextTurnIndex = 0;

  /// TMAP turnType 코드 → 하드웨어 7종 Navigation Command 매핑표.
  ///
  /// [검증 상태 — 실제 사용 전에 꼭 알아둘 것]
  /// - 11(직진)/13(우회전)/211~213(횡단보도)은 실제 TMAP 응답으로 검증 완료
  ///   (tool/verify_tmap_route.dart 실행 결과 기준).
  /// - 12(좌회전)·16~19(대각선/사잇길 계열)는 테스트했던 경로에 해당 케이스가
  ///   없어서 TMAP 공식 문서만 보고 매핑해뒀다 — 아직 실측 검증 전이라는 뜻.
  ///   실제 좌회전/사잇길이 있는 경로로 한번 더 테스트해봐야 한다.
  /// - 횡단보도·육교·계단 같은 시설 안내(211~219)는 장갑의 7종 명령 중에
  ///   대응하는 게 없어서 일단 전부 "직진"으로 뭉뚱그렸다. 이건 나중에
  ///   팀 논의가 필요한 부분으로 남겨둔 것이다 (예: 횡단보도 전용 진동
  ///   패턴을 새로 만들지 여부).
  ///
  /// [공부 포인트] Dart의 switch문에서 여러 case를 연달아 쓰면(break 없이
  /// 바로 다음 return으로 이어지면) "이 여러 값들은 같은 동작을 한다"는
  /// 뜻이다. 예를 들어 16과 17 case는 둘 다 altTurnLeft를 반환한다.
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
