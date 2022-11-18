/// MessageException 带消息体的异常
class MessageException implements Exception {
  late String _message;

  MessageException(String message) {
    _message = message;
  }

  getMessage() => _message;
}
