import 'dart:async';
import 'dart:convert';

import 'package:signals_flutter/signals_flutter.dart';

import '../domain/connection.dart';
import '../domain/enums.dart';
import '../domain/log.dart';
import '../domain/net_speed.dart';
import '../domain/proxy_group.dart';
import '../utils/constants.dart';
import '../utils/log_file.dart';
import 'ipc_worker.dart';
import 'lib_core_channel.dart';
import 'service_manager.dart';

abstract class LibCorePlatform {
  Future<void> init();
  Future<void> initCore(String homeDir);
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy});
  Future<void> stopCore();
  Future<void> resetNetwork();
  Future<(List<ProxyGroup>, Map<String, int>)> queryProxies();
  Future<CoreStats> queryStats();
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
  void updateVpnStats(CoreStats stats);
}

class LibCore {
  static final LibCore instance = LibCore._();
  LibCore._();

  static const kStateCreated = 'created';
  static const kStateInitialized = 'initialized';
  static const kStateStarting = 'starting';
  static const kStateStopping = 'stopping';
  static const kStateRunning = 'running';
  static const kStateDestroyed = 'destroyed';

  static const _evtLog = 0;
  static const _evtUrlTest = 1;
  static const _evtModeUpdate = 2;
  static const _evtConnEvent = 3;
  static const _evtStateUpdate = 4;
  static const _evtTrafficUpdate = 5;
  static const _evtDisconnectRequested = 6;

  late final LibCorePlatform _platform;
  IpcWorker? _ipcWorker;
  ServiceManager? _serviceManager;

  ServiceManager? get serviceManager => _serviceManager;

  final statsSignal = signal<CoreStats?>(null);
  final activeConnectionsSignal = signal<int>(0);
  final proxiesSignal = signal<List<ProxyGroup>>([]);
  final selectedProxySignal = signal<Map<String, String>>({});
  final _proxyDelays = signal<Map<String, int>>({});
  Signal<Map<String, int>> get proxyDelaysSignal => _proxyDelays;
  final modeSignal = signal<String>('rule');
  final stateSignal = signal<String>(kStateCreated);
  final availableModesSignal = signal<List<String>>([
    'rule',
    'global',
    'direct',
  ]);
  final proxyTogglingSignal = signal(false);
  /// True once the kernel has reached running state at least once since app launch.
  final kernelBooted = signal(false);
  void Function()? onDisconnectRequested;

  int _prevUpTotal = 0;
  int _prevDownTotal = 0;
  Timer? _pollTimer; // Only used on mobile
  bool _reconnecting = false;
  bool _disposed = false;

  LibCorePlatform get platform => _platform;

  Future<void> init() async {
    if (Constants.isDesktop) {
      _serviceManager = ServiceManager.create(Constants.homeDir.path);
      _ipcWorker = IpcWorker(ipcPath: _serviceManager!.ipcPath);
      _ipcWorker!.onCallback = _handleWorkerCallback;
      _ipcWorker!.onDisconnect = _onIpcDisconnected;

      // Try connecting to an already-running service first.
      // Do NOT probe with connect+disconnect (isRunning) before the IPC
      // worker is connected — cff-core exits when all GUI connections
      // disconnect and the core is not running.
      if (!await _connectWithRetry(attempts: 2)) {
        // Not running — start the service process with fallback
        if (!await _startAndConnectWithFallback()) {
          throw StateError('Failed to connect to service process');
        }
      }
      _platform = _ipcWorker!;

      // Recover state from running service (reconnect scenario)
      await syncKernelState();
    } else {
      final channel = LibCoreChannel();
      channel.onCallback = _handleWorkerCallback;
      _platform = channel;
      await _platform.init();
    }
    await LogFileWriter.init('${Constants.homeDir.path}/singcast.log');
  }

  Future<void> dispose() async {
    _disposed = true;
    stopPolling();
    try {
      await stopCore();
    } catch (_) {}
    await _ipcWorker?.disconnect();
  }

  /// Called when IPC connection drops unexpectedly (service process crash, etc.).
  void _onIpcDisconnected() {
    if (_disposed || _reconnecting) return;
    stateSignal.value = kStateDestroyed;
    _clearRuntimeState();
    stopPolling();
    _attemptReconnect();
  }

