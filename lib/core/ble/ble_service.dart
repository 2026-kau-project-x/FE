import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../domain/navigation/navigation_command.dart';
import 'ble_connection_state.dart';
import 'ble_protocol.dart';

/// 장갑과의 BLE 연결·통신을 담당. (FE-5, FE-6)
class GloveBleService {
  GloveBleService({FlutterReactiveBle? ble}) : _bleOverride = ble;

  final FlutterReactiveBle? _bleOverride;
  FlutterReactiveBle? _bleInstance;

  /// 실제 연결 시도 전까지 플러그인(내부 상태추적 타이머 포함)을 기동하지 않는다.
  FlutterReactiveBle get _ble => _bleInstance ??= _bleOverride ?? FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _statusSub;
  String? _deviceId;

  final _stateController = StreamController<GloveConnectionState>.broadcast();
  Stream<GloveConnectionState> get connectionState => _stateController.stream;

  final _ackController = StreamController<NavigationCommand>.broadcast();
  /// 장갑이 마지막으로 수신했다고 echo한 command (LINK_STATUS)
  Stream<NavigationCommand> get lastAck => _ackController.stream;

  bool get isConnected => _deviceId != null;

  /// 스캔 → 연결 → LINK_STATUS 구독까지 한 번에 수행한다.
  ///
  /// 서비스 UUID가 아직 미확정(placeholder)이라 withServices 필터를 걸면
  /// 실기기를 못 찾을 수 있어, 전체 스캔 후 기기 이름 접두어로 걸러낸다.
  /// UUID가 확정되면 ble_protocol.dart만 교체하면 된다.
  Future<void> connect({Duration scanTimeout = const Duration(seconds: 10)}) async {
    _stateController.add(GloveConnectionState.scanning);

    final completer = Completer<String>();
    _scanSub = _ble.scanForDevices(withServices: const []).listen(
      (device) {
        if (device.name.startsWith(GloveBleProtocol.devicePrefix) &&
            !completer.isCompleted) {
          completer.complete(device.id);
        }
      },
      onError: (Object e, StackTrace _) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    final String deviceId;
    try {
      deviceId = await completer.future.timeout(scanTimeout);
    } on TimeoutException {
      await _scanSub?.cancel();
      _stateController.add(GloveConnectionState.failed);
      rethrow;
    } finally {
      await _scanSub?.cancel();
    }

    _deviceId = deviceId;
    _stateController.add(GloveConnectionState.connecting);

    _connSub = _ble.connectToDevice(id: deviceId).listen(
      (update) {
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            _stateController.add(GloveConnectionState.connected);
            _subscribeLinkStatus(deviceId);
            break;
          case DeviceConnectionState.disconnected:
            _deviceId = null;
            _stateController.add(GloveConnectionState.disconnected);
            break;
          default:
            break;
        }
      },
      onError: (Object _, StackTrace _) => _stateController.add(GloveConnectionState.failed),
    );
  }

  void _subscribeLinkStatus(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: GloveBleProtocol.serviceId,
      characteristicId: GloveBleProtocol.linkStatusCharacteristicId,
      deviceId: deviceId,
    );
    _statusSub = _ble.subscribeToCharacteristic(characteristic).listen((bytes) {
      final ack = GloveBleProtocol.decodeLinkStatus(bytes);
      if (ack != null) _ackController.add(ack);
    });
  }

  /// Navigation Command 다운링크 전송. 연결 안 된 상태면 조용히 무시하지 않고 예외를 던진다 —
  /// 호출부(TripSession)가 연결상태를 먼저 확인하도록 강제하기 위함.
  Future<void> sendCommand(NavigationCommand command) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('장갑이 연결되지 않았습니다.');
    }
    final characteristic = QualifiedCharacteristic(
      serviceId: GloveBleProtocol.serviceId,
      characteristicId: GloveBleProtocol.navCommandCharacteristicId,
      deviceId: deviceId,
    );
    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: GloveBleProtocol.encode(command),
    );
  }

  Future<void> disconnect() async {
    await _scanSub?.cancel();
    await _statusSub?.cancel();
    await _connSub?.cancel();
    _deviceId = null;
    _stateController.add(GloveConnectionState.disconnected);
  }

  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _statusSub?.cancel();
    _stateController.close();
    _ackController.close();
  }
}
