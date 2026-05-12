import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:signals_flutter/signals_flutter.dart';

import '../domain/connection.dart';
import '../domain/enums.dart';
import '../domain/log.dart';
import '../domain/net_speed.dart';
import '../domain/proxy_group.dart';
import '../utils/constants.dart';
import '../utils/log_file.dart';
import 'ffi_worker.dart';
import 'lib_core_channel.dart';
import 'lib_core_exception.dart';

abstract class LibCorePlatform {
  Future<void> init();
  Future<void> initCore(String homeDir);
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy});
  Future<void> destroyCore();
  Future<void> resetNetwork();
  Future<(List<ProxyGroup>, Map<String, int>)> queryProxies();
  Future<TrafficSnapshot> queryTraffic();
  Future<ConnectionEventsPayload> queryConnections();
  Future<String> queryMode();
  Future<String> queryState();
  Future<void> selectProxy(String group, String tag);
  Future<int> testDelay(String name, {int timeoutMs = 3000});
  Future<Map<String, int>> testGroupDelay(String group, {int timeoutMs = 3000});
  Future<void> setMode(String mode);
  Future<void> setGroupExpand(String group, bool expand);
  Future<void> closeConnection(String id);
  Future<void> closeAllConnections();
  Future<void> setLogLevel(int level);
  Future<void> setMemoryLimit(int bytes);
  Future<void> flushSystemDNS();
  Future<void> flushFakeIP();
  Future<void> flushDNSCache();
  Future<void> triggerGC();
  Future<String> checkConfig(String content);
  Future<String> getVersion();
  Future<void> connectVpn(
    String configContent, {
    String? ruleSetProxy,
    bool? ipv6,
  });
  Future<void> disconnectVpn();
  Future<bool> isVpnRunning();
  void updateVpnTraffic(TrafficSnapshot traffic);
}

class LibCore {
  static final LibCore instance = LibCore._();
  LibCore._();

  static const kStateCreated = 'created';
  static const kStateInitialized = 'initialized';
  static const kStateStarting = 'starting';
  static const kStateRunning = 'running';
  static const kStateDestroyed = 'destroyed';

  late final LibCorePlatform _platform;
  FfiWorker? _worker;

  final trafficSignal = signal<TrafficSnapshot?>(null);
  final activeConnectionsSignal = signal<int>(0);
  final proxiesSignal = signal<List<ProxyGroup>>([]);
  final selectedProxySignal = signal<Map<String, String>>({});
  final _proxyDelays = signal<Map<String, int>>({});
  Signal<Map<String, int>> get proxyDelaysSignal => _proxyDelays;
  final modeSignal = signal<String>('rule');
  final stateSignal = signal<String>(kStateCreated);
  final availableModesSignal = signal<List<String>>(['rule', 'global', 'direct']);
  final proxyTogglingSignal = signal(false);

  final _activeConnectionIds = <String>{};
  int _prevUpTotal = 0;
  int _prevDownTotal = 0;
  Timer? _pollTimer;

