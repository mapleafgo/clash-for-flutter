import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'ffi_worker.dart';
import 'lib_core.dart';
import '../domain/connection.dart';
import '../domain/log.dart';
import '../domain/net_speed.dart';
import '../domain/proxy_group.dart';

class LibCoreChannel implements LibCorePlatform {
  static const _channel = MethodChannel('cn.mapleafgo/singcast');
  static const _eventChannel = EventChannel('cn.mapleafgo/singcast/events');
  final _eventController = StreamController<CoreEvent>.broadcast();

  @override
  Stream<CoreEvent> get events => _eventController.stream;

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

    final payload = rawData is String
        ? rawData
        : rawData != null
            ? jsonEncode(rawData)
            : '';

    _eventController.add(CoreEvent(eventType, payload));
  }

  Future<dynamic> _invokeJson(String method, [Map<String, dynamic>? args]) async {
    final raw = await _channel.invokeMethod<String>(method, args);
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw);
  }

  // --- Lifecycle ---

  @override
  Future<void> initCore(String homeDir) async {
    final optionsJSON = jsonEncode({'home_dir': homeDir, 'log_max_lines': 500});
    try {
      await _channel.invokeMethod('initCore', {'optionsJSON': optionsJSON});
    } on PlatformException catch (e) {
      if ((e.message ?? '').contains('already initialized')) return;
      rethrow;
    }
  }

  @override
  Future<void> startCoreWithContent(String content, {String? ruleSetProxy}) =>
      _channel.invokeMethod('startCoreWithContent', {
        'content': content,
        'ruleSetProxy': ruleSetProxy ?? '',
      });

  @override
  Future<void> stopCore() => _channel.invokeMethod('stopCore');

  @override
  Future<void> destroyCore() => _channel.invokeMethod('destroyCore');

  @override
  Future<void> pause() => _channel.invokeMethod('pause');

  @override
  Future<void> wake() => _channel.invokeMethod('wake');

  @override
  Future<void> resetNetwork() => _channel.invokeMethod('resetNetwork');

  // --- Config ---

  @override
  Future<void> reloadConfig(String content, {String? ruleSetProxy}) =>
      _channel.invokeMethod('reloadConfig', {
        'content': content,
        'ruleSetProxy': ruleSetProxy ?? '',
      });

  @override
  Future<void> reloadTUN() => _channel.invokeMethod('reloadTUN');

  @override
  Future<void> setOverridePackages(String overrideJSON) =>
      _channel.invokeMethod('setOverridePackages', {'overrideJSON': overrideJSON});

  @override
  Future<String> queryTunOptions() async {
    final result = await _channel.invokeMethod<String>('queryTunOptions');
    return result ?? '';
  }

  // --- Queries ---

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
  Future<List<LogEntry>> queryLogs({bool clear = false}) async {
    final json = await _invokeJson('queryLogs', {'clear': clear});
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

  // --- Proxy Control ---

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
  Future<String> queryMemoryStats() async {
    final result = await _channel.invokeMethod<String>('queryMemoryStats');
    return result ?? '';
  }

  @override
  Future<void> flushSystemDNS() => _channel.invokeMethod('flushSystemDNS');

  // --- Platform ---

  @override
  Future<bool> needFindProcess() async {
    final result = await _channel.invokeMethod<bool>('needFindProcess');
    return result ?? false;
  }

  @override
  Future<void> writeMessage(int level, String message) =>
      _channel.invokeMethod('writeMessage', {'level': level, 'message': message});

  // --- Utilities ---

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
  Future<void> setLocale(String localeID) =>
      _channel.invokeMethod('setLocale', {'localeID': localeID});

  // --- VPN ---

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

  @override
  void updateVpnTraffic(TrafficSnapshot traffic) {
    try {
      _channel.invokeMethod('updateVpnTraffic', {
        'up': traffic.up,
        'down': traffic.down,
        'upTotal': traffic.upTotal,
        'downTotal': traffic.downTotal,
      });
    } catch (_) {}
  }
}
