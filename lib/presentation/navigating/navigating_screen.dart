import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ble/ble_connection_state.dart';
import '../../core/ble/ble_service.dart';
import '../../domain/navigation/navigation_command.dart';
import '../../domain/session/trip_state.dart';
import '../widgets/glove_status_chip.dart';

/// 보행 안내 화면. 현재 Navigation Command와 장갑 연결상태를 함께 보여준다. (FE-3, FE-8)
class NavigatingScreen extends StatelessWidget {
  const NavigatingScreen({super.key});

  static const _phaseLabel = {
    TripPhase.idle: 'Request',
    TripPhase.routing: 'Walking (경로 계산 중)',
    TripPhase.navigating: 'Walking',
    TripPhase.rerouting: 'Waiting (경로 이탈)',
    TripPhase.arrived: 'Rendezvous',
  };

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
              initialData: ble.isConnected
                  ? GloveConnectionState.connected
                  : GloveConnectionState.disconnected,
              builder: (context, snapshot) {
                final state = snapshot.data ?? GloveConnectionState.disconnected;
                return GloveStatusChip(state: state);
              },
            ),
            const Spacer(),
            Icon(
              command != null ? _commandIcon[command] : Icons.explore_outlined,
              size: 96,
              color: command == NavigationCommand.offRoute
                  ? Colors.redAccent
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              command?.label ?? '경로 계산 중…',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            if (session.phase == TripPhase.rerouting)
              FilledButton.icon(
                onPressed: () => session.reroute(),
                icon: const Icon(Icons.refresh),
                label: const Text('재탐색'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                session.endTrip();
                Navigator.of(context).pop();
              },
              child: const Text('안내 종료'),
            ),
          ],
        ),
      ),
    );
  }
}

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
