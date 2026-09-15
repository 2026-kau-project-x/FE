/// 하드웨어(장갑) 쪽과 합의된 7종 Navigation Command.
/// 기능명세서 06장 "Navigation Command (7종)" 표와 1:1로 대응한다.
enum NavigationCommand {
  straight(0x01, '직진'),
  turnLeft(0x02, '좌회전'),
  altTurnLeft(0x03, '사잇길좌회전'),
  turnRight(0x04, '우회전'),
  altTurnRight(0x05, '사잇길우회전'),
  arrived(0x06, '안내종료'),
  offRoute(0x07, '잘못된 경로로 진행중');

  const NavigationCommand(this.byte, this.label);

  final int byte;
  final String label;

  static NavigationCommand fromByte(int byte) {
    return NavigationCommand.values.firstWhere(
      (c) => c.byte == byte,
      orElse: () => throw ArgumentError('알 수 없는 Navigation Command byte: $byte'),
    );
  }
}
