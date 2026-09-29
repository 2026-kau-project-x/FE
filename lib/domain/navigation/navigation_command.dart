/// 하드웨어(장갑) 쪽과 합의된 7종 Navigation Command.
/// 기능명세서 06장 "Navigation Command (7종)" 표와 1:1로 대응한다.
///
/// [공부 포인트] 이건 Dart의 "enhanced enum" 문법이다. 일반적인 enum은
/// `enum Foo { a, b, c }`처럼 이름뿐인 값의 나열이지만, enhanced enum은
/// 각 값이 생성자를 호출해서 자기만의 데이터를 들고 다닐 수 있다.
/// 여기서는 각 명령이 (1) 장갑에 실제로 보낼 BLE 바이트 값과 (2) 화면에
/// 보여줄 한글 라벨을 동시에 갖도록 했다. 그래서 `NavigationCommand.turnLeft.byte`,
/// `NavigationCommand.turnLeft.label` 처럼 값 자체에서 바로 꺼내 쓸 수 있다.
enum NavigationCommand {
  straight(0x01, '직진'),
  turnLeft(0x02, '좌회전'),
  altTurnLeft(0x03, '사잇길좌회전'), // 갈림길에서 완만하게 왼쪽 방향으로 빠지는 경우
  turnRight(0x04, '우회전'),
  altTurnRight(0x05, '사잇길우회전'), // 갈림길에서 완만하게 오른쪽 방향으로 빠지는 경우
  arrived(0x06, '안내종료'), // 목적지 도착
  offRoute(0x07, '잘못된 경로로 진행중'); // 경로 이탈이 감지된 상태

  // enhanced enum은 반드시 const 생성자를 가져야 한다 (런타임에 값이 바뀌지 않는다는 뜻).
  const NavigationCommand(this.byte, this.label);

  /// 장갑(ESP32)에 BLE로 실제로 전송되는 1바이트 값.
  final int byte;

  /// 화면에 표시할 한글 라벨 (NavigatingScreen에서 그대로 사용).
  final String label;

  /// BLE로 받은 raw byte(예: 장갑이 되돌려준 LINK_STATUS 값)를 다시
  /// NavigationCommand enum 값으로 변환한다.
  ///
  /// [공부 포인트] `firstWhere`의 `orElse`는 조건에 맞는 원소가 없을 때 실행할
  /// 콜백이다. 여기서는 매칭 실패 시 그냥 null을 주지 않고 일부러 예외를
  /// 던지게 했다 — 알 수 없는 바이트를 조용히 무시하면 나중에 "왜 명령이
  /// 안 오지?" 같은 버그를 디버깅하기 훨씬 어려워지기 때문에, 문제가 생기면
  /// 바로 시끄럽게(throw) 알게 만드는 편이 낫다는 판단이다.
  static NavigationCommand fromByte(int byte) {
    return NavigationCommand.values.firstWhere(
      (c) => c.byte == byte,
      orElse: () => throw ArgumentError('알 수 없는 Navigation Command byte: $byte'),
    );
  }
}