  Future<void> _attemptReconnect() async {
    if (_disposed || _reconnecting) return;
    _reconnecting = true;
    LogFileWriter.instance?.log('IPC disconnected, attempting reconnect', name: 'ipc');

    try {
      // Try reconnecting to an existing process first
      try {
        if (await _connectWithRetry(attempts: 5)) {
          await syncKernelState();
          LogFileWriter.instance?.log('IPC reconnected to existing process', name: 'ipc');
          return;
        }
      } catch (_) {}

      // Process is gone — restart with fallback
      try {
        await _serviceManager!.stop();
        if (await _startAndConnectWithFallback()) {
          await syncKernelState();
          LogFileWriter.instance?.log('IPC reconnected via new process', name: 'ipc');
        } else {
          LogFileWriter.instance?.log('IPC reconnect failed', level: LogLevel.error, name: 'ipc');
        }
      } catch (e) {
        LogFileWriter.instance?.log('IPC reconnect failed: $e', level: LogLevel.error, name: 'ipc');
      }
    } finally {
      _reconnecting = false;
    }
  }

  /// Try to connect IPC with retries. Returns true on success.
  Future<bool> _connectWithRetry({int attempts = 20}) async {
    for (int i = 0; i < attempts; i++) {
      try {
        await _ipcWorker!.connect();
        return true;
      } catch (_) {
        if (i < attempts - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return false;
  }

  /// Start the service process and connect IPC.
  Future<bool> _startAndConnect({int attempts = 20}) async {
    if (!await _serviceManager!.start()) return false;
    return await _connectWithRetry(attempts: attempts);
  }

  /// Start the service process and connect IPC, with fallback to built-in core.
  Future<bool> _startAndConnectWithFallback() async {
    // Try privileged/elevated core first
    if (await _startAndConnect()) return true;
    // Fallback: stop elevated service, start direct process (no UAC)
    await _serviceManager!.stop();
    if (!await _serviceManager!.startDirect()) return false;
    if (!await _connectWithRetry(attempts: 10)) return false;
    LogFileWriter.instance?.log(
      'Fallback: started with built-in core (TUN unavailable)',
      name: 'ipc',
    );
    return true;
  }

  /// Stop the service process, start a fresh one, and reconnect.
  Future<void> restart() async {
    if (!Constants.isDesktop) return;
    _reconnecting = true;
    try {
      stateSignal.value = kStateDestroyed;
      _clearRuntimeState();
      stopPolling();
      await stopCore();
      await _ipcWorker?.disconnect();
      await _serviceManager?.stop();
      if (!await _startAndConnectWithFallback()) {
        throw StateError('Failed to connect to service process');
      }
      await syncKernelState();
    } finally {
      _reconnecting = false;
    }
  }

  /// Uninstall elevated/privileged service, then restart with built-in core.
  Future<void> uninstallServiceAndRestart() async {
    if (!Constants.isDesktop) return;
    _reconnecting = true; // Block automatic reconnect during transition
    try {
      stateSignal.value = kStateDestroyed;
      _clearRuntimeState();
      stopPolling();
      try {
        await stopCore();
      } catch (_) {}
      await _ipcWorker?.disconnect();
      await _serviceManager?.stop();
      await _serviceManager!.uninstall();
      if (!await _startAndConnect(attempts: 10)) {
        throw StateError('Failed to connect to service process');
      }
      await syncKernelState();
    } finally {
      _reconnecting = false;
    }
  }

  void _handleWorkerCallback(int eventType, String payload) {
    switch (eventType) {
      case _evtLog:
        final json = jsonDecode(payload) as Map<String, dynamic>;
        LogFileWriter.instance?.writeAll([LogEntry.fromJson(json)]);
      case _evtUrlTest:
        _queryAndUpdate();
      case _evtModeUpdate:
        modeSignal.value = payload.toLowerCase();
      case _evtConnEvent:
        break;
      case _evtStateUpdate:
        final newState = payload;
        final oldState = stateSignal.peek();
        LogFileWriter.instance?.log(
          'StateUpdate: $oldState -> $newState',
          name: 'tun',
        );
        if (newState == oldState) break;
        stateSignal.value = newState;
        if (newState == kStateRunning) {
          kernelBooted.value = true;
          proxyTogglingSignal.value = false;
          _onKernelRunning();
        } else {
          if (newState == kStateInitialized || newState == kStateDestroyed) {
            proxyTogglingSignal.value = false;
          }
          stopPolling();
          _clearRuntimeState();
        }
      case _evtTrafficUpdate:
        if (Constants.isDesktop) {
          _handleTrafficUpdate(payload);
        }
      case _evtDisconnectRequested:
        LogFileWriter.instance?.log('DisconnectRequested: from notification', name: 'tun');
        onDisconnectRequested?.call();
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

  void clearStats() {
    statsSignal.value = null;
  }

  void _clearRuntimeState() {
    statsSignal.value = null;
    activeConnectionsSignal.value = 0;
    proxiesSignal.value = [];
    _proxyDelays.value = {};
  }

  void _onKernelRunning() {
    _queryAndUpdate();
    _fetchAvailableModes();
    if (!Constants.isDesktop) {
      startPolling();
    }
  }

  // --- Polling ---

  void startPolling() {
    if (_pollTimer != null) return;
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

      final raw = await queryStats();
      final stats = _applyStats(raw);
      _updateVpnStats(stats);

      if (stats.up > 1024 && stats.down == 0) {
        LogFileWriter.instance?.log(
          'traffic anomaly: up=${stats.up} down=${stats.down} conns=${stats.connections} mem=${stats.memory}',
          level: LogLevel.warning,
          name: 'tun',
        );
      }
      if (stats.memory > 100 * 1024 * 1024 || stats.connections > 500) {
        LogFileWriter.instance?.log(
          'resource pressure: mem=${(stats.memory / 1024 / 1024).toStringAsFixed(1)}MB conns=${stats.connections}',
          level: LogLevel.warning,
          name: 'tun',
        );
      }
    } catch (e) {
      LogFileWriter.instance?.log('$e', level: LogLevel.warning, name: 'poll');
      if (e is StateError) stopPolling();
    }
  }

  /// 从后端同步内核真实状态（移动端引擎重建 / 桌面端重连时调用）。
  Future<void> syncKernelState({String fallback = kStateInitialized}) async {
    try {
      final state = await _platform.queryState();
      stateSignal.value = state;
      if (state == kStateRunning) {
        kernelBooted.value = true;
        _onKernelRunning();
      }
    } catch (_) {
      stateSignal.value = fallback;
    }
  }

  // --- Delegated methods ---

  Future<void> initCore(String homeDir) async {
    await _platform.initCore(homeDir);
  }

  Future<void> startCoreWithContent(
    String content, {
    String? ruleSetProxy,
  }) async {
    await _platform.startCoreWithContent(content, ruleSetProxy: ruleSetProxy);
  }

  Future<void> stopCore() async {
    if (stateSignal.peek() == kStateRunning) {
      stateSignal.value = kStateStopping;
    }
    await _platform.stopCore();
  }

  Future<void> resetNetwork() => _platform.resetNetwork();
  Future<List<ProxyGroup>> queryProxies() async =>
      (await _platform.queryProxies()).$1;
  Future<CoreStats> queryStats() => _platform.queryStats();
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
    // 当前模式由内核回调 (_evtModeUpdate) 更新
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
  Future<Map<String, int>> testGroupDelay(
    String group, {
    int timeoutMs = 3000,
  }) => _platform.testGroupDelay(group, timeoutMs: timeoutMs);
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
    _platform
        .queryProxies()
        .then((result) {
          proxiesSignal.value = result.$1;
          final selected = <String, String>{};
          for (final g in result.$1) {
            if (g.selected.isNotEmpty) selected[g.tag] = g.selected;
          }
          selectedProxySignal.value = selected;
          if (result.$2.isNotEmpty) _proxyDelays.value = result.$2;
        })
        .catchError((e) {
          LogFileWriter.instance?.log(
            '$e',
            level: LogLevel.warning,
            name: 'proxies',
          );
        });
  }

  void _fetchAvailableModes() {
    _platform
        .queryMode()
        .then((modeJson) {
          final decoded = jsonDecode(modeJson) as Map<String, dynamic>;
          final available = decoded['modes'];
          if (available is List) {
            availableModesSignal.value = available
                .map((e) => (e as String).toLowerCase())
                .toList();
          }
        })
        .catchError((_) {});
  }

  /// Handle traffic update pushed from IPC service (replaces _poll on desktop).
  void _handleTrafficUpdate(String payload) {
    try {
      _applyStats(parseStatsJson(jsonDecode(payload)));
    } catch (e) {
      LogFileWriter.instance?.log(
        '$e',
        level: LogLevel.warning,
        name: 'traffic',
      );
    }
  }

  /// Compute per-second speeds and update stat signals.
  CoreStats _applyStats(CoreStats raw) {
    final upSpeed = (raw.upTotal - _prevUpTotal).clamp(0, raw.upTotal);
    final downSpeed = (raw.downTotal - _prevDownTotal).clamp(0, raw.downTotal);
    _prevUpTotal = raw.upTotal;
    _prevDownTotal = raw.downTotal;

    final stats = CoreStats(
      up: upSpeed,
      down: downSpeed,
      upTotal: raw.upTotal,
      downTotal: raw.downTotal,
      memory: raw.memory,
      connections: raw.connections,
      startedAt: raw.startedAt,
    );
    statsSignal.value = stats;
    activeConnectionsSignal.value = stats.connections;
    return stats;
  }

  // --- VPN stats ---

  void _updateVpnStats(CoreStats stats) {
    if (Constants.isDesktop) return;
    _platform.updateVpnStats(stats);
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

  static CoreStats parseStatsJson(dynamic json) {
    if (json is! Map<String, dynamic>) return CoreStats();
    return CoreStats.fromKernelJson(json);
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
}
