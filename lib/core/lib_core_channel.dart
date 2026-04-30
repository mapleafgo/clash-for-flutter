import 'dart:convert';
import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/connection.dart';
import 'package:singcast/domain/log.dart';
import 'package:singcast/domain/net_speed.dart';
import 'package:singcast/domain/proxy_group.dart';
import 'package:flutter/services.dart';

class LibCoreChannel implements LibCorePlatform {
  static const _channel = MethodChannel('cn.mapleafgo/singcast');
  static const _eventChannel = EventChannel('cn.mapleafgo/singcast/events');

  @override
  Future<void> init() async {
    _eventChannel.receiveBroadcastStream().listen(_onEvent);
    if (Platform.isAndroid) {
      await _channel.invokeMethod('requestNotificationPermission');
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<String, dynamic>.from(event);
    final eventType = map['type'] as int? ?? -1;
    final rawData = map['data'];
    final core = LibCore.instance;

    switch (eventType) {
      case 0: // traffic
        if (rawData is String) {
          core.trafficSignal.value = TrafficSnapshot.fromJson(
              jsonDecode(rawData) as Map<String, dynamic>);
        } else if (rawData is Map) {
          core.trafficSignal.value = TrafficSnapshot.fromJson(
              Map<String, dynamic>.from(rawData));
        }
        _updateVpnNotification(core.trafficSignal.value);
      case 1: // logs
        final list = rawData is String
            ? jsonDecode(rawData) as List
            : rawData as List;
        final logs = list
            .map((e) => LogEntry.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
        core.appendLogs(logs);
      case 2: // connections (incremental)
        if (rawData is String) {
          final json = jsonDecode(rawData) as Map<String, dynamic>;
          core.handleConnectionEvents(ConnectionEventsPayload.fromJson(json));
        } else if (rawData is Map) {
          core.handleConnectionEvents(
              ConnectionEventsPayload.fromJson(
                  Map<String, dynamic>.from(rawData)));
        }
      case 3: // proxies
        final list = rawData is String
            ? jsonDecode(rawData) as List
            : rawData as List;
        core.proxiesSignal.value = list
            .map((e) =>
                ProxyGroup.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      case 4: // mode
        if (rawData is String) {
          final json = jsonDecode(rawData) as Map<String, dynamic>;
          core.modeSignal.value = json['current_mode'] as String? ?? 'rule';
        } else if (rawData is Map) {
          final m = Map<String, dynamic>.from(rawData);
          core.modeSignal.value = m['current_mode'] as String? ?? 'rule';
        }
      case 5: // vpn state changed (from notification disconnect)
        if (rawData is String) {
          final json = jsonDecode(rawData) as Map<String, dynamic>;
          core.vpnDisconnectedByUser.value = !(json['connected'] as bool? ?? true);
        } else if (rawData is Map) {
          final m = Map<String, dynamic>.from(rawData);
          core.vpnDisconnectedByUser.value = !(m['connected'] as bool? ?? true);
        }
    }
  }

  void _updateVpnNotification(TrafficSnapshot? traffic) {
    if (!Platform.isAndroid || traffic == null) return;
    try {
      _channel.invokeMethod('updateVpnTraffic', {
        'up': traffic.up,
        'down': traffic.down,
        'upTotal': traffic.upTotal,
        'downTotal': traffic.downTotal,
      });
    } catch (_) {}
  }

  Future<dynamic> _invokeJson(String method, [Map<String, dynamic>? args]) async {
    final raw = await _channel.invokeMethod<String>(method, args);
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw);
  }

  @override
  Future<void> initCore(String homeDir) =>
      _channel.invokeMethod('initCore', {'homeDir': homeDir});

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) async {
    await _channel.invokeMethod('startCoreWithContent', {
      'content': content,
      'ruleSetProxy': ruleSetProxy ?? '',
    });
    // 移动端依赖事件推送更新 UI，但内核启动后不一定立即推送代理数据
    // 主动查询一次确保代理列表可用
    try {
      LibCore.instance.proxiesSignal.value = await queryProxies();
    } catch (_) {}
  }

  @override
  Future<void> stopCore() => _channel.invokeMethod('stopCore');

  @override
  Future<void> closeCore() => _channel.invokeMethod('closeCore');

  @override
  Future<void> reloadConfig() => _channel.invokeMethod('reloadConfig');

  @override
  Future<List<ProxyGroup>> queryProxies() async {
    final json = await _invokeJson('queryProxies');
    if (json is! List) return [];
    return json
        .map((e) => ProxyGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<TrafficSnapshot> queryTraffic() async {
    final json = await _invokeJson('queryTraffic');
    if (json is! Map<String, dynamic>) return TrafficSnapshot();
    return TrafficSnapshot.fromJson(json);
  }

  @override
  Future<List<LogEntry>> queryLogs() async {
    final json = await _invokeJson('queryLogs');
    if (json is! List) return [];
    return json
        .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ConnectionEventsPayload> queryConnections() async {
    final json = await _invokeJson('queryConnections');
    if (json is! Map<String, dynamic>) {
      return ConnectionEventsPayload(reset: true, items: []);
    }
    return ConnectionEventsPayload.fromJson(json);
  }

  @override
  Future<void> selectProxy(String group, String tag) =>
      _channel.invokeMethod('selectProxy', {'group': group, 'tag': tag});

  @override
  Future<void> testDelay(String name) =>
      _channel.invokeMethod('testDelay', {'name': name});

  @override
  Future<void> setMode(String mode) =>
      _channel.invokeMethod('setMode', {'mode': mode});

  @override
  Future<void> closeConnection(String id) =>
      _channel.invokeMethod('closeConnection', {'id': id});

  @override
  Future<void> closeAllConnections() =>
      _channel.invokeMethod('closeAllConnections');

  @override
  Future<String> checkConfig(String content) async {
    final result = await _channel
        .invokeMethod<String>('checkConfig', {'content': content});
    return result ?? '';
  }

  @override
  Future<String> getVersion() async {
    final result = await _channel.invokeMethod<String>('getVersion');
    return result ?? '';
  }

  @override
  Future<void> connectVpn(String configContent, {String? ruleSetProxy}) =>
      _channel.invokeMethod('connectVpn', {
        'configContent': configContent,
        'ruleSetProxy': ruleSetProxy ?? '',
      });

  @override
  Future<void> disconnectVpn() =>
      _channel.invokeMethod('disconnectVpn');

  @override
  Future<bool> isVpnRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isVpnRunning') ?? false;
    } catch (_) {
      return false;
    }
  }
}
