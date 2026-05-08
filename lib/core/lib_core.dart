import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:signals_flutter/signals_flutter.dart';

import '../domain/connection.dart';
import '../domain/log.dart';
import '../domain/net_speed.dart';
import '../domain/proxy_group.dart';
import '../utils/constants.dart';
import '../utils/log_file.dart';
import 'ffi_worker.dart';
import 'lib_core_channel.dart';
import 'lib_core_exception.dart';

abstract class LibCorePlatform {
  Stream<CoreEvent> get events;
  Future<void> init();
  Future<void> initCore(String homeDir);
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy});
  Future<void> stopCore();
  Future<void> destroyCore();
  Future<void> pause();
  Future<void> wake();
  Future<void> resetNetwork();
  Future<void> reloadTUN();
  Future<void> setOverridePackages(String overrideJSON);
  Future<String> queryTunOptions();
  Future<List<ProxyGroup>> queryProxies();
  Future<TrafficSnapshot> queryTraffic();
  Future<List<LogEntry>> queryLogs({bool clear = false});
  Future<ConnectionEventsPayload> queryConnections();
  Future<void> selectProxy(String group, String tag);
  Future<void> testDelay(String name);
  Future<void> setMode(String mode);
  Future<void> setGroupExpand(String group, bool expand);
  Future<void> closeConnection(String id);
  Future<void> closeAllConnections();
  Future<void> setLogLevel(int level);
  Future<void> setMemoryLimit(int bytes);
  Future<String> queryMemoryStats();
  Future<void> flushSystemDNS();
  Future<bool> needFindProcess();
  Future<void> writeMessage(int level, String message);
  Future<String> checkConfig(String content);
  Future<String> getVersion();
  Future<void> setLocale(String localeID);
  Future<void> connectVpn(String configContent, {String? ruleSetProxy, bool? ipv6});
  Future<void> disconnectVpn();
  Future<bool> isVpnRunning();
  void updateVpnTraffic(TrafficSnapshot traffic);
  Future<void> openTun(String mergedContent, {String? ruleSetProxy, bool? ipv6});
  Future<void> closeTun(String mergedContent, {String? ruleSetProxy});
  bool get isVpnStarting;
}

class LibCore {
  static final LibCore instance = LibCore._();
  LibCore._();

  late final LibCorePlatform _platform;
  StreamSubscription<CoreEvent>? _eventSub;

  final trafficSignal = signal<TrafficSnapshot?>(null);
  final logsSignal = signal<List<LogEntry>>([]);
  final activeConnectionsSignal = signal<int>(0);
  final proxiesSignal = signal<List<ProxyGroup>>([]);
  final modeSignal = signal<String>('rule');
  final vpnDisconnectedByUser = signal<bool>(false);
  final coreConnected = signal<bool>(false);

  static const _maxLogs = 1000;
  final _logBuffer = <LogEntry>[];
  final _activeConnectionIds = <String>{};