  String get _platformLibPath {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isLinux) return '$exeDir/lib/libsingcast-linux.so';
    if (Platform.isMacOS) {
      return '$exeDir/../Frameworks/libsingcast-darwin.dylib';
    }
    if (Platform.isWindows) return '$exeDir/libsingcast-windows.dll';
    throw UnsupportedError('Unsupported platform');
  }

  LibCorePlatform get platform => _platform;

  Future<void> init() async {
    if (Constants.isDesktop) {
      _worker = FfiWorker();
      _worker!.onCallback = _handleWorkerCallback;
      await _worker!.spawn(_platformLibPath);
      _platform = _FfiWorkerBackend(_worker!);
    } else {
      final channel = LibCoreChannel();
      channel.onCallback = _handleWorkerCallback;
      _platform = channel;
      await _platform.init();
    }
    await LogFileWriter.init('${Constants.homeDir.path}/singcast.log');
  }

  void dispose() {
    stopPolling();
    _worker?.dispose();
  }

  // eventType: 0=Log, 1=URLTest, 2=ModeUpdate, 3=ConnEvent, 4=StateUpdate
  void _handleWorkerCallback(int eventType, String payload) {
    switch (eventType) {
      case 0: // Log
        final json = jsonDecode(payload) as Map<String, dynamic>;
        LogFileWriter.instance?.writeAll([LogEntry.fromJson(json)]);
      case 1: // URLTest
        _queryAndUpdate();
      case 2: // ModeUpdate
        modeSignal.value = payload.toLowerCase();
      case 3: // ConnEvent
        final json = jsonDecode(payload) as Map<String, dynamic>;
        handleConnectionEvents(ConnectionEventsPayload.fromJson(json));
      case 4: // StateUpdate
        final newState = payload;
        final oldState = stateSignal.peek();
        LogFileWriter.instance?.log(
          'StateUpdate: $oldState -> $newState',
          name: 'tun',
        );
        if (newState == oldState) break;
        stateSignal.value = newState;
        if (newState == kStateRunning) {
          proxyTogglingSignal.value = false;
          _onKernelRunning();
        } else {
          if (newState == kStateInitialized || newState == kStateDestroyed) {
            proxyTogglingSignal.value = false;
          }
          stopPolling();
          proxiesSignal.value = [];
          _proxyDelays.value = {};
        }
    }
  }

  void updateProxyDelays(Map<String, int> delays) {
    _proxyDelays.value = delays;
  }

  void updateProxyDelay(String tag, int delay) {
    final current = Map<String, int>.from(_proxyDelays.peek());
    current[tag] = delay;
    _proxyDelays.value = current;
  }

  void _onKernelRunning() {
    startPolling();
    _queryAndUpdate();
    _fetchAvailableModes();
  }

  // --- Polling ---

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _prevUpTotal = 0;
    _prevDownTotal = 0;
  }

  Future<void> _poll() async {
    try {
      if (stateSignal.peek() != kStateRunning) return;

      final raw = await queryTraffic();
      final upSpeed = (raw.upTotal - _prevUpTotal).clamp(0, raw.upTotal);
      final downSpeed = (raw.downTotal - _prevDownTotal).clamp(0, raw.downTotal);
      _prevUpTotal = raw.upTotal;
      _prevDownTotal = raw.downTotal;

      final traffic = TrafficSnapshot(
        up: upSpeed,
        down: downSpeed,
        upTotal: raw.upTotal,
        downTotal: raw.downTotal,
        memory: raw.memory,
        connections: raw.connections,
      );
      trafficSignal.value = traffic;
      activeConnectionsSignal.value = traffic.connections;
      _updateVpnTraffic(traffic);

      // 检测异常：有上传无下载 或 内存/连接数异常
      if (upSpeed > 1024 && downSpeed == 0) {
        LogFileWriter.instance?.log(
          'traffic anomaly: up=$upSpeed down=$downSpeed conns=${traffic.connections} mem=${traffic.memory}',
          level: LogLevel.warning,
          name: 'tun',
        );
      }
      if (traffic.memory > 100 * 1024 * 1024 || traffic.connections > 500) {
        LogFileWriter.instance?.log(
          'resource pressure: mem=${(traffic.memory / 1024 / 1024).toStringAsFixed(1)}MB conns=${traffic.connections}',
          level: LogLevel.warning,
          name: 'tun',
        );
      }
    } catch (e) {
      LogFileWriter.instance?.log('$e', level: LogLevel.warning, name: 'poll');
      if (e is StateError) stopPolling();
    }
  }

  /// 同步内核真实状态（移动端引擎重建恢复时调用）
  Future<void> syncKernelState() async {
    try {
      final state = await _platform.queryState();
      stateSignal.value = state;
      if (state == kStateRunning) _onKernelRunning();
    } catch (e) {
      stateSignal.value = kStateInitialized;
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

  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) async {
    await _platform.startCoreWithContent(content, ruleSetProxy: ruleSetProxy);
  }

  Future<void> destroyCore() async {
    await _platform.destroyCore();
  }
  Future<void> resetNetwork() => _platform.resetNetwork();
  Future<List<ProxyGroup>> queryProxies() async =>
      (await _platform.queryProxies()).$1;
  Future<TrafficSnapshot> queryTraffic() => _platform.queryTraffic();
  Future<ConnectionEventsPayload> queryConnections() =>
      _platform.queryConnections();
  Future<void> selectProxy(String group, String tag) async {
    await _platform.selectProxy(group, tag);
    final current = Map<String, String>.from(selectedProxySignal.peek());
    current[group] = tag;
    selectedProxySignal.value = current;
  }
  Future<int> testDelay(String name, {int timeoutMs = 3000}) =>
      _platform.testDelay(name, timeoutMs: timeoutMs);

  Future<void> setMode(String mode) async {
    await _platform.setMode(mode);
    // 当前模式由内核回调 (eventType=2) 更新
  }

  Future<void> setGroupExpand(String group, bool expand) =>
      _platform.setGroupExpand(group, expand);
  Future<void> closeConnection(String id) => _platform.closeConnection(id);
  Future<void> closeAllConnections() => _platform.closeAllConnections();
  Future<void> setLogLevel(int level) => _platform.setLogLevel(level);
  Future<void> setMemoryLimit(int bytes) => _platform.setMemoryLimit(bytes);
  Future<void> flushSystemDNS() => _platform.flushSystemDNS();
  Future<String> checkConfig(String content) => _platform.checkConfig(content);
  Future<String> getVersion() => _platform.getVersion();
  Future<String> queryMode() => _platform.queryMode();
  Future<String> queryState() => _platform.queryState();
  Future<Map<String, int>> testGroupDelay(String group, {int timeoutMs = 3000}) =>
      _platform.testGroupDelay(group, timeoutMs: timeoutMs);
  Future<void> flushFakeIP() => _platform.flushFakeIP();
  Future<void> flushDNSCache() => _platform.flushDNSCache();
  Future<void> triggerGC() => _platform.triggerGC();
  Future<void> connectVpn(
    String configContent, {
    String? ruleSetProxy,
    bool? ipv6,
  }) async {
    await _platform.connectVpn(
      configContent,
      ruleSetProxy: ruleSetProxy,
      ipv6: ipv6,
    );
  }

  Future<void> disconnectVpn() async {
    await _platform.disconnectVpn();
  }

  Future<bool> isVpnRunning() => _platform.isVpnRunning();

  // --- Proxy query helper ---

  void _queryAndUpdate() {
    _platform.queryProxies().then((result) {
      proxiesSignal.value = result.$1;
      final selected = <String, String>{};
      for (final g in result.$1) {
        if (g.selected.isNotEmpty) selected[g.tag] = g.selected;
      }
      selectedProxySignal.value = selected;
      if (result.$2.isNotEmpty) _proxyDelays.value = result.$2;
    }).catchError((e) {
      LogFileWriter.instance?.log('$e', level: LogLevel.warning, name: 'proxies');
    });
  }

  void _fetchAvailableModes() {
    _platform.queryMode().then((modeJson) {
      final decoded = jsonDecode(modeJson) as Map<String, dynamic>;
      final available = decoded['modes'];
      if (available is List) {
        availableModesSignal.value = available
            .map((e) => (e as String).toLowerCase())
            .toList();
      }
    }).catchError((_) {});
  }

  // --- VPN traffic ---

  void _updateVpnTraffic(TrafficSnapshot traffic) {
    if (Constants.isDesktop) return;
    _platform.updateVpnTraffic(traffic);
  }

  // --- Shared response parsers ---

  static (List<ProxyGroup>, Map<String, int>) parseProxiesJson(dynamic json) {
    if (json is! List) return (<ProxyGroup>[], <String, int>{});
    final groups = <ProxyGroup>[];
    final delays = <String, int>{};
    for (final item in json) {
      final map = item as Map<String, dynamic>;
      final group = ProxyGroup.fromJson(map);
      groups.add(group);
      final rawItems = map['items'] as List?;
      if (rawItems != null) {
        for (int i = 0; i < rawItems.length && i < group.items.length; i++) {
          final rawItem = rawItems[i] as Map<String, dynamic>?;
          if (rawItem != null) {
            final delay = (rawItem['delay'] as num?)?.toInt();
            if (delay != null) delays[group.items[i].tag] = delay;
          }
        }
      }
    }
    return (groups, delays);
  }

  static TrafficSnapshot parseTrafficJson(dynamic json) {
    if (json is! Map<String, dynamic>) return TrafficSnapshot();
    return TrafficSnapshot.fromKernelJson(json);
  }

  static ConnectionEventsPayload parseConnectionsJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return ConnectionEventsPayload(reset: true, items: []);
    }
    return ConnectionEventsPayload.fromJson(json);
  }

  static Map<String, int> parseGroupDelayJson(dynamic json) {
    if (json is! Map<String, dynamic>) return {};
    return json.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  static String parseVersionJson(dynamic result) {
    if (result is String) {
      try {
        final decoded = jsonDecode(result);
        if (decoded is Map<String, dynamic>) {
          return decoded['version'] as String? ?? result;
        }
      } catch (_) {}
      return result;
    }
    if (result is Map<String, dynamic>) {
      return result['version'] as String? ?? result.toString();
    }
    return result?.toString() ?? '';
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
}

/// Desktop FFI backend using FfiWorker.
class _FfiWorkerBackend implements LibCorePlatform {
  final FfiWorker _worker;
  _FfiWorkerBackend(this._worker);

  @override
  Future<void> init() async {}

  @override
  Future<void> initCore(String homeDir) => _worker.invoke('CoreInit', {
        'optionsJSON': jsonEncode({'home_dir': homeDir, 'log_max_lines': 500}),
      });

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) =>
      _worker.invoke('CoreStartWithContent', {
        'content': content,
        'ruleSetProxy': ruleSetProxy ?? '',
      });

  @override
  Future<void> destroyCore() => _worker.invoke('CoreDestroy');

  @override
  Future<void> resetNetwork() => _worker.invoke('CoreResetNetwork');

  @override
  Future<(List<ProxyGroup>, Map<String, int>)> queryProxies() async {
    final json = await _worker.invoke<dynamic>('CoreQueryProxies');
    return LibCore.parseProxiesJson(json);
  }

  @override
  Future<TrafficSnapshot> queryTraffic() async {
    final json = await _worker.invoke<dynamic>('CoreQueryStats');
    return LibCore.parseTrafficJson(json);
  }

  @override
  Future<ConnectionEventsPayload> queryConnections() async {
    final json = await _worker.invoke<dynamic>('CoreQueryConnections');
    return LibCore.parseConnectionsJson(json);
  }

  @override
  Future<void> selectProxy(String group, String tag) =>
      _worker.invoke('CoreSelectProxy', {'group': group, 'tag': tag});

  @override
  Future<int> testDelay(String name, {int timeoutMs = 3000}) =>
      _worker.invoke<int>('CoreTestDelay', {'name': name, 'timeoutMs': timeoutMs});

  @override
  Future<Map<String, int>> testGroupDelay(String group, {int timeoutMs = 3000}) async {
    final json = await _worker.invoke<dynamic>(
        'CoreTestGroupDelay', {'group': group, 'timeoutMs': timeoutMs});
    return LibCore.parseGroupDelayJson(json);
  }

  @override
  Future<void> setMode(String mode) =>
      _worker.invoke('CoreSetMode', {'mode': mode});

  @override
  Future<void> setGroupExpand(String group, bool expand) =>
      _worker.invoke('CoreSetGroupExpand', {'group': group, 'expand': expand});

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
  Future<String> queryState() => _worker.invoke<String>('CoreQueryState');

  @override
  Future<void> flushSystemDNS() => _worker.invoke('CoreFlushSystemDNS');

  @override
  Future<String> queryMode() async {
    final json = await _worker.invoke<dynamic>('CoreQueryMode');
    return jsonEncode(json);
  }

  @override
  Future<void> flushFakeIP() => _worker.invoke('CoreFlushFakeIP');

  @override
  Future<void> flushDNSCache() => _worker.invoke('CoreFlushDNSCache');

  @override
  Future<void> triggerGC() => _worker.invoke('CoreTriggerGC');

  @override
  Future<String> checkConfig(String content) async {
    try {
      await _worker.invoke('CoreCheckConfig', {'content': content});
      return '';
    } on LibCoreException catch (e) {
      return e.message;
    }
  }

  @override
  Future<String> getVersion() async {
    final result = await _worker.invoke<String>('CoreGetVersion');
    return LibCore.parseVersionJson(result);
  }

  @override
  Future<void> connectVpn(
    String configContent, {
    String? ruleSetProxy,
    bool? ipv6,
  }) {
    throw UnsupportedError('connectVpn is only available on mobile platforms');
  }

  @override
  Future<void> disconnectVpn() {
    throw UnsupportedError(
      'disconnectVpn is only available on mobile platforms',
    );
  }

  @override
  Future<bool> isVpnRunning() async => false;

  @override
  void updateVpnTraffic(TrafficSnapshot traffic) {}
}
