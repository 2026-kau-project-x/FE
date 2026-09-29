import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../domain/navigation/navigation_command.dart';

/// 장갑(Wearable) BLE GATT 계약. 기능명세서 05장 "BLE — FE ↔ Wearable 프로토콜" 대응.
///
/// [BLE/GATT 배경지식 — 처음 보는 사람을 위한 설명]
/// BLE(Bluetooth Low Energy) 기기는 자기 데이터를 "GATT"라는 구조로
/// 노출한다. 비유하자면 GATT는 일종의 트리 구조 API다:
///   Service(서비스) — 관련된 기능들의 묶음. UUID(고유 식별자)로 구분된다.
///     └─ Characteristic(캐릭터리스틱) — 실제 읽기/쓰기/구독이 가능한
///        "값" 하나. 이것도 자기만의 UUID를 갖는다.
/// 우리 장갑은 Service 하나 아래에 Characteristic 2개를 둔다: 앱이 장갑에
/// 명령을 "쓰는(Write)" 것과, 장갑이 앱에게 상태를 "알려주는(Notify)" 것.
/// 앱(FE)과 장갑(ESP32 펌웨어) 양쪽이 반드시 똑같은 UUID를 써야 서로를
/// 인식할 수 있다 — 그래서 이 값들은 "계약(contract)"이고, 한쪽만 바꾸면
/// 절대 안 된다.
///
/// UUID는 Tech Lead 확정값 — Wearable(ESP32) 펌웨어도 동일한 값으로 GATT
/// 서버를 구성해야 한다. 이 값이 바뀔 일이 있으면 이 파일만 고치면 되도록
/// 프로토콜 상수를 전부 한 클래스에 모아뒀다 (다른 파일에 흩어져 있으면
/// 바꿀 때 빠뜨리기 쉽다).
class GloveBleProtocol {
  // 생성자를 private(_)으로 막아서 이 클래스는 인스턴스를 만들 수 없게
  // 했다. 안에 든 게 전부 static 상수/함수라 애초에 인스턴스가 필요 없다 —
  // "이건 그냥 이름공간(namespace)이다"라는 의도를 코드로 표현한 것.
  GloveBleProtocol._();

  /// 장갑이 광고(advertise, 주변에 "나 여기 있어요"라고 신호를 계속 보내는
  /// 것)할 때 쓰는 기기 이름의 접두어. 스캔 결과 중 이 접두어로 시작하는
  /// 기기만 우리 장갑으로 간주한다. ESP32 펌웨어의 실제 advertise 이름과
  /// 일치해야만 스캔에서 찾을 수 있다 — 확인되는 대로 이 값을 맞출 것.
  static const devicePrefix = 'GLOVE_';

  /// 장갑의 GATT Service UUID. 표준 BLE UUID는 128비트인데, 앞의 8자리
  /// (0000ff00)만 우리가 정한 값이고 나머지(-0000-1000-8000-00805f9b34fb)는
  /// "Bluetooth Base UUID"라는 고정된 접미사다. 이런 짧은 커스텀 UUID
  /// 형식은 자체 개발 BLE 기기에서 흔히 쓰는 방식이다.
  static final serviceId = Uuid.parse('0000ff00-0000-1000-8000-00805f9b34fb');

  /// 다운링크(FE→Glove) 캐릭터리스틱: Navigation Command 1바이트를 여기에
  /// "쓰면(Write)" 장갑이 그 값을 받아서 진동 패턴을 출력한다.
  static final navCommandCharacteristicId =
      Uuid.parse('0000ff01-0000-1000-8000-00805f9b34fb');

  /// 업링크(Glove→FE) 캐릭터리스틱: 장갑이 마지막으로 받은 command를
  /// 그대로 되돌려주는(echo) 용도. 앱은 이 값을 "구독(subscribe)"해서
  /// 장갑이 실제로 명령을 잘 받았는지 확인하는 ACK(수신확인)로 쓴다.
  static final linkStatusCharacteristicId =
      Uuid.parse('0000ff02-0000-1000-8000-00805f9b34fb');

  /// NavigationCommand를 BLE로 전송할 바이트 배열로 변환한다.
  /// (실제로는 언제나 1바이트짜리 리스트 — command.byte 하나뿐)
  static List<int> encode(NavigationCommand command) => [command.byte];

  /// 장갑이 보내온 LINK_STATUS 바이트를 다시 NavigationCommand로 해석한다.
  /// 알 수 없는 바이트가 오면(장갑 펌웨어 버그, 노이즈 등) 앱이 죽지 않고
  /// null을 리턴해서 조용히 무시하도록 했다 — NavigationCommand.fromByte()는
  /// 원래 예외를 던지지만, BLE로 들어오는 외부 데이터는 언제든 이상할 수
  /// 있으므로 여기서는 그 예외를 잡아서 null로 바꿔주는 "방어막" 역할을 한다.
  static NavigationCommand? decodeLinkStatus(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      return NavigationCommand.fromByte(bytes.first);
    } on ArgumentError {
      return null;
    }
  }
}
