import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../domain/navigation/navigation_command.dart';
import 'ble_connection_state.dart';
import 'ble_protocol.dart';

/// 장갑과의 BLE 연결·통신을 담당하는 서비스. (FE-5, FE-6)
///
/// `flutter_reactive_ble`는 Flutter에서 BLE를 다루는 대표적인 패키지다.
/// 이 클래스는 그 패키지의 저수준 API(스캔, 연결, 캐릭터리스틱 읽기/쓰기)를
/// 감싸서, 앱의 나머지 부분(TripSession, HomeScreen)은 "장갑에 연결하고
/// (connect), 명령을 보내고(sendCommand), 연결 상태를 구독한다
/// (connectionState 스트림)"는 간단한 인터페이스만 쓰면 되게 만든다.
class GloveBleService {
  GloveBleService({FlutterReactiveBle? ble}) : _bleOverride = ble;

  // 테스트에서 가짜 BLE 인스턴스를 주입할 수 있도록 생성자로 받는다
  // (tmap_route_client.dart의 Dio 주입과 같은 이유).
  final FlutterReactiveBle? _bleOverride;
  FlutterReactiveBle? _bleInstance;

  /// [공부 포인트 — 지연 초기화(lazy initialization)]
  /// `??=`는 "왼쪽 값이 null이면 오른쪽 값을 대입하고, 아니면 그대로 둔다"는
  /// 연산자다. 즉 `_bleInstance`가 아직 없을 때만 새로 만든다. FlutterReactiveBle
  /// 객체를 생성하는 순간 내부적으로 상태추적 타이머 등이 돌기 시작하는데,
  /// GloveBleService 자체는 앱 시작하자마자(main.dart) 만들어지지만 실제로
  /// BLE가 필요한 시점은 사용자가 "장갑 연결하기"를 눌렀을 때뿐이다. 그래서
  /// 진짜 필요해지는 그 순간까지 생성을 미루는(lazy) 게터로 만들었다.
  FlutterReactiveBle get _ble => _bleInstance ??= _bleOverride ?? FlutterReactiveBle();

  // 스캔/연결/구독 각각의 스트림 구독(subscription) 핸들. 나중에 연결을
  // 끊거나(disconnect) 서비스를 정리할 때(dispose) 이 핸들로 취소(cancel)해야
  // 스트림 리스너가 메모리에 계속 남아있는 "누수(leak)"를 막을 수 있다.
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _statusSub;
  String? _deviceId;

  /// [공부 포인트 — StreamController]
  /// StreamController는 "내가 값을 넣으면(add) 구독자들에게 흘러가는 파이프"를
  /// 직접 만드는 도구다. `.broadcast()`를 붙인 이유: 기본 스트림은 구독자가
  /// 1명만 붙을 수 있는데, 여기서는 HomeScreen과 NavigatingScreen 등 여러
  /// 화면이 동시에 같은 연결 상태를 구독해야 하므로 broadcast(다중 구독 허용)
  /// 스트림으로 만들었다. 이 클래스 내부에서만 `.add()`로 값을 넣고, 외부에는
  /// `.stream`(읽기 전용)만 노출한다 — "쓰기는 나만, 읽기는 모두에게" 패턴.
  final _stateController = StreamController<GloveConnectionState>.broadcast();
  Stream<GloveConnectionState> get connectionState => _stateController.stream;

  final _ackController = StreamController<NavigationCommand>.broadcast();
  /// 장갑이 마지막으로 수신했다고 echo한 command (LINK_STATUS)
  Stream<NavigationCommand> get lastAck => _ackController.stream;

  bool get isConnected => _deviceId != null;

