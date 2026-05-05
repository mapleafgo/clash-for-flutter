import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi_bindings.dart';
import 'lib_core_exception.dart';

/// Event from native core callback.
class CoreEvent {
  final int type;
  final String payload;
  CoreEvent(this.type, this.payload);
}

/// Command message sent to worker isolate.
class _Command {
  final int id;
  final String method;
  final Map<String, dynamic>? args;
  final SendPort replyPort;
  _Command(this.id, this.method, this.args, this.replyPort);
}

/// Response message from worker isolate.
class _Response {
  final int id;
  final dynamic result;
  final String? error;
  _Response.success(this.id, this.result) : error = null;
  _Response.error(this.id, this.error) : result = null;
}

/// Callback type matching CoreCallback: void callback(int eventType, const char* jsonPayload)
typedef _CoreCallbackNative = ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>);

/// Long-lived FFI worker isolate with event-driven callback support.
class FfiWorker {
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _mainPort;
  int _requestId = 0;
  final _pending = <int, Completer<dynamic>>{};
  final _eventController = StreamController<CoreEvent>.broadcast();
  bool _disposed = false;

  Stream<CoreEvent> get events => _eventController.stream;

  Future<void> spawn(String libPath) async {
    _mainPort = ReceivePort();
    _mainPort!.listen(_onMessageFromWorker);

    _isolate = await Isolate.spawn(
      _workerEntryPoint,
      _WorkerInit(libPath, _mainPort!.sendPort),
      debugName: 'ffi-worker',
    );
  }

  void _onMessageFromWorker(dynamic message) {
    if (message is SendPort) {
      _workerPort = message;
      return;
    }
    if (message is _Response) {
      final completer = _pending.remove(message.id);
      if (completer == null) return;
      if (message.error != null) {
        completer.completeError(LibCoreException(message.error!));
      } else {
        completer.complete(message.result);
      }
      return;
    }
    if (message is CoreEvent) {
      _eventController.add(message);
      return;
    }
  }

  Future<T> invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (_disposed || _workerPort == null) {
      throw StateError('FfiWorker not initialized or disposed');
    }
    final id = ++_requestId;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _workerPort!.send(_Command(id, method, args, _mainPort!.sendPort));
    return completer.future.then((v) => v as T);
  }

  void dispose() {
    _disposed = true;
    _mainPort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _eventController.close();
    for (final c in _pending.values) {
      c.completeError(StateError('FfiWorker disposed'));
    }
    _pending.clear();
  }
}

class _WorkerInit {
  final String libPath;
  final SendPort mainPort;
  _WorkerInit(this.libPath, this.mainPort);
}

void _workerEntryPoint(_WorkerInit init) {
  final receivePort = ReceivePort();
  init.mainPort.send(receivePort.sendPort);

  final lib = ffi.DynamicLibrary.open(init.libPath);
  final bindings = LibCoreBindings(lib);
  final mainPort = init.mainPort;

  final callback = NativeCallable<_CoreCallbackNative>.listener(
    (int eventType, ffi.Pointer<ffi.Char> jsonPtr) {
      final payload = jsonPtr.cast<Utf8>().toDartString();
      bindings.CoreFreeString(jsonPtr);
      mainPort.send(CoreEvent(eventType, payload));
    },
  );
  bindings.CoreSetCallback(callback.nativeFunction.cast());

  receivePort.listen((message) {
    if (message is _Command) {
      try {
        final result = _dispatch(bindings, message.method, message.args);
        message.replyPort.send(_Response.success(message.id, result));
      } catch (e) {
        message.replyPort.send(_Response.error(message.id, e.toString()));
      }
    }
  });
}

