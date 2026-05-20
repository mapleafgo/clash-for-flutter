import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'ffi_bindings.dart';
import 'lib_core_exception.dart';

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

/// Callback event from kernel via worker isolate.
class _CallbackEvent {
  final int eventType;
  final String payload;
  _CallbackEvent(this.eventType, this.payload);
}

/// Long-lived FFI worker isolate for non-blocking kernel calls.
class FfiWorker {
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _mainPort;
  int _requestId = 0;
  final _pending = <int, Completer<dynamic>>{};
  bool _disposed = false;
  Completer<void>? _readyCompleter;
  void Function(int eventType, String payload)? onCallback;

  Future<void> spawn(String libPath) async {
    _readyCompleter = Completer<void>();
    _mainPort = ReceivePort();
    _mainPort!.listen(_onMessageFromWorker);

    _isolate = await Isolate.spawn(
      _workerEntryPoint,
      _WorkerInit(libPath, _mainPort!.sendPort),
      debugName: 'ffi-worker',
      onError: _mainPort!.sendPort,
      onExit: _mainPort!.sendPort,
    );

    await _readyCompleter!.future;
  }

  void _onMessageFromWorker(dynamic message) {
    if (_disposed) return;
    if (message is SendPort) {
      _workerPort = message;
      _readyCompleter?.complete();
      return;
    }
    if (message is _CallbackEvent) {
      onCallback?.call(message.eventType, message.payload);
      return;
    }
    // Isolate 错误或退出
    if (message == null || (message is List && message.first is String)) {
      _handleCrash();
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
    }
  }

  void _handleCrash() {
    _disposed = true;
    for (final c in _pending.values) {
      c.completeError(StateError('FFI worker terminated unexpectedly'));
    }
    _pending.clear();
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
    if (_disposed) return;
    _disposed = true;
    _workerPort?.send(_Command(-1, '__exit__', null, _mainPort!.sendPort));
    _mainPort?.close();
    _isolate?.kill(priority: Isolate.immediate);
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

// 顶层变量确保 GC 不回收 NativeCallable（worker isolate 内）
ffi.NativeCallable<ffi.Void Function(ffi.Int32, ffi.Pointer<ffi.Char>)>? _eventCb;

void _workerEntryPoint(_WorkerInit init) {
  final receivePort = ReceivePort();
  init.mainPort.send(receivePort.sendPort);

  final lib = ffi.DynamicLibrary.open(init.libPath);
  final bindings = LibCoreBindings(lib);

  // 统一事件回调：ownership transfer，Dart 侧拷贝后调 CoreFreeString 释放
  // eventType: 0=Log, 1=URLTest, 2=ModeUpdate, 3=ConnEvent, 4=StateUpdate
  _eventCb = ffi.NativeCallable<
      ffi.Void Function(ffi.Int32, ffi.Pointer<ffi.Char>)>.listener(
          (int eventType, ffi.Pointer<ffi.Char> payload) {
    final dartStr = payload.cast<Utf8>().toDartString();
    bindings.CoreFreeString(payload);
    init.mainPort.send(_CallbackEvent(eventType, dartStr));
  });
  bindings.CoreSetEventCallback(_eventCb!.nativeFunction);

  receivePort.listen((message) {
    if (message is _Command) {
      if (message.method == '__exit__') {
        _eventCb?.close();
        _eventCb = null;
        receivePort.close();
        return;
      }
      if (message.method == 'CoreTestDelay') {
        _runTestDelayConcurrent(message, init.libPath);
      } else {
        try {
          final result = _dispatch(bindings, message.method, message.args);
          message.replyPort.send(_Response.success(message.id, result));
        } catch (e) {
          message.replyPort.send(_Response.error(message.id, e.toString()));
        }
      }
    }
  });
}

/// 在独立 isolate 中并发执行 CoreTestDelay，不阻塞 worker 主循环。
Future<void> _runTestDelayConcurrent(_Command message, String libPath) async {
  final name = message.args!['name'] as String;
  final timeoutMs = message.args!['timeoutMs'] as int? ?? 3000;
  try {
    final result = await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final coreTestDelay = lib.lookupFunction<
          ffi.Int Function(ffi.Pointer<ffi.Char>, ffi.Int32),
          int Function(ffi.Pointer<ffi.Char>, int)
      >('CoreTestDelay');
      final namePtr = name.toNativeUtf8();
      try {
        return coreTestDelay(namePtr.cast(), timeoutMs);
      } finally {
        malloc.free(namePtr);
      }
    });
    message.replyPort.send(_Response.success(message.id, result));
  } catch (e) {
    message.replyPort.send(_Response.error(message.id, e.toString()));
  }
}

