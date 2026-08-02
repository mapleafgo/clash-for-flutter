import 'dart:async';
import 'dart:convert';

import '../domain/connection.dart';
import '../domain/enums.dart';
import '../domain/proxy_group.dart';
import '../utils/log_file.dart';
import 'ipc/json_rpc_client.dart';
import 'event_types.dart';
import 'lib_core.dart';

/// IPC-based backend for desktop platforms.
/// JSON-RPC 2.0 over Unix Socket / Named Pipe.
class IpcWorker implements LibCorePlatform {
  JsonRpcClient? _client;
  StreamSubscription? _logSub;
  StreamSubscription? _urlTestSub;
  StreamSubscription? _modeUpdateSub;
  StreamSubscription? _connEventSub;
  StreamSubscription? _stateUpdateSub;
  StreamSubscription? _trafficUpdateSub;

  void Function(int eventType, String payload)? onCallback;

  /// Called when IPC connection is lost unexpectedly.
  void Function()? onDisconnect;

  final String ipcPath;

  /// VPN lifecycle hooks, injected on mobile RPC platforms (iOS) where the
  /// kernel runs in a Network Extension and VPN is driven via MethodChannel.
  /// Null on desktop → connectVpn/disconnectVpn throw UnsupportedError.
  Future<void> Function(String configContent, {String? ruleSetProxy, bool? ipv6})? connectVpnImpl;
  Future<void> Function()? disconnectVpnImpl;
  Future<bool> Function()? isVpnRunningImpl;

  /// 内核启动/重启钩子,注入于内核需重新 SetTunFd 的平台(iOS)。
  /// iOS 上裸 RPC core.startWithContent 会因 tunFd 已被消费而失败,故走
  /// MethodChannel 让 Extension 本地 SetTunFd + StartWithContent。null → RPC。
  Future<void> Function(String content, {String? ruleSetProxy})? startCoreWithContentImpl;

  /// 移动端本地转换钩子（iOS）：主 App 无 RPC 连接时也能转订阅。
  Future<String> Function(String content)? convertImpl;

  IpcWorker({required this.ipcPath});

  Future<void> connect() async {
    // 重入保护：直接覆盖 _client 会泄漏旧 socket、6 个事件订阅和 6 个
    // broadcast controller，且旧 client 的 onDisconnect 仍可能回调。
    if (_client != null) await disconnect();
    _client = JsonRpcClient(path: ipcPath);
    _client!.onDisconnect = () => onDisconnect?.call();
    await _client!.connect();
    _subscribeEvents();
  }

  void _subscribeEvents() {
    final c = _client!;

    _logSub = c.notifications('event.log').listen((n) {
      onCallback?.call(CoreEventType.log, jsonEncode(n.params));
    });

    _urlTestSub = c.notifications('event.urlTest').listen((n) {
      onCallback?.call(CoreEventType.urlTest, '');
    });

    _modeUpdateSub = c.notifications('event.modeUpdate').listen((n) {
      final mode = (n.params as Map<String, dynamic>?)?['mode'] as String? ?? '';
      onCallback?.call(CoreEventType.modeUpdate, mode);
    });

    _connEventSub = c.notifications('event.connEvent').listen((n) {
      onCallback?.call(CoreEventType.connEvent, jsonEncode(n.params));
    });

    _stateUpdateSub = c.notifications('event.stateUpdate').listen((n) {
      final state = (n.params as Map<String, dynamic>?)?['state'] as String? ?? '';
      onCallback?.call(CoreEventType.stateUpdate, state);
    });

    _trafficUpdateSub = c.notifications('event.trafficUpdate').listen((n) {
      onCallback?.call(CoreEventType.trafficUpdate, jsonEncode(n.params));
    });
  }

  Future<void> disconnect() async {
    await Future.wait([
      _logSub?.cancel() ?? Future.value(),
      _urlTestSub?.cancel() ?? Future.value(),
      _modeUpdateSub?.cancel() ?? Future.value(),
      _connEventSub?.cancel() ?? Future.value(),
      _stateUpdateSub?.cancel() ?? Future.value(),
      _trafficUpdateSub?.cancel() ?? Future.value(),
    ]);
    _logSub = null;
    _urlTestSub = null;
    _modeUpdateSub = null;
    _connEventSub = null;
    _stateUpdateSub = null;
    _trafficUpdateSub = null;
    try {
      await _client?.disconnect().timeout(const Duration(seconds: 3));
    } catch (e) {
      LogFileWriter.instance?.log(
        'IPC disconnect timed out: $e',
        level: LogLevel.warning,
        name: 'ipc',
      );
    }
    _client?.dispose();
    _client = null;
  }

  bool get isConnected => _client?.isConnected ?? false;

  @override
  Future<void> init() async {}

