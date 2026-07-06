import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:signals_flutter/signals_flutter.dart';

import '../domain/connection.dart';
import '../domain/enums.dart';
import '../domain/log.dart';
import '../domain/net_speed.dart';
import '../domain/proxy_group.dart';
import '../utils/constants.dart';
import '../utils/log_file.dart';
import 'event_types.dart';
import 'ipc_worker.dart';
import 'ios_vpn_bridge.dart';
import 'lib_core_channel.dart';
import 'service_manager.dart';

abstract class LibCorePlatform {
  Future<void> init();
  Future<void> initCore(String homeDir);
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy, bool enabledVpn = false});
  Future<void> stopCore();
  Future<(List<ProxyGroup>, Map<String, int>)> queryProxies();
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
  /// Called after process restart (restart / uninstall) completes and IPC reconnects.
  /// The app layer uses this to re-activate the kernel profile.
  Future<void> Function()? onProcessReady;

  int _prevUpTotal = 0;
  int _prevDownTotal = 0;
  bool _reconnecting = false;
  bool _disposed = false;

  /// Heartbeat: actively probe IPC with queryState to detect zombie connections.
  Timer? _heartbeatTimer;
  bool _heartbeatInProgress = false;
  static const _heartbeatInterval = Duration(seconds: 10);
  static const _heartbeatTimeout = Duration(seconds: 3);

  LibCorePlatform get platform => _platform;

  Future<void> init() async {
    // Desktop (macOS/Windows/Linux): 独立进程 + RPC
    if (Constants.isDesktop) {
      _serviceManager = ServiceManager.create(Constants.homeDir.path);
      _ipcWorker = IpcWorker(ipcPath: _serviceManager!.ipcPath);
      _ipcWorker!.onCallback = _handleWorkerCallback;
      _ipcWorker!.onDisconnect = _onIpcDisconnected;

      // Try connecting to an already-running service first.
      // Do NOT probe with connect+disconnect (isRunning) before the IPC
      // worker is connected — singcast-cli exits when all GUI connections
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
    // iOS: Network Extension 进程 + RPC
    } else if (Platform.isIOS) {
      final bridge = IosVpnBridge();
      final socketPath = await bridge.appGroupSocketPath();
      _ipcWorker = IpcWorker(ipcPath: socketPath);
      _ipcWorker!.onCallback = _handleWorkerCallback;
      _ipcWorker!.onDisconnect = _onIpcDisconnected;
      bridge.wireInto(_ipcWorker!, onVpnDisconnected: _onVpnDisconnected);
      _platform = _ipcWorker!;
      // iOS Extension 进程在 VPN 开启时才启动，RPC 连接延迟到 connectVpn() 后
    // Android: 本进程 FFI
    } else {
      final channel = LibCoreChannel();
      channel.onCallback = _handleWorkerCallback;
      channel.onVpnDisconnected = _onVpnDisconnected;
      _platform = channel;
      await _platform.init();
    }
    await LogFileWriter.init('${Constants.homeDir.path}/singcast.log');
  }

  /// iOS:连接 Extension 内核的 RPC socket。
  ///
  /// 在 connectVpn() 后调用，此时 Extension 进程已启动，RPC server 可用。
  /// 带重试以等待 Extension 开启 socket。桌面/Android 不使用。
  Future<void> connectIpc() async {
    if (_ipcWorker == null) return;
    if (!await _connectWithRetry(attempts: 20)) {
      throw StateError('Failed to connect to Extension RPC socket');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _heartbeatTimer?.cancel();
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
    _attemptReconnect();
  }

  Future<void> _attemptReconnect() async {
    if (_disposed || _reconnecting) return;
    // 移动端无独立内核进程:iOS 内核跑在 Extension、Android 走本进程 FFI,
    // _serviceManager 仅桌面 init() 创建(为 null)。桌面端的进程重启逻辑在此
    // 不适用 —— 直接走到 `_serviceManager!.stop()` 会解引用 null 而崩溃。
    // iOS RPC 断开通常意味着 VPN 停止(Extension 退出);不自动重连,等用户
    // 重新开 VPN 时由 connectVpn → connectIpc 恢复。
    if (!Constants.isDesktop) {
      LogFileWriter.instance?.log(
        'IPC disconnected; awaiting reconnect via VPN toggle',
        level: LogLevel.warning,
        name: 'ipc',
      );
      return;
    }
    _reconnecting = true;
    _heartbeatTimer?.cancel();

    try {
      // Quick probe: 1 attempt to see if the existing process is still alive.
      // If the kernel is frozen, connect succeeds but syncKernelState will
      // timeout — fall through to restart the process.
      try {
        if (await _connectWithRetry(attempts: 1)) {
          await syncKernelState();
          _startHeartbeat();
          return;
        }
      } catch (_) {}

      // Process is gone — restart with fallback
      try {
        await _serviceManager!.stop();
        if (await _startAndConnectWithFallback()) {
          await syncKernelState();
          try {
            await onProcessReady?.call();
          } catch (e) {
            LogFileWriter.instance?.log(
              'onProcessReady failed: $e',
              level: LogLevel.warning,
              name: 'ipc',
            );
          }
          _startHeartbeat();
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

  /// Start the IPC heartbeat timer.
  ///
  /// Should be called after all startup initialization is complete.
  /// Reconnect scenarios also call this internally via [_attemptReconnect].
  void startHeartbeat() {
    if (!Constants.isDesktop) return;
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _heartbeatProbe();
    });
  }

  /// Send a queryState RPC to probe IPC liveness.
  Future<void> _heartbeatProbe() async {
    if (_disposed || _reconnecting || _heartbeatInProgress) return;
    _heartbeatInProgress = true;
    try {
      await _platform.queryState().timeout(_heartbeatTimeout);
    } catch (e) {
      // IPC is dead — disconnect and trigger reconnect.
      LogFileWriter.instance?.log(
        'IPC heartbeat failed: $e, reconnecting',
        level: LogLevel.warning,
        name: 'ipc',
      );
      _heartbeatTimer?.cancel();
      try {
        await _ipcWorker?.disconnect();
      } catch (_) {}
      _onIpcDisconnected();
    } finally {
      _heartbeatInProgress = false;
    }
  }

  /// Try to connect IPC with retries. Returns true on success.
  /// 带指数退避的 RPC 连接重试。
  ///
  /// [maxDelayMs] 单次延迟上限(默认 3000ms)，[totalTimeoutMs] 总超时(默认 10000ms)。
  /// 首次立即尝试，后续延迟按 100 * 2^i 递增，直到达到上限或总超时。
  Future<bool> _connectWithRetry({
    int attempts = 20,
    int maxDelayMs = 3000,
    int totalTimeoutMs = 10000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: totalTimeoutMs));
    for (int i = 0; i < attempts; i++) {
      if (DateTime.now().isAfter(deadline)) break;
      try {
        await _ipcWorker!.connect();
        return true;
      } catch (_) {
        if (i < attempts - 1 && DateTime.now().isBefore(deadline)) {
          final delay = Duration(milliseconds: (100 * (1 << i)).clamp(100, maxDelayMs));
          await Future.delayed(delay);
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
      try {
        await stopCore().timeout(const Duration(seconds: 5));
      } catch (_) {}
      await _ipcWorker?.disconnect();
      await _serviceManager?.stop();
      if (!await _startAndConnectWithFallback()) {
        throw StateError('Failed to connect to service process');
      }
      await syncKernelState();
      await onProcessReady?.call();
    } finally {
      _reconnecting = false;
    }
  }

  /// One-time privilege setup for TUN mode.
  /// Disconnects IPC and blocks automatic reconnection during elevation
  /// to prevent _attemptReconnect() from spawning a non-elevated process
  /// that would race with the elevated service.install RPC.
  Future<bool> elevateService() async {
    _reconnecting = true;
    try {
      await _ipcWorker?.disconnect();
      return await _serviceManager!.setup();
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
      try {
        await stopCore();
      } catch (_) {}
      await _ipcWorker?.disconnect();
      await _serviceManager?.stop();
      await _serviceManager!.uninstall();
      if (!await _serviceManager!.startDirect()) {
        throw StateError('Failed to start direct process');
      }
      if (!await _connectWithRetry(attempts: 10)) {
        throw StateError('Failed to connect to service process');
      }
      await syncKernelState();
      await onProcessReady?.call();
    } finally {
      _reconnecting = false;
    }
  }

  void _handleWorkerCallback(int eventType, String payload) {
    switch (eventType) {
      case CoreEventType.log:
        final json = jsonDecode(payload) as Map<String, dynamic>;
        LogFileWriter.instance?.writeAll([LogEntry.fromJson(json)]);
      case CoreEventType.urlTest:
        _queryAndUpdate();
      case CoreEventType.modeUpdate:
        modeSignal.value = payload.toLowerCase();
      case CoreEventType.connEvent:
        break;
      case CoreEventType.stateUpdate:
        final newState = payload;
        final oldState = stateSignal.peek();
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
          _clearRuntimeState();
        }
      case CoreEventType.trafficUpdate:
        _handleTrafficUpdate(payload);
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
    _prevUpTotal = 0;
    _prevDownTotal = 0;
  }

  void _onKernelRunning() {
    _queryAndUpdate();
    _fetchAvailableModes();
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
    bool enabledVpn = false,
  }) async {
    // iOS: 内核只在 VPN 开启时运行，非 TUN 模式下忽略热重载
    if (Platform.isIOS && !enabledVpn) {
      LogFileWriter.instance?.log(
        'startCoreWithContent ignored: VPN not connected on iOS',
        level: LogLevel.debug,
        name: 'core',
      );
      return;
    }
    await _platform.startCoreWithContent(content, ruleSetProxy: ruleSetProxy, enabledVpn: enabledVpn);
  }

  Future<void> stopCore() async {
    if (stateSignal.peek() == kStateRunning) {
      stateSignal.value = kStateStopping;
    }
    await _platform.stopCore();
  }

  Future<List<ProxyGroup>> queryProxies() async =>
      (await _platform.queryProxies()).$1;
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
    // iOS: VPN 开启后 Extension 进程已启动，RPC socket 可用，立即连接
    if (Platform.isIOS) {
      try {
        await connectIpc();
        await syncKernelState();
      } catch (e) {
        // 隧道已成功开启，RPC 连接失败不阻断 connectVpn
        LogFileWriter.instance?.log(
          'connectIpc after VPN start failed: $e',
          level: LogLevel.warning,
          name: 'ipc',
        );
      }
    }
  }

  Future<void> disconnectVpn() async {
    await _platform.disconnectVpn();
  }

  Future<bool> isVpnRunning() => _platform.isVpnRunning();

  // --- Proxy query helper ---

  void _queryAndUpdate() async {
    try {
      final result = await _platform.queryProxies();
      proxiesSignal.value = result.$1;
      final selected = <String, String>{};
      for (final g in result.$1) {
        if (g.selected.isNotEmpty) selected[g.tag] = g.selected;
      }
      selectedProxySignal.value = selected;
      if (result.$2.isNotEmpty) _proxyDelays.value = result.$2;
    } catch (e) {
      LogFileWriter.instance?.log(
        '$e',
        level: LogLevel.warning,
        name: 'proxies',
      );
    }
  }

  void _fetchAvailableModes() async {
    try {
      final modeJson = await _platform.queryMode();
      final decoded = jsonDecode(modeJson) as Map<String, dynamic>;
      final available = decoded['modes'];
      if (available is List) {
        availableModesSignal.value = available
            .map((e) => (e as String).toLowerCase())
            .toList();
      }
    } catch (e) {
      LogFileWriter.instance?.log(
        '$e',
        level: LogLevel.warning,
        name: 'modes',
      );
    }
  }

  /// Handle traffic stats pushed from kernel (both desktop IPC and mobile FFI).
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
  void _applyStats(CoreStats raw) {
    final upSpeed = (raw.upTotal - _prevUpTotal).clamp(0, raw.upTotal);
    final downSpeed = (raw.downTotal - _prevDownTotal).clamp(0, raw.downTotal);
    _prevUpTotal = raw.upTotal;
    _prevDownTotal = raw.downTotal;

    final stats = CoreStats.withSpeed(
      upSpeed: upSpeed,
      downSpeed: downSpeed,
      raw: raw,
    );
    statsSignal.value = stats;
    activeConnectionsSignal.value = stats.connections;
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

  void _onVpnDisconnected() {
    vpnDisconnected.add(null);
  }
}

/// VPN 通知栏断开事件，由 app.dart 监听并更新 UI 状态。
final vpnDisconnected = StreamController<void>.broadcast();
