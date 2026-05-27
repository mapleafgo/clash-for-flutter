import 'dart:async';
import 'dart:convert';

import '../domain/connection.dart';
import '../domain/net_speed.dart';
import '../domain/proxy_group.dart';
import 'ipc/json_rpc_client.dart';
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

  IpcWorker({required this.ipcPath});

  Future<void> connect() async {
    _client = JsonRpcClient(path: ipcPath);
    _client!.onDisconnect = () => onDisconnect?.call();
    await _client!.connect();
    _subscribeEvents();
  }

  void _subscribeEvents() {
    final c = _client!;

    // event.log → eventType 0
    _logSub = c.notifications('event.log').listen((n) {
      onCallback?.call(0, jsonEncode(n.params));
    });

    // event.urlTest → eventType 1
    _urlTestSub = c.notifications('event.urlTest').listen((n) {
      onCallback?.call(1, '');
    });

    // event.modeUpdate → eventType 2
    _modeUpdateSub = c.notifications('event.modeUpdate').listen((n) {
      final mode = (n.params as Map<String, dynamic>?)?['mode'] as String? ?? '';
      onCallback?.call(2, mode);
    });

    // event.connEvent → eventType 3
    _connEventSub = c.notifications('event.connEvent').listen((n) {
      onCallback?.call(3, jsonEncode(n.params));
    });

    // event.stateUpdate → eventType 4
    _stateUpdateSub = c.notifications('event.stateUpdate').listen((n) {
      final state = (n.params as Map<String, dynamic>?)?['state'] as String? ?? '';
      onCallback?.call(4, state);
    });

    // event.trafficUpdate → replaces _poll()
    _trafficUpdateSub = c.notifications('event.trafficUpdate').listen((n) {
      // Re-use traffic update as stats signal update
      // The payload is already the stats JSON from Go QueryStats()
      onCallback?.call(5, jsonEncode(n.params));
    });
  }

  Future<void> disconnect() async {
    await _logSub?.cancel();
    _logSub = null;
    await _urlTestSub?.cancel();
    _urlTestSub = null;
    await _modeUpdateSub?.cancel();
    _modeUpdateSub = null;
    await _connEventSub?.cancel();
    _connEventSub = null;
    await _stateUpdateSub?.cancel();
    _stateUpdateSub = null;
    await _trafficUpdateSub?.cancel();
    _trafficUpdateSub = null;
    try {
      await _client?.disconnect().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _client?.dispose();
    _client = null;
  }

  Future<bool> get isConnected async => _client?.isConnected ?? false;

  @override
  Future<void> init() async {}

  @override
  Future<void> initCore(String homeDir) async {
    // Service process handles init internally via --home-dir flag.
    // No-op on IPC side.
  }

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) =>
      _call('core.startWithContent', {
        'content': content,
        'rule_set_proxy': ruleSetProxy ?? '',
      });

  @override
  Future<void> stopCore() => _call('core.stop');

  @override
  Future<(List<ProxyGroup>, Map<String, int>)> queryProxies() async {
    final json = await _call('core.queryProxies');
    return LibCore.parseProxiesJson(json);
  }

  @override
  Future<CoreStats> queryStats() async {
    final json = await _call('core.queryStats');
    return LibCore.parseStatsJson(json);
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
    throw UnsupportedError('connectVpn is only available on mobile platforms');
  }

  @override
  Future<void> disconnectVpn() {
    throw UnsupportedError('disconnectVpn is only available on mobile platforms');
  }

  @override
  Future<bool> isVpnRunning() async => false;

  @override
  void updateVpnStats(CoreStats stats) {}

  Future<dynamic> _call(String method, [Map<String, dynamic>? params]) {
    if (_client == null || !_client!.isConnected) return Future.value();
    return _client!.call(method, params);
  }
}
