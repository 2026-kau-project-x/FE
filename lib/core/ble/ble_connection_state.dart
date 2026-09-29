/// 장갑(Wearable)과의 BLE 연결 상태 5단계.
///
/// GloveBleService가 연결을 시도하는 동안 이 값들을 순서대로 흘려보낸다:
/// disconnected(초기 상태) → scanning(기기 검색 중) → connecting(찾은 기기에
/// 연결 시도 중) → connected(연결 완료) 또는 failed(스캔 시간초과·연결 에러
/// 등으로 실패). UI(GloveStatusChip)는 이 값을 구독해서 사용자에게 지금
/// 무슨 일이 일어나고 있는지 보여준다.
enum GloveConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  failed,
}
