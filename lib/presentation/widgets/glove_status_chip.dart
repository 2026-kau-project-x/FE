import 'package:flutter/material.dart';

import '../../core/ble/ble_connection_state.dart';

/// 장갑 BLE 연결상태 칩. 온보딩 화면·이동 안내 화면에서 공통으로 쓴다.
class GloveStatusChip extends StatelessWidget {
  const GloveStatusChip({super.key, required this.state});

  final GloveConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      GloveConnectionState.connected => ('장갑 연결됨', Colors.green),
      GloveConnectionState.connecting => ('연결 중…', Colors.orange),
      GloveConnectionState.scanning => ('장갑 검색 중…', Colors.orange),
      GloveConnectionState.failed => ('연결 실패', Colors.red),
      GloveConnectionState.disconnected => ('장갑 연결 안 됨', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.watch, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
