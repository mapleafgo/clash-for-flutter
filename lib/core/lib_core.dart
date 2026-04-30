import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../domain/connection.dart';
import '../domain/log.dart';
import '../domain/net_speed.dart';
import '../domain/proxy_group.dart';
import '../utils/constants.dart';
import 'ffi_bindings.dart';
import 'lib_core_channel.dart';
import 'lib_core_exception.dart';

abstract class LibCorePlatform {
  Future<void> init();
  Future<void> initCore(String homeDir);
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy});
  Future<void> stopCore();
  Future<void> closeCore();
  Future<void> reloadConfig();

  Future<List<ProxyGroup>> queryProxies();
  Future<TrafficSnapshot> queryTraffic();
  Future<List<LogEntry>> queryLogs();
  Future<ConnectionEventsPayload> queryConnections();

  Future<void> selectProxy(String group, String tag);
  Future<void> testDelay(String name);
  Future<void> setMode(String mode);
  Future<void> closeConnection(String id);
  Future<void> closeAllConnections();
  Future<String> checkConfig(String content);
  Future<String> getVersion();

  Future<void> connectVpn(String configContent, {String? ruleSetProxy});
  Future<void> disconnectVpn();
  Future<bool> isVpnRunning();
}

class LibCore {
  static final LibCore instance = LibCore._();
  LibCore._();

  late final LibCorePlatform _platform;

  final trafficSignal = signal<TrafficSnapshot?>(null);
  final logsSignal = signal<List<LogEntry>>([]);
  final activeConnectionsSignal = signal<int>(0);
  final proxiesSignal = signal<List<ProxyGroup>>([]);
  final modeSignal = signal<String>('rule');
  final vpnDisconnectedByUser = signal<bool>(false); // set to true when VPN is disconnected from notification

  static const _maxLogs = 1000;
  final _logBuffer = <LogEntry>[];
  final _activeConnectionIds = <String>{};

  Future<void> init() async {
    if (Constants.isDesktop) {
      _platform = LibCoreFFI();
    } else {
      _platform = LibCoreChannel();
    }
    await _platform.init();
  }

  Future<void> initCore(String homeDir) async {
    try {
      await _platform.initCore(homeDir);
    } on LibCoreException catch (e) {
      if (!e.message.contains('already initialized')) rethrow;
    }
  }

  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) =>
      _platform.startCoreWithContent(content, ruleSetProxy: ruleSetProxy);

  Future<void> stopCore() => _platform.stopCore();

  Future<void> closeCore() => _platform.closeCore();

  Future<void> reloadConfig() => _platform.reloadConfig();

  Future<List<ProxyGroup>> queryProxies() => _platform.queryProxies();

  Future<TrafficSnapshot> queryTraffic() => _platform.queryTraffic();

  Future<List<LogEntry>> queryLogs() => _platform.queryLogs();

  Future<ConnectionEventsPayload> queryConnections() =>
      _platform.queryConnections();

  Future<void> selectProxy(String group, String tag) =>
      _platform.selectProxy(group, tag);

  Future<void> testDelay(String name) => _platform.testDelay(name);

  Future<void> setMode(String mode) => _platform.setMode(mode);

  Future<void> closeConnection(String id) => _platform.closeConnection(id);

  Future<void> closeAllConnections() => _platform.closeAllConnections();

  Future<String> checkConfig(String content) =>
      _platform.checkConfig(content);

  Future<String> getVersion() => _platform.getVersion();

  Future<void> connectVpn(String configContent, {String? ruleSetProxy}) =>
      _platform.connectVpn(configContent, ruleSetProxy: ruleSetProxy);

  Future<void> disconnectVpn() => _platform.disconnectVpn();

  Future<bool> isVpnRunning() => _platform.isVpnRunning();

  void appendLogs(List<LogEntry> newLogs) {
    _logBuffer.addAll(newLogs);
    if (_logBuffer.length > _maxLogs) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxLogs);
    }
    logsSignal.value = List.unmodifiable(_logBuffer);
  }

  void clearLogs() {
    _logBuffer.clear();
    logsSignal.value = [];
  }

  void handleConnectionEvents(ConnectionEventsPayload payload) {
    if (payload.reset) {
      _activeConnectionIds.clear();
    }
    for (final event in payload.items) {
      if (event.eventType == 0) {
        _activeConnectionIds.add(event.id);
      } else {
        _activeConnectionIds.remove(event.id);
      }
    }
    activeConnectionsSignal.value = _activeConnectionIds.length;
  }

  LibCorePlatform get platform => _platform;
}

