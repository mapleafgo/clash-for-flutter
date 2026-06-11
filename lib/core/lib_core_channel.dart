import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'lib_core.dart';
import '../domain/connection.dart';
import '../domain/proxy_group.dart';

class LibCoreChannel implements LibCorePlatform {
  static const _channel = MethodChannel('cn.mapleafgo/singcast');

  void Function(int eventType, String payload)? onCallback;
  void Function()? onVpnDisconnected;

  @override
  Future<void> init() async {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onEvent') {
      final args = call.arguments;
      if (args is! Map) return;
      final eventType = args['eventType'] as int? ?? -1;
      final payload = args['payload'] as String? ?? '';
      onCallback?.call(eventType, payload);
    } else if (call.method == 'onVpnDisconnected') {
      onVpnDisconnected?.call();
    }
  }

  Future<dynamic> _invokeJson(String method, [Map<String, dynamic>? args]) async {
    final raw = await _channel.invokeMethod<String>(method, args);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  // --- Lifecycle ---

  @override
  Future<void> initCore(String homeDir) async {
    final optionsJSON = jsonEncode({
      'home_dir': homeDir,
      'debug': true,
    });
    await _channel.invokeMethod('initCore', {'optionsJSON': optionsJSON});
  }

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy, bool enabledVpn = false}) async {
    await _channel.invokeMethod('startCoreWithContent', {
      'content': content,
      'ruleSetProxy': ruleSetProxy ?? '',
      'enabledVpn': enabledVpn,
    });
  }

  @override
  Future<void> stopCore() => _channel.invokeMethod('stopCore');

  // --- Queries ---

  @override
  Future<(List<ProxyGroup>, Map<String, int>)> queryProxies() async {
    final json = await _invokeJson('queryProxies');
    return LibCore.parseProxiesJson(json);
  }

  @override
  Future<ConnectionEventsPayload> queryConnections() async {
    final json = await _invokeJson('queryConnections');
    return LibCore.parseConnectionsJson(json);
  }

  // --- Proxy Control ---

  @override
  Future<void> selectProxy(String group, String tag) =>
      _channel.invokeMethod('selectProxy', {'group': group, 'tag': tag});

  @override
  Future<int> testDelay(String name, {int timeoutMs = 3000}) async {
    final result = await _channel.invokeMethod(
        'testDelay', {'name': name, 'timeoutMs': timeoutMs});
    return (result as num?)?.toInt() ?? -1;
  }

  @override
  Future<Map<String, int>> testGroupDelay(String group, {int timeoutMs = 3000}) async {
    final raw = await _channel.invokeMethod<String>(
        'testGroupDelay', {'group': group, 'timeoutMs': timeoutMs});
    if (raw == null || raw.isEmpty) return {};
    return LibCore.parseGroupDelayJson(jsonDecode(raw));
  }

  @override
  Future<void> setMode(String mode) =>
      _channel.invokeMethod('setMode', {'mode': mode});

  @override
  Future<void> setGroupExpand(String group, bool expand) =>
      _channel.invokeMethod('setGroupExpand', {'group': group, 'expand': expand});

  // --- Connection Management ---

  @override
  Future<void> closeConnection(String id) =>
      _channel.invokeMethod('closeConnection', {'id': id});

  @override
  Future<void> closeAllConnections() =>
      _channel.invokeMethod('closeAllConnections');

  // --- Logging / Memory ---

  @override
  Future<void> setLogLevel(int level) =>
      _channel.invokeMethod('setLogLevel', {'level': level});

  @override
  Future<void> setMemoryLimit(int bytes) =>
      _channel.invokeMethod('setMemoryLimit', {'bytes': bytes});

  @override
  Future<void> flushSystemDNS() => _channel.invokeMethod('flushSystemDNS');

  @override
  Future<String> queryMode() async {
    final result = await _channel.invokeMethod<String>('queryMode');
    return result ?? '';
  }

  @override
  Future<String> queryState() async {
    final result = await _channel.invokeMethod<String>('queryState');
    return result ?? LibCore.kStateCreated;
  }

  @override
  Future<void> flushFakeIP() => _channel.invokeMethod('flushFakeIP');

  @override
  Future<void> flushDNSCache() => _channel.invokeMethod('flushDNSCache');

  @override
  Future<void> triggerGC() => _channel.invokeMethod('triggerGC');

  // --- Utilities ---

  @override
  Future<String> checkConfig(String content) async {
    final result = await _channel
        .invokeMethod<String>('checkConfig', {'content': content});
    return result ?? '';
  }

  @override
  Future<String> getVersion() async {
    final result = await _channel.invokeMethod<dynamic>('getVersion');
    return LibCore.parseVersionJson(result);
  }

  // --- VPN ---

  @override
  Future<void> connectVpn(String configContent, {String? ruleSetProxy, bool? ipv6}) async {
    await _channel.invokeMethod('connectVpn', {
      'configContent': configContent,
      'ruleSetProxy': ruleSetProxy ?? '',
      'ipv6': ipv6,
    });
  }

  @override
  Future<void> disconnectVpn() async {
    await _channel.invokeMethod('disconnectVpn');
  }

  @override
  Future<bool> isVpnRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isVpnRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

}
