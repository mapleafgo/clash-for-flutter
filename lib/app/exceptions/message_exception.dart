/// MessageException 带消息体的异常
class MessageException implements Exception {
  String _message;

  MessageException(String message) {
    this._message = message;
  }

  getMessage() => _message;
}
