/// IPC/FFI 内核事件类型常量，供 IpcWorker 和 LibCore 共享。
///
/// IpcWorker 将 JSON-RPC 通知映射为这些事件类型，
/// LibCore._handleWorkerCallback 根据 eventType 分发处理。
class CoreEventType {
  static const log = 0;
  static const urlTest = 1;
  static const modeUpdate = 2;
  static const connEvent = 3;
  static const stateUpdate = 4;
  static const trafficUpdate = 5;
}