  /// 스캔 → 연결 → LINK_STATUS 구독까지 한 번에 수행한다.
  ///
  /// [전체 흐름]
  /// 1. 주변 BLE 기기를 스캔한다.
  /// 2. 이름이 "GLOVE_"로 시작하는 첫 번째 기기를 찾으면 스캔을 멈춘다.
  /// 3. 그 기기에 연결을 시도한다.
  /// 4. 연결되면 LINK_STATUS 캐릭터리스틱을 구독해서 장갑의 ACK를 받을
  ///    준비를 한다.
  ///
  /// 서비스 UUID가 아직 미확정(placeholder)이라 withServices 필터를 걸면
  /// 실기기를 못 찾을 수 있어, 전체 스캔 후 기기 이름 접두어로 걸러낸다.
  /// UUID가 확정되면 ble_protocol.dart만 교체하면 된다.
  Future<void> connect({Duration scanTimeout = const Duration(seconds: 10)}) async {
    _stateController.add(GloveConnectionState.scanning);

    // [공부 포인트 — Completer]
    // Completer는 "스트림 이벤트를 하나 기다렸다가, 원하는 게 나오면 그
    // 시점에 Future를 완료시키는" 도구다. scanForDevices()는 계속 흘러
    // 나오는 스트림인데, 우리가 원하는 건 "그중 조건에 맞는 첫 번째 기기
    // 하나"뿐이다. 그래서 스트림을 listen하다가 조건에 맞는 기기를 찾으면
    // completer.complete()를 호출해서 아래 `await completer.future`가 그
    // 값을 받고 진행되게 만든다 — "스트림을 Future로 변환하는" 흔한 패턴.
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
      // scanTimeout 안에 원하는 기기를 못 찾으면 TimeoutException이 발생한다.
      deviceId = await completer.future.timeout(scanTimeout);
    } on TimeoutException {
      await _scanSub?.cancel();
      _stateController.add(GloveConnectionState.failed);
      rethrow; // 호출한 쪽(HomeScreen._connectGlove)이 에러를 알고 스낵바를 띄울 수 있게 전파
    } finally {
      // 기기를 찾았든 시간초과로 실패했든, 스캔은 더 이상 필요 없으니 반드시 멈춘다.
      // finally 블록이라 try 안에서 무슨 일이 생기든 항상 실행된다.
      await _scanSub?.cancel();
    }

    _deviceId = deviceId;
    _stateController.add(GloveConnectionState.connecting);

    // connectToDevice()도 스트림이다 — 연결 시도 과정에서 여러 상태
    // (connecting → connected/disconnected 등)를 순차적으로 흘려보낸다.
    // 이 스트림은 연결이 유지되는 한 계속 살아있으므로(연결 끊김 감지도
    // 이 스트림으로 온다) completer 패턴이 아니라 listen을 계속 유지한다.
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
            break; // connecting, disconnecting 등 중간 상태는 UI에서 따로 구분하지 않음
        }
      },
      onError: (Object _, StackTrace _) => _stateController.add(GloveConnectionState.failed),
    );
  }

  /// LINK_STATUS 캐릭터리스틱을 구독해서, 장갑이 보내는 notify(알림)를
  /// 받을 때마다 디코딩해서 lastAck 스트림으로 흘려보낸다.
  void _subscribeLinkStatus(String deviceId) {
    // QualifiedCharacteristic: "어떤 기기(deviceId)의, 어떤 서비스(serviceId)
    // 아래, 어떤 캐릭터리스틱(characteristicId)인지"를 한 번에 지정하는 값.
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

  /// Navigation Command를 장갑에 전송한다 (다운링크).
  ///
  /// 연결이 안 된 상태에서 호출되면 조용히 아무 일도 안 하는 대신 예외를
  /// 던진다 — 호출하는 쪽(TripSession)이 "연결 확인을 먼저 해야 한다"는
  /// 걸 잊지 않도록 강제하기 위한 설계다. 실제로 TripSession은 sendCommand를
  /// 부르기 전에 `bleService.isConnected`를 먼저 확인한다.
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
    // writeCharacteristicWithResponse: 장갑이 값을 잘 받았다는 응답까지
    // 기다린다(vs. WithoutResponse는 응답 없이 그냥 쏘기만 함). 명령 하나하나가
    // 실제로 전달됐는지 확인하는 게 중요하므로 응답을 기다리는 쪽을 택했다.
    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: GloveBleProtocol.encode(command),
    );
  }

  /// 모든 구독을 취소하고 연결 상태를 초기화한다.
  Future<void> disconnect() async {
    await _scanSub?.cancel();
    await _statusSub?.cancel();
    await _connSub?.cancel();
    _deviceId = null;
    _stateController.add(GloveConnectionState.disconnected);
  }

  /// [공부 포인트] 이 서비스는 main.dart에서 앱 전체 생명주기 동안 딱 한
  /// 번만 만들어지는 객체라 실제로 dispose가 호출될 일은 거의 없지만,
  /// StreamController는 안 쓸 때 반드시 close()해줘야 하는 자원이라는 걸
  /// 보여주는 관례적인 코드다 (안 닫으면 메모리 누수로 이어질 수 있다).
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _statusSub?.cancel();
    _stateController.close();
    _ackController.close();
  }
}
