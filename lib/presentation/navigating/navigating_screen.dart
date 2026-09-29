import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ble/ble_connection_state.dart';
import '../../core/ble/ble_service.dart';
import '../../domain/navigation/navigation_command.dart';
import '../../domain/session/trip_state.dart';
import '../widgets/glove_status_chip.dart';

/// 보행 안내 화면. 현재 Navigation Command와 장갑 연결상태를 함께 보여준다. (FE-3, FE-8)
///
/// [이 화면의 설계 철학] 여기가 바로 "실제 안내 중" 화면이라 화려한 지도
/// UI가 있을 것 같지만, 일부러 아주 단순하게 만들었다 — 큰 아이콘 하나와
/// 짧은 텍스트뿐이다. 실제 방향 안내는 장갑의 진동(햅틱)으로 전달되고,
/// 화면은 어디까지나 "지금 어떤 명령이 나가고 있는지 눈으로도 확인 가능한"
/// 보조 수단일 뿐이라는 설계 원칙 때문이다.
///
/// [공부 포인트 — StatelessWidget인데 화면이 바뀌는 이유] 이 위젯 자체는
/// StatelessWidget이라 자기 내부에 변하는 값이 없다. 그런데도 화면이
/// 실시간으로 바뀌는 건 `context.watch<TripSession>()` 때문이다 — TripSession이
/// notifyListeners()를 부를 때마다 이 build() 메서드가 자동으로 다시
/// 호출된다. 즉 "상태는 다른 곳(TripSession)에 있고, 이 위젯은 그 상태를
/// 구독해서 보여주기만 하는" 구조다.
class NavigatingScreen extends StatelessWidget {
  const NavigatingScreen({super.key});

  // TripPhase(내부 상태 enum) → 화면에 보여줄 한글 라벨 매핑표.
  static const _phaseLabel = {
    TripPhase.idle: 'Request',
    TripPhase.routing: 'Walking (경로 계산 중)',
    TripPhase.navigating: 'Walking',
    TripPhase.rerouting: 'Waiting (경로 이탈)',
    TripPhase.arrived: 'Rendezvous',
  };

  // NavigationCommand → 화면에 보여줄 아이콘 매핑표.
  static const _commandIcon = {
    NavigationCommand.straight: Icons.arrow_upward,
    NavigationCommand.turnLeft: Icons.turn_left,
    NavigationCommand.altTurnLeft: Icons.turn_slight_left,
    NavigationCommand.turnRight: Icons.turn_right,
    NavigationCommand.altTurnRight: Icons.turn_slight_right,
    NavigationCommand.arrived: Icons.flag_circle,
    NavigationCommand.offRoute: Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    // watch: TripSession이나 BLE 연결 상태가 바뀔 때마다 이 화면이 다시
    // 그려지도록 구독한다 (home_screen.dart의 context.watch 설명 참고).
    final session = context.watch<TripSession>();
    final ble = context.watch<GloveBleService>();
    final command = session.currentCommand;

    return Scaffold(
      appBar: AppBar(title: const Text('이동 안내')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _StatusRow(phase: _phaseLabel[session.phase] ?? '-'),
            const SizedBox(height: 8),
            StreamBuilder<GloveConnectionState>(
              stream: ble.connectionState,
              // 화면 전환 직전에 이미 연결되어 있었을 수도 있으므로, 스트림의
              // 첫 값이 오기 전까지는 현재 isConnected 값으로 미리 보여준다
              // (그냥 disconnected로 고정하면 실제로는 연결됐는데도 잠깐
              // "연결 안 됨"으로 깜빡이는 어색함이 생긴다).
              initialData: ble.isConnected
                  ? GloveConnectionState.connected
                  : GloveConnectionState.disconnected,
              builder: (context, snapshot) {
                final state = snapshot.data ?? GloveConnectionState.disconnected;
                return GloveStatusChip(state: state);
              },
            ),
            const Spacer(), // 위/아래 여백을 균등하게 밀어내서 아이콘을 화면 중앙 쪽에 배치
            Icon(
              command != null ? _commandIcon[command] : Icons.explore_outlined,
              size: 96, // 걸으면서 흘끗 봐도 알아볼 수 있도록 아주 크게
              color: command == NavigationCommand.offRoute
                  ? Colors.redAccent // 경로 이탈은 시각적으로도 눈에 띄게 빨간색
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              command?.label ?? '경로 계산 중…',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            // 경로 이탈 상태일 때만 "재탐색" 버튼을 보여준다.
            if (session.phase == TripPhase.rerouting)
              FilledButton.icon(
                onPressed: () => session.reroute(),
                icon: const Icon(Icons.refresh),
                label: const Text('재탐색'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                session.endTrip(); // TripSession 상태 초기화 + GPS 구독 해제
                Navigator.of(context).pop(); // 이전 화면(HomeScreen)으로 돌아가기
              },
              child: const Text('안내 종료'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Walking" 같은 현재 이동 단계를 보여주는 작은 한 줄짜리 행.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.phase});

  final String phase;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.directions_walk, size: 18),
        const SizedBox(width: 6),
        Text(phase, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}
