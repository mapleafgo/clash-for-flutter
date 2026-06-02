import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' as ipc;

/// NDJSON JSON-RPC 2.0 client over dart_ipc transport.
class JsonRpcClient {
  Socket? _socket;
  StreamSubscription? _subscription;
  int _nextId = 1;
  final _pending = <int, Completer<_Response>>{};
  final _notifiers = <String, StreamController<RpcNotification>>{};
  final _lineBuffer = <int>[];
  bool _connected = false;
  bool _intentionalDisconnect = false;

  final String path;

  /// Called when the connection is lost unexpectedly (not via [disconnect]).
  void Function()? onDisconnect;

  /// Timeout for normal requests.
  final Duration normalTimeout;

  /// Timeout for heavy requests (urlTest, etc.).
  final Duration heavyTimeout;

  /// Set of method names that use [heavyTimeout].
  final Set<String> heavyMethods;

  JsonRpcClient({
    required this.path,
    this.normalTimeout = const Duration(seconds: 5),
    this.heavyTimeout = const Duration(seconds: 30),
    this.heavyMethods = const {
      'core.startWithContent',
      'core.stop',
      'core.testDelay',
      'core.testGroupDelay',
    },
  });

  bool get isConnected => _connected;

  /// Stream of notifications for a given method.
  Stream<RpcNotification> notifications(String method) {
    return (_notifiers[method] ??= StreamController<RpcNotification>.broadcast())
        .stream;
  }

  /// Connect to the IPC server.
  Future<void> connect({Duration timeout = const Duration(seconds: 10)}) async {
    if (_connected) return;

    try {
      _socket = await ipc.connect(path).timeout(timeout);
      _connected = true;

      _subscription = _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  /// Send a JSON-RPC request and wait for the response.
  Future<dynamic> call(String method, [Map<String, dynamic>? params]) {
    if (!_connected) throw StateError('Not connected');

    final id = _nextId++;
    final completer = Completer<_Response>();
    _pending[id] = completer;

    final request = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
      'id': id,
    };

    _send(request);

    final timeoutDuration =
        heavyMethods.contains(method) ? heavyTimeout : normalTimeout;

    return completer.future.timeout(timeoutDuration, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('Request $method timed out', timeoutDuration);
    }).then((resp) {
      if (resp.error != null) {
        throw JsonRpcException(resp.error!);
      }
      return resp.result;
    });
  }

  /// Send a JSON-RPC notification (no response expected).
  void notify(String method, [dynamic params]) {
    if (!_connected) return;

    final notification = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
    };

    _send(notification);
  }

  /// Disconnect from the server.
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _connected = false;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;

    for (final c in _pending.values) {
      c.completeError(StateError('Disconnected'));
    }
    _pending.clear();
    _lineBuffer.clear();
  }

  void _send(Map<String, dynamic> message) {
    final data = utf8.encode('${jsonEncode(message)}\n');
    _socket?.add(data);
  }

  void _onData(List<int> data) {
    _lineBuffer.addAll(data);

    // Process complete lines (NDJSON)
    while (true) {
      final newlineIndex = _lineBuffer.indexOf(0x0A); // '\n'
      if (newlineIndex == -1) break;

      final lineBytes = _lineBuffer.sublist(0, newlineIndex);
      _lineBuffer.removeRange(0, newlineIndex + 1);

      if (lineBytes.isEmpty) continue;

      try {
        final json = jsonDecode(utf8.decode(lineBytes)) as Map<String, dynamic>;
        _handleMessage(json);
      } catch (e) {
        // Malformed JSON — skip
      }
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    // Response (has 'id' and no 'method')
    if (msg.containsKey('id') && !msg.containsKey('method')) {
      final id = (msg['id'] as num?)?.toInt();
      if (id != null) {
        final completer = _pending.remove(id);
        if (completer != null) {
          final error = msg['error'] as Map<String, dynamic>?;
          completer.complete(_Response(
            result: msg['result'],
            error: error != null
                ? RpcError(
                    code: error['code'] as int,
                    message: error['message'] as String,
                  )
                : null,
          ));
        }
      }
      return;
    }

    // Notification (has 'method', no 'id')
    if (msg.containsKey('method')) {
      final method = msg['method'] as String;
      final params = msg['params'];
      final controller = _notifiers[method];
      if (controller != null && !controller.isClosed) {
        controller.add(RpcNotification(method: method, params: params));
      }
    }
  }

  void _onError(Object error) {
    _connected = false;
    for (final c in _pending.values) {
      c.completeError(error);
    }
    _pending.clear();
  }

  void _onDone() {
    _connected = false;
    for (final c in _pending.values) {
      c.completeError(StateError('Connection closed'));
    }
    _pending.clear();
    if (!_intentionalDisconnect) {
      onDisconnect?.call();
    }
  }

  void dispose() {
    for (final c in _notifiers.values) {
      c.close();
    }
    _notifiers.clear();
  }
}

class _Response {
  final dynamic result;
  final RpcError? error;
  _Response({this.result, this.error});
}

class RpcNotification {
  final String method;
  final dynamic params;
  RpcNotification({required this.method, this.params});
}

class RpcError {
  final int code;
  final String message;
  RpcError({required this.code, required this.message});

  @override
  String toString() => 'RpcError($code): $message';
}

class JsonRpcException implements Exception {
  final RpcError error;
  JsonRpcException(this.error);

  @override
  String toString() => 'JsonRpcException: ${error.message}';
}