class LibCoreFFI implements LibCorePlatform {
  Timer? _pollTimer;
  bool _running = false;

  @override
  Future<void> init() async {
    // The library is opened fresh inside each Isolate.run() call,
    // so no need to hold a reference here.
  }

  String get _platformLibPath {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isLinux) return '$exeDir/lib/libsingcast-linux.so';
    if (Platform.isMacOS) return '$exeDir/../Frameworks/libsingcast-darwin.dylib';
    if (Platform.isWindows) return '$exeDir/libsingcast-windows.dll';
    throw UnsupportedError('Unsupported platform');
  }

  void startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    if (_running) return;
    _running = true;
    try {
      final core = LibCore.instance;
      await Future.wait([
        _safeQuery(
            () => core.queryTraffic(), (r) => core.trafficSignal.value = r),
        _safeQuery(
            () => core.queryProxies(), (r) => core.proxiesSignal.value = r),
        _safeQuery(() => core.queryLogs(), (r) => core.appendLogs(r)),
        _safeQuery(() => core.queryConnections(),
            (r) => core.handleConnectionEvents(r)),
      ]);
    } finally {
      _running = false;
    }
  }

  Future<void> _safeQuery<T>(
    Future<T> Function() query,
    void Function(T) apply,
  ) async {
    try {
      apply(await query().timeout(const Duration(seconds: 5)));
    } catch (_) {}
  }

  // ---- Static helpers for use inside Isolates ----

  /// Parse the result from a core FFI call. Throws [LibCoreException] on error.
  /// Must be called from the same isolate that performed the FFI call.
  static void _parseResult(
    ffi.Pointer<ffi.Char> ptr,
    LibCoreBindings bindings,
  ) {
    try {
      final str = ptr.cast<Utf8>().toDartString();
      if (str.isEmpty) return;
      final json = jsonDecode(str);
      if (json is Map && json.containsKey('error')) {
        throw LibCoreException(json['error']);
      }
    } finally {
      bindings.CoreFreeString(ptr);
    }
  }

  /// Parse the result and return the decoded JSON value.
  /// Must be called from the same isolate that performed the FFI call.
  static dynamic _parseResultJson(
    ffi.Pointer<ffi.Char> ptr,
    LibCoreBindings bindings,
  ) {
    try {
      final str = ptr.cast<Utf8>().toDartString();
      final json = jsonDecode(str);
      if (json is Map && json.containsKey('error')) {
        throw LibCoreException(json['error']);
      }
      return json;
    } finally {
      bindings.CoreFreeString(ptr);
    }
  }

  /// Parse the result and return the raw string (before JSON decode).
  /// Must be called from the same isolate that performed the FFI call.
  static String _parseResultString(
    ffi.Pointer<ffi.Char> ptr,
    LibCoreBindings bindings,
  ) {
    try {
      final str = ptr.cast<Utf8>().toDartString();
      if (str.isEmpty) return '';
      final json = jsonDecode(str);
      if (json is Map && json.containsKey('error')) {
        throw LibCoreException(json['error']);
      }
      return str;
    } finally {
      bindings.CoreFreeString(ptr);
    }
  }

  // ---- FFI methods (all run in Isolates to avoid UI jank) ----

  @override
  Future<void> initCore(String homeDir) async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final homeDirPtr = homeDir.toNativeUtf8().cast<ffi.Char>();
      ffi.Pointer<ffi.Char> resultPtr;
      try {
        resultPtr = bindings.CoreInit(homeDirPtr);
      } finally {
        calloc.free(homeDirPtr);
      }
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final contentPtr = content.toNativeUtf8().cast<ffi.Char>();
      final proxyPtr = (ruleSetProxy ?? '').toNativeUtf8().cast<ffi.Char>();
      ffi.Pointer<ffi.Char> resultPtr;
      try {
        resultPtr = bindings.CoreStartWithContent(contentPtr, proxyPtr);
      } finally {
        calloc.free(contentPtr);
        calloc.free(proxyPtr);
      }
      _parseResult(resultPtr, bindings);
    });
    startPolling();
  }

  @override
  Future<void> stopCore() async {
    stopPolling();
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreStop();
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<void> closeCore() async {
    stopPolling();
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      bindings.CoreClose();
    });
  }

  @override
  Future<void> reloadConfig() async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreReloadConfig();
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<List<ProxyGroup>> queryProxies() async {
    final libPath = _platformLibPath;
    return Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreQueryProxies();
      final json = _parseResultJson(resultPtr, bindings);
      return (json as List)
          .map((e) => ProxyGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<TrafficSnapshot> queryTraffic() async {
    final libPath = _platformLibPath;
    return Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreQueryTraffic();
      final json = _parseResultJson(resultPtr, bindings);
      return TrafficSnapshot.fromJson(json as Map<String, dynamic>);
    });
  }

  @override
  Future<List<LogEntry>> queryLogs() async {
    final libPath = _platformLibPath;
    return Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreQueryLogs();
      final json = _parseResultJson(resultPtr, bindings);
      return (json as List)
          .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<ConnectionEventsPayload> queryConnections() async {
    final libPath = _platformLibPath;
    return Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreQueryConnections();
      final json = _parseResultJson(resultPtr, bindings);
      if (json is! Map<String, dynamic>) {
        return ConnectionEventsPayload(reset: true, items: []);
      }
      return ConnectionEventsPayload.fromJson(json);
    });
  }

  @override
  Future<void> selectProxy(String group, String tag) async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final groupPtr = group.toNativeUtf8().cast<ffi.Char>();
      final tagPtr = tag.toNativeUtf8().cast<ffi.Char>();
      ffi.Pointer<ffi.Char> resultPtr;
      try {
        resultPtr = bindings.CoreSelectProxy(groupPtr, tagPtr);
      } finally {
        calloc.free(groupPtr);
        calloc.free(tagPtr);
      }
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<void> testDelay(String name) async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final namePtr = name.toNativeUtf8().cast<ffi.Char>();
      final underscorePtr = ''.toNativeUtf8().cast<ffi.Char>();
      ffi.Pointer<ffi.Char> resultPtr;
      try {
        resultPtr = bindings.CoreTestDelay(namePtr, underscorePtr);
      } finally {
        calloc.free(namePtr);
        calloc.free(underscorePtr);
      }
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<void> setMode(String mode) async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final modePtr = mode.toNativeUtf8().cast<ffi.Char>();
      ffi.Pointer<ffi.Char> resultPtr;
      try {
        resultPtr = bindings.CoreSetMode(modePtr);
      } finally {
        calloc.free(modePtr);
      }
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<void> closeConnection(String id) async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final idPtr = id.toNativeUtf8().cast<ffi.Char>();
      ffi.Pointer<ffi.Char> resultPtr;
      try {
        resultPtr = bindings.CoreCloseConnection(idPtr);
      } finally {
        calloc.free(idPtr);
      }
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<void> closeAllConnections() async {
    final libPath = _platformLibPath;
    await Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreCloseAllConnections();
      _parseResult(resultPtr, bindings);
    });
  }

  @override
  Future<String> checkConfig(String content) async {
    final libPath = _platformLibPath;
    return Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final ptr = content.toNativeUtf8().cast<ffi.Char>();
      ffi.Pointer<ffi.Char> resultPtr;
      try {
        resultPtr = bindings.CoreCheckConfig(ptr);
      } finally {
        calloc.free(ptr);
      }
      return _parseResultString(resultPtr, bindings);
    });
  }

  @override
  Future<String> getVersion() async {
    final libPath = _platformLibPath;
    return Isolate.run(() {
      final lib = ffi.DynamicLibrary.open(libPath);
      final bindings = LibCoreBindings(lib);
      final resultPtr = bindings.CoreGetVersion();
      return _parseResultString(resultPtr, bindings);
    });
  }

  @override
  Future<void> connectVpn(String configContent, {String? ruleSetProxy}) async {
    throw UnsupportedError('connectVpn is only available on mobile platforms');
  }

  @override
  Future<void> disconnectVpn() async {
    throw UnsupportedError('disconnectVpn is only available on mobile platforms');
  }

  @override
  Future<bool> isVpnRunning() async => false;
}
