import 'package:flutter/material.dart';

import '../../core/ble/ble_connection_state.dart';

/// 장갑 BLE 연결상태를 보여주는 작은 알약(pill) 모양 위젯.
/// 온보딩 화면(HomeScreen)과 이동 안내 화면(NavigatingScreen) 양쪽에서
/// 똑같이 쓰여서, 공통 위젯 폴더(presentation/widgets)로 따로 뺐다 —
/// 코드 중복을 없애고, 나중에 디자인을 바꿀 때 한 곳만 고치면 되게 하기 위함.
///
/// [설계 메모] 원래는 Flutter의 기본 `Chip` 위젯을 썼었는데, 웹 빌드(캔버스
/// 렌더러)에서 한글 라벨 텍스트가 이상하게 잘려 보이는 현상이 있어서 직접
/// `Container` + `Row`로 똑같은 모양을 만들어 대체했다. 원인을 깊게 파기보다
/// 더 단순하고 확실하게 제어 가능한 방식으로 바꾼 것.
class GloveStatusChip extends StatelessWidget {
  const GloveStatusChip({super.key, required this.state});

  final GloveConnectionState state;

  @override
  Widget build(BuildContext context) {
    // [공부 포인트 — Dart 3 패턴 매칭 switch 표현식]
    // 이건 `switch (state) { case ...: return ...; }` 문장을 훨씬 짧게 쓸 수
    // 있는 최신 Dart 문법이다. `=>` 오른쪽 값을 바로 반환하고, 왼쪽처럼
    // `(label, color)`라는 "레코드(튜플)"를 한 번에 만들어서 두 변수에
    // 동시에 대입(destructuring)할 수 있다. 자바/구버전 Dart라면 if-else를
    // 여러 번 쓰거나 두 개의 Map을 따로 만들어야 했을 코드다.
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
        borderRadius: BorderRadius.circular(20), // 숫자를 크게 줘서 완전한 알약 모양으로
        border: Border.all(color: color.withValues(alpha: 0.35)), // 상태 색을 연하게 테두리로만
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // Row 크기를 내용물만큼만 (화면 폭 전체 X)
        children: [
          Icon(Icons.watch, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
