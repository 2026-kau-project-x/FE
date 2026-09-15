import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../domain/navigation/navigation_command.dart';

/// 장갑(Wearable) BLE GATT 계약. 기능명세서 05장 "BLE — FE ↔ Wearable 프로토콜" 대응.
///
/// UUID는 Tech Lead 확정값 — Wearable(ESP32) 펌웨어도 동일한 값으로 GATT 서버를
/// 구성해야 한다. 이 값이 바뀔 일이 있으면 이 파일만 고치면 되도록 한 곳에 모아둔다.
class GloveBleProtocol {
  GloveBleProtocol._();

  /// 장갑이 광고하는 기기 이름 접두어. ESP32 펌웨어의 실제 advertise 이름과
  /// 일치해야 스캔에서 찾을 수 있다 — 확인되는 대로 이 값을 맞출 것.
  static const devicePrefix = 'GLOVE_';

  static final serviceId = Uuid.parse('0000ff00-0000-1000-8000-00805f9b34fb');

  /// 다운링크(FE→Glove): Navigation Command, 1 byte enum. Write.
  static final navCommandCharacteristicId =
      Uuid.parse('0000ff01-0000-1000-8000-00805f9b34fb');

  /// 업링크(Glove→FE): 마지막 수신 command echo + heartbeat. Notify.
  static final linkStatusCharacteristicId =
      Uuid.parse('0000ff02-0000-1000-8000-00805f9b34fb');

  static List<int> encode(NavigationCommand command) => [command.byte];

  static NavigationCommand? decodeLinkStatus(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      return NavigationCommand.fromByte(bytes.first);
    } on ArgumentError {
      return null;
    }
  }
}