  String get _platformLibPath {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isLinux) return '$exeDir/lib/libsingcast-linux.so';
    if (Platform.isMacOS) return '$exeDir/../Frameworks/libsingcast-darwin.dylib';
    if (Platform.isWindows) return '$exeDir/libsingcast-windows.dll';
    throw UnsupportedError('Unsupported platform');
  }

  Future<void> init() async {
    if (Constants.isDesktop) {
      final worker = FfiWorker();
      await worker.spawn(_platformLibPath);
      _platform = _FfiWorkerBackend(worker);
    } else {
      _platform = LibCoreChannel();
      await _platform.init();
    }
    _eventSub = _platform.events.listen(handleCoreEvent);
    await LogFileWriter.init('${Constants.homeDir.path}/singcast.log');
  }

  // --- Shared event handler for both desktop and mobile ---

  void handleCoreEvent(CoreEvent event) {
    try {
      final decoded = jsonDecode(event.payload);
      switch (event.type) {
        case 0: // traffic
          if (decoded is Map<String, dynamic>) {
            final snapshot = TrafficSnapshot.fromJson(decoded);
            trafficSignal.value = snapshot;
            _updateVpnTraffic(snapshot);
          }
        case 1: // logs
          if (decoded is List) {
            appendLogs(decoded
                .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
                .toList());
          }
        case 2: // connections
          if (decoded is Map<String, dynamic>) {
            handleConnectionEvents(ConnectionEventsPayload.fromJson(decoded));
          }
        case 3: // proxies
          if (decoded is List) {
            proxiesSignal.value = decoded
                .map((e) => ProxyGroup.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        case 4: // mode
          if (decoded is Map<String, dynamic>) {
            modeSignal.value = decoded['current_mode'] as String? ?? 'rule';
          }
        case 5: // vpn state changed
          if (decoded is Map<String, dynamic>) {
            vpnDisconnectedByUser.value =
                !(decoded['connected'] as bool? ?? true);
          }
        case 6: // core logs (internal)
          if (decoded is List) {
            appendLogs(decoded
                .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
                .toList());
          }
        case 7: // connected
          coreConnected.value = true;
        case 8: // disconnected
          coreConnected.value = false;
          proxiesSignal.value = [];
      }
    } catch (_) {
      // Defensive: ignore malformed event payloads
    }
  }

  // --- Delegated methods ---

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
  Future<void> destroyCore() => _platform.destroyCore();
  Future<void> pause() => _platform.pause();
  Future<void> wake() => _platform.wake();
  Future<void> resetNetwork() => _platform.resetNetwork();
  Future<void> reloadTUN() => _platform.reloadTUN();
  Future<void> setOverridePackages(String overrideJSON) =>
      _platform.setOverridePackages(overrideJSON);
  Future<String> queryTunOptions() => _platform.queryTunOptions();
  Future<List<ProxyGroup>> queryProxies() => _platform.queryProxies();
  Future<TrafficSnapshot> queryTraffic() => _platform.queryTraffic();
  Future<List<LogEntry>> queryLogs({bool clear = false}) =>
      _platform.queryLogs(clear: clear);
  Future<void> selectProxy(String group, String tag) =>
      _platform.selectProxy(group, tag);
  Future<void> testDelay(String name) => _platform.testDelay(name);
  Future<void> setMode(String mode) => _platform.setMode(mode);
  Future<void> setGroupExpand(String group, bool expand) =>
      _platform.setGroupExpand(group, expand);
  Future<void> closeConnection(String id) => _platform.closeConnection(id);
  Future<void> closeAllConnections() => _platform.closeAllConnections();
  Future<void> setLogLevel(int level) => _platform.setLogLevel(level);
  Future<void> setMemoryLimit(int bytes) => _platform.setMemoryLimit(bytes);
  Future<String> queryMemoryStats() => _platform.queryMemoryStats();
  Future<void> flushSystemDNS() => _platform.flushSystemDNS();
  Future<bool> needFindProcess() => _platform.needFindProcess();
  Future<void> writeMessage(int level, String message) =>
      _platform.writeMessage(level, message);
  Future<String> checkConfig(String content) =>
      _platform.checkConfig(content);
  Future<String> getVersion() => _platform.getVersion();
  Future<void> setLocale(String localeID) => _platform.setLocale(localeID);
  Future<void> connectVpn(String configContent, {String? ruleSetProxy, bool? ipv6}) =>
      _platform.connectVpn(configContent, ruleSetProxy: ruleSetProxy, ipv6: ipv6);
  Future<void> disconnectVpn() => _platform.disconnectVpn();
  Future<bool> isVpnRunning() => _platform.isVpnRunning();
  Future<void> openTun(String mergedContent, {String? ruleSetProxy, bool? ipv6}) =>
      _platform.openTun(mergedContent, ruleSetProxy: ruleSetProxy, ipv6: ipv6);
  Future<void> closeTun(String mergedContent, {String? ruleSetProxy}) =>
      _platform.closeTun(mergedContent, ruleSetProxy: ruleSetProxy);
  bool get isVpnStarting => _platform.isVpnStarting;

  // --- Log buffer management ---

  void _updateVpnTraffic(TrafficSnapshot traffic) {
    if (Constants.isDesktop) return;
    _platform.updateVpnTraffic(traffic);
  }

  void clearLogs() {
    _logBuffer.clear();
    logsSignal.value = [];
    queryLogs(clear: true).catchError((_) => <LogEntry>[]);
  }

  void appendLogs(List<LogEntry> newLogs) {
    _logBuffer.addAll(newLogs);
    if (_logBuffer.length > _maxLogs) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxLogs);
    }
    logsSignal.value = List.unmodifiable(_logBuffer);
    LogFileWriter.instance?.writeAll(newLogs);
  }

  void handleConnectionEvents(ConnectionEventsPayload payload) {
    if (payload.reset) _activeConnectionIds.clear();
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

/// Desktop FFI backend using FfiWorker.
class _FfiWorkerBackend implements LibCorePlatform {
  final FfiWorker _worker;
  _FfiWorkerBackend(this._worker);

  @override
  Stream<CoreEvent> get events => _worker.events;

  @override
  Future<void> init() async {}

  @override
  Future<void> initCore(String homeDir) =>
      _worker.invoke('CoreInit', {
        'optionsJSON':
            jsonEncode({'home_dir': homeDir, 'log_max_lines': 500}),
      });

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) =>
      _worker.invoke('CoreStartWithContent', {
        'content': content,
        'ruleSetProxy': ruleSetProxy ?? '',
      });

  @override
  Future<void> stopCore() => _worker.invoke('CoreStop');

  @override
  Future<void> destroyCore() => _worker.invoke('CoreDestroy');

  @override
  Future<void> pause() => _worker.invoke('CorePause');

  @override
  Future<void> wake() => _worker.invoke('CoreWake');

  @override
  Future<void> resetNetwork() => _worker.invoke('CoreResetNetwork');


  @override
  Future<void> reloadTUN() => _worker.invoke('CoreReloadTUN');

  @override
  Future<void> setOverridePackages(String overrideJSON) =>
      _worker.invoke('CoreSetOverridePackages', {
        'overrideJSON': overrideJSON,
      });

  @override
  Future<String> queryTunOptions() =>
      _worker.invoke<String>('CoreQueryTunOptions');

  @override
  Future<List<ProxyGroup>> queryProxies() async {
    final json = await _worker.invoke<dynamic>('CoreQueryProxies');
    return (json as List)
        .map((e) => ProxyGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<TrafficSnapshot> queryTraffic() async {
    final json = await _worker.invoke<dynamic>('CoreQueryTraffic');
    return TrafficSnapshot.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<List<LogEntry>> queryLogs({bool clear = false}) async {
    final json = await _worker.invoke<dynamic>('CoreQueryLogs', {
      'clear': clear ? 1 : 0,
    });
    return (json as List)
        .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ConnectionEventsPayload> queryConnections() async {
    final json = await _worker.invoke<dynamic>('CoreQueryConnections');
    if (json is! Map<String, dynamic>) {
      return ConnectionEventsPayload(reset: true, items: []);
    }
    return ConnectionEventsPayload.fromJson(json);
  }

  @override
  Future<void> selectProxy(String group, String tag) =>
      _worker.invoke('CoreSelectProxy', {
        'group': group,
        'tag': tag,
      });

  @override
  Future<void> testDelay(String name) =>
      _worker.invoke('CoreTestDelay', {'name': name});

  @override
  Future<void> setMode(String mode) =>
      _worker.invoke('CoreSetMode', {'mode': mode});

  @override
  Future<void> setGroupExpand(String group, bool expand) =>
      _worker.invoke('CoreSetGroupExpand', {
        'group': group,
        'expand': expand,
      });

  @override
  Future<void> closeConnection(String id) =>
      _worker.invoke('CoreCloseConnection', {'id': id});

  @override
  Future<void> closeAllConnections() =>
      _worker.invoke('CoreCloseAllConnections');

  @override
  Future<void> setLogLevel(int level) =>
      _worker.invoke('CoreSetLogLevel', {'level': level});

  @override
  Future<void> setMemoryLimit(int bytes) =>
      _worker.invoke('CoreSetMemoryLimit', {'bytes': bytes});

  @override
  Future<String> queryMemoryStats() =>
      _worker.invoke<String>('CoreQueryMemoryStats');

  @override
  Future<void> flushSystemDNS() => _worker.invoke('CoreFlushSystemDNS');

  @override
  Future<bool> needFindProcess() =>
      _worker.invoke<bool>('CoreNeedFindProcess');

  @override
  Future<void> writeMessage(int level, String message) =>
      _worker.invoke('CoreWriteMessage', {
        'level': level,
        'message': message,
      });

  @override
  Future<String> checkConfig(String content) =>
      _worker.invoke<String>('CoreCheckConfig', {'content': content});

  @override
  Future<String> getVersion() =>
      _worker.invoke<String>('CoreGetVersion');

  @override
  Future<void> setLocale(String localeID) =>
      _worker.invoke('CoreSetLocale', {'localeID': localeID});

  @override
  Future<void> connectVpn(String configContent, {String? ruleSetProxy, bool? ipv6}) {
    throw UnsupportedError('connectVpn is only available on mobile platforms');
  }

  @override
  Future<void> disconnectVpn() {
    throw UnsupportedError('disconnectVpn is only available on mobile platforms');
  }

  @override
  Future<bool> isVpnRunning() async => false;

  @override
  void updateVpnTraffic(TrafficSnapshot traffic) {}

  @override
  Future<void> openTun(String mergedContent, {String? ruleSetProxy, bool? ipv6}) async {}

  @override
  Future<void> closeTun(String mergedContent, {String? ruleSetProxy}) async {}

  @override
  bool get isVpnStarting => false;
}