dynamic _dispatch(LibCoreBindings b, String method, Map<String, dynamic>? args) {
  switch (method) {
    // Lifecycle
    case 'CoreInit':
      return _withCString(args!['optionsJSON'] as String, (p) {
        _parseResult(b.CoreInit(p), b);
      });
    case 'CoreStartWithContent':
      return _withTwoCStrings(
        args!['content'] as String,
        args['ruleSetProxy'] as String,
        (p1, p2) => _parseResult(b.CoreStartWithContent(p1, p2), b),
      );
    case 'CoreStop':
      return _parseResult(b.CoreStop(), b);
    case 'CoreDestroy':
      return b.CoreDestroy();
    case 'CorePause':
      return b.CorePause();
    case 'CoreWake':
      return b.CoreWake();
    case 'CoreResetNetwork':
      return b.CoreResetNetwork();

    // Config
    case 'CoreReloadConfig':
      return _withTwoCStrings(
        args!['content'] as String,
        args['ruleSetProxy'] as String,
        (p1, p2) => _parseResult(b.CoreReloadConfig(p1, p2), b),
      );
    case 'CoreReloadTUN':
      return _parseResult(b.CoreReloadTUN(), b);
    case 'CoreSetOverridePackages':
      return _withCString(args!['overrideJSON'] as String,
          (p) => _parseResult(b.CoreSetOverridePackages(p), b));
    case 'CoreQueryTunOptions':
      return _parseResultString(b.CoreQueryTunOptions(), b);
    case 'CoreCheckConfig':
      return _withCString(args!['content'] as String,
          (p) => _parseResultString(b.CoreCheckConfig(p), b));

    // Queries
    case 'CoreQueryProxies':
      return _parseResultJson(b.CoreQueryProxies(), b);
    case 'CoreQueryTraffic':
      return _parseResultJson(b.CoreQueryTraffic(), b);
    case 'CoreQueryLogs':
      return _parseResultJson(b.CoreQueryLogs(args!['clear'] as int), b);
    case 'CoreQueryConnections':
      return _parseResultJson(b.CoreQueryConnections(), b);

    // Proxy Control
    case 'CoreSelectProxy':
      return _withTwoCStrings(
        args!['group'] as String,
        args['tag'] as String,
        (p1, p2) => _parseResult(b.CoreSelectProxy(p1, p2), b),
      );
    case 'CoreSetMode':
      return _withCString(
          args!['mode'] as String, (p) => _parseResult(b.CoreSetMode(p), b));
    case 'CoreSetGroupExpand':
      return _withCString(args!['group'] as String, (p) {
        return _parseResult(b.CoreSetGroupExpand(p, args['expand'] as bool ? 1 : 0), b);
      });
    case 'CoreTestDelay':
      return _withCString(
          args!['name'] as String, (p) => _parseResult(b.CoreTestDelay(p), b));

    // Connections
    case 'CoreCloseConnection':
      return _withCString(args!['id'] as String,
          (p) => _parseResult(b.CoreCloseConnection(p), b));
    case 'CoreCloseAllConnections':
      return _parseResult(b.CoreCloseAllConnections(), b);

    // Logging / Memory
    case 'CoreSetLogLevel':
      return b.CoreSetLogLevel(args!['level'] as int);
    case 'CoreSetError':
      return _withCString(args!['message'] as String,
          (p) => b.CoreSetError(p));
    case 'CoreSetMemoryLimit':
      return _parseResult(b.CoreSetMemoryLimit(args!['bytes'] as int), b);
    case 'CoreQueryMemoryStats':
      return _parseResultString(b.CoreQueryMemoryStats(), b);
    case 'CoreFlushSystemDNS':
      return b.CoreFlushSystemDNS();

    // Version / Platform
    case 'CoreGetVersion':
      return _parseResultString(b.CoreGetVersion(), b);
    case 'CoreNeedFindProcess':
      return b.CoreNeedFindProcess() != 0;
    case 'CoreWriteMessage':
      return _withCString(args!['message'] as String,
          (p) => b.CoreWriteMessage(args['level'] as int, p));
    case 'CoreSetLocale':
      return _withCString(
          args!['localeID'] as String, (p) => b.CoreSetLocale(p));

    default:
      throw UnimplementedError('Unknown FFI method: $method');
  }
}

// --- FFI helpers (worker isolate only) ---

void _parseResult(ffi.Pointer<ffi.Char> ptr, LibCoreBindings b) {
  try {
    final str = ptr.cast<Utf8>().toDartString();
    if (str.isEmpty) return;
    final json = _jsonDecode(str);
    if (json is Map && json.containsKey('error')) {
      throw LibCoreException(json['error']);
    }
  } finally {
    b.CoreFreeString(ptr);
  }
}

dynamic _parseResultJson(ffi.Pointer<ffi.Char> ptr, LibCoreBindings b) {
  try {
    final str = ptr.cast<Utf8>().toDartString();
    final json = _jsonDecode(str);
    if (json is Map && json.containsKey('error')) {
      throw LibCoreException(json['error']);
    }
    return json;
  } finally {
    b.CoreFreeString(ptr);
  }
}

String _parseResultString(ffi.Pointer<ffi.Char> ptr, LibCoreBindings b) {
  try {
    final str = ptr.cast<Utf8>().toDartString();
    if (str.isEmpty) return '';
    final json = _jsonDecode(str);
    if (json is Map && json.containsKey('error')) {
      throw LibCoreException(json['error']);
    }
    return str;
  } finally {
    b.CoreFreeString(ptr);
  }
}

dynamic _jsonDecode(String s) => jsonDecode(s);

T _withCString<T>(String s, T Function(ffi.Pointer<ffi.Char>) fn) {
  final p = s.toNativeUtf8().cast<ffi.Char>();
  try {
    return fn(p);
  } finally {
    calloc.free(p);
  }
}

T _withTwoCStrings<T>(
  String s1,
  String s2,
  T Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>) fn,
) {
  final p1 = s1.toNativeUtf8().cast<ffi.Char>();
  final p2 = s2.toNativeUtf8().cast<ffi.Char>();
  try {
    return fn(p1, p2);
  } finally {
    calloc.free(p1);
    calloc.free(p2);
  }
}