dynamic _dispatch(LibCoreBindings b, String method, Map<String, dynamic>? args) {
  switch (method) {
    // Lifecycle
    case 'CoreInit':
      return _withCString(args!['optionsJSON'] as String,
          (p) => _parseResult(b.CoreInit(p), b));
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
    case 'CoreResetNetwork':
      return b.CoreResetNetwork();

    // Config
    case 'CoreCheckConfig':
      return _withCString(args!['content'] as String,
          (p) => _parseResult(b.CoreCheckConfig(p), b));

    // Queries
    case 'CoreQueryProxies':
      return _parseResultJson(b.CoreQueryProxies(), b);
    case 'CoreQueryStats':
      return _parseResultJson(b.CoreQueryStats(), b);
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
        return _parseResult(
            b.CoreSetGroupExpand(p, args['expand'] as bool ? 1 : 0), b);
      });
    case 'CoreTestDelay':
      final timeoutMs = args!['timeoutMs'] as int? ?? 3000;
      return _withCString(args['name'] as String,
          (p) => b.CoreTestDelay(p, timeoutMs));

    case 'CoreTestGroupDelay':
      final timeoutMs = args!['timeoutMs'] as int? ?? 3000;
      return _withCString(args['group'] as String,
          (p) => _parseResultJson(b.CoreTestGroupDelay(p, timeoutMs), b));

    // Connections
    case 'CoreCloseConnection':
      return _withCString(args!['id'] as String,
          (p) => _parseResult(b.CoreCloseConnection(p), b));
    case 'CoreCloseAllConnections':
      return _parseResult(b.CoreCloseAllConnections(), b);

    // Logging / Memory
    case 'CoreSetLogLevel':
      return b.CoreSetLogLevel(args!['level'] as int);
    case 'CoreSetMemoryLimit':
      return b.CoreSetMemoryLimit(args!['bytes'] as int);
    case 'CoreFlushSystemDNS':
      return b.CoreFlushSystemDNS();

    // State & Mode queries
    case 'CoreQueryState':
      return _parseResultString(b.CoreQueryState(), b);
    case 'CoreQueryMode':
      return _parseResultJson(b.CoreQueryMode(), b);

    // Rules & DNS
    case 'CoreQueryRules':
      return _parseResultJson(b.CoreQueryRules(), b);
    case 'CoreFlushFakeIP':
      return _parseResult(b.CoreFlushFakeIP(), b);
    case 'CoreFlushDNSCache':
      return _parseResult(b.CoreFlushDNSCache(), b);
    case 'CoreTriggerGC':
      return b.CoreTriggerGC();

    // Version
    case 'CoreGetVersion':
      return _parseResultString(b.CoreGetVersion(), b);

    default:
      throw UnimplementedError('Unknown FFI method: $method');
  }
}

// --- FFI helpers (worker isolate only) ---

// 命令类：null = 成功，非空 = 错误字符串
void _parseResult(ffi.Pointer<ffi.Char> ptr, LibCoreBindings b) {
  if (ptr == ffi.nullptr) return;
  try {
    final err = ptr.cast<Utf8>().toDartString();
    if (err.isNotEmpty) throw LibCoreException(err);
  } finally {
    b.CoreFreeString(ptr);
  }
}

// 查询类：返回 JSON 字符串
dynamic _parseResultJson(ffi.Pointer<ffi.Char> ptr, LibCoreBindings b) {
  try {
    final str = ptr.cast<Utf8>().toDartString();
    return jsonDecode(str);
  } finally {
    b.CoreFreeString(ptr);
  }
}

// 字符串类：返回原始字符串
String _parseResultString(ffi.Pointer<ffi.Char> ptr, LibCoreBindings b) {
  try {
    return ptr.cast<Utf8>().toDartString();
  } finally {
    b.CoreFreeString(ptr);
  }
}

T _withCString<T>(String s, T Function(ffi.Pointer<ffi.Char>) fn) {
  final p = s.toNativeUtf8(allocator: malloc).cast<ffi.Char>();
  try {
    return fn(p);
  } finally {
    malloc.free(p);
  }
}

T _withTwoCStrings<T>(
  String s1,
  String s2,
  T Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>) fn,
) {
  final p1 = s1.toNativeUtf8(allocator: malloc).cast<ffi.Char>();
  final p2 = s2.toNativeUtf8(allocator: malloc).cast<ffi.Char>();
  try {
    return fn(p1, p2);
  } finally {
    malloc.free(p1);
    malloc.free(p2);
  }
}