  @override
  Future<void> initCore(String homeDir) async {
    // Service process handles init internally via --home-dir flag.
    // No-op on IPC side.
  }

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy, bool enabledVpn = false}) {
    final impl = startCoreWithContentImpl;
    if (impl != null) {
      return impl(content, ruleSetProxy: ruleSetProxy);
    }
    return _call('core.startWithContent', {
      'content': content,
      'rule_set_proxy': ruleSetProxy ?? '',
    });
  }

  @override
  Future<void> stopCore() => _call('core.stop');

  @override
  Future<(List<ProxyGroup>, Map<String, int>)> queryProxies() async {
    final json = await _call('core.queryProxies');
    return LibCore.parseProxiesJson(json);
  }

  @override
  Future<ConnectionEventsPayload> queryConnections() async {
    final json = await _call('core.queryConnections');
    return LibCore.parseConnectionsJson(json);
  }

  @override
  Future<void> selectProxy(String group, String tag) =>
      _call('core.selectProxy', {'group_tag': group, 'outbound_tag': tag});

  @override
  Future<int> testDelay(String name, {int timeoutMs = 3000}) async {
    final result = await _call('core.testDelay', {
      'tag': name,
      'timeout_ms': timeoutMs,
    });
    return (result as Map<String, dynamic>?)?['delay'] as int? ?? -1;
  }

  @override
  Future<Map<String, int>> testGroupDelay(String group, {int timeoutMs = 3000}) async {
    final json = await _call('core.testGroupDelay', {
      'group_tag': group,
      'timeout_ms': timeoutMs,
    });
    return LibCore.parseGroupDelayJson(json);
  }

  @override
  Future<void> setMode(String mode) =>
      _call('core.setMode', {'mode': mode});

  @override
  Future<void> setGroupExpand(String group, bool expand) =>
      _call('core.setGroupExpand', {'group_tag': group, 'expand': expand});

  @override
  Future<void> closeConnection(String id) =>
      _call('core.closeConnection', {'id': id});

  @override
  Future<void> closeAllConnections() => _call('core.closeAllConnections');

  @override
  Future<void> setLogLevel(int level) =>
      _call('core.setLogLevel', {'level': level});

  @override
  Future<void> setMemoryLimit(int bytes) {
    // Not in the IPC protocol — no-op
    return Future.value();
  }

  @override
  Future<String> queryState() async =>
      (await _call('core.queryState')) as String? ?? LibCore.kStateCreated;

  @override
  Future<void> flushSystemDNS() => _call('core.flushSystemDNS');

  @override
  Future<String> queryMode() async {
    final json = await _call('core.queryMode');
    if (json == null) return '{}';
    return jsonEncode(json);
  }

  @override
  Future<void> flushFakeIP() => _call('core.flushFakeIP');

  @override
  Future<void> flushDNSCache() => _call('core.flushDNSCache');

  @override
  Future<void> triggerGC() => _call('core.triggerGC');

  @override
  Future<String> checkConfig(String content) async {
    try {
      final result = await _call('core.checkConfig', {'content': content});
      if (result is Map<String, dynamic>) {
        return result['error'] as String? ?? '';
      }
      return '';
    } on JsonRpcException catch (e) {
      return e.error.message;
    }
  }

  @override
  Future<String> convert(String content) {
    final impl = convertImpl;
    if (impl != null) return impl(content);
    return _convertRpc(content);
  }

  Future<String> _convertRpc(String content) async {
    final result = await _call('core.convert', {'content': content});
    if (result is Map<String, dynamic>) {
      final json = result['json'] as String?;
      if (json != null && json.isNotEmpty) return json;
    }
    throw StateError('core.convert returned no json result');
  }

  @override
  Future<String> getVersion() async {
    final result = await _call('core.getVersion');
    return LibCore.parseVersionJson(result);
  }

  @override
  Future<void> connectVpn(
    String configContent, {
    String? ruleSetProxy,
    bool? ipv6,
  }) {
    final impl = connectVpnImpl;
    if (impl != null) {
      return impl(configContent, ruleSetProxy: ruleSetProxy, ipv6: ipv6);
    }
    throw UnsupportedError('connectVpn is only available on mobile platforms');
  }

  @override
  Future<void> disconnectVpn() {
    final impl = disconnectVpnImpl;
    if (impl != null) return impl();
    throw UnsupportedError('disconnectVpn is only available on mobile platforms');
  }

  @override
  Future<bool> isVpnRunning() {
    final impl = isVpnRunningImpl;
    if (impl != null) return impl();
    return Future.value(false);
  }

  Future<dynamic> _call(String method, [Map<String, dynamic>? params]) {
    if (_client == null || !_client!.isConnected) {
      throw StateError('IPC not connected');
    }
    return _client!.call(method, params);
  }
}
