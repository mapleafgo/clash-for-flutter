import 'package:flutter/services.dart';

import '../utils/constants.dart';
import 'ipc_worker.dart';

/// iOS 专属:把 VPN 生命周期(由 Network Extension 管理)和 App Group socket
/// 路径通过 MethodChannel 桥接到内核 RPC 客户端 [IpcWorker]。
///
/// iOS 上内核跑在 Extension 进程,主 App 是纯 RPC 客户端。VPN 的开/关/查询
/// 必须经原生(`NETunnelProviderManager`),RPC 只承载运行时控制。本类把这两者
/// 接到同一个 [IpcWorker] 上,使 LibCore 的平台无关调用在 iOS 仍能工作。
class IosVpnBridge {
  static const _channel = MethodChannel(Constants.methodChannelName);
  static const _socketName = 'command.sock';

  /// App Group 共享容器里的 RPC socket 路径。
  ///
  /// Extension 与主 App 解析到同一 App Group 容器,故 socket 可跨进程访问。
  /// 容器路径由原生 `getAppGroupPath` 返回(`containerURL(forSecurityApplicationGroupIdentifier:)`)。
  Future<String> appGroupSocketPath() async {
    final container = await _channel.invokeMethod<String>('getAppGroupPath');
    if (container == null || container.isEmpty) {
      throw StateError('App Group container unavailable');
    }
    return container.endsWith('/')
        ? '$container$_socketName'
        : '$container/$_socketName';
  }

  /// 把 VPN 相关方法注入 [worker],并监听原生推送的隧道断开事件。
  ///
  /// connectVpn/disconnectVpn/isVpnRunning 走 MethodChannel,reload 经
  /// startCoreWithContent 转发到 Extension 本地(见下方)。[onVpnDisconnected]
  /// 在系统停止隧道时触发。
  void wireInto(
    IpcWorker worker, {
    required void Function() onVpnDisconnected,
  }) {
    worker.connectVpnImpl = _connectVpn;
    worker.disconnectVpnImpl = _disconnectVpn;
    worker.isVpnRunningImpl = _isVpnRunning;
    // 切配置/reload 走 Extension 本地(SetTunFd + StartWithContent),
    // 避免裸 RPC 重启内核导致 tunFd 失效。
    worker.startCoreWithContentImpl = _reloadCore;
    worker.convertImpl = _convert;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVpnDisconnected') {
        onVpnDisconnected();
      }
      return null;
    });
  }

  /// 本地转换订阅（iOS）：主 App 通过 Runner 本地 FFI 调用，不依赖 VPN/RPC。
  Future<String> _convert(String content) async {
    final result = await _channel.invokeMethod<String>('convert', {
      'content': content,
    });
    if (result != null && result.isNotEmpty) return result;
    throw StateError('iOS convert returned no json result');
  }

  Future<void> _connectVpn(
    String configContent, {
    String? ruleSetProxy,
    bool? ipv6,
  }) => _channel.invokeMethod('connectVpn', {
    'configContent': configContent,
    'ruleSetProxy': ruleSetProxy ?? '',
    'ipv6': ipv6,
  });

  Future<void> _disconnectVpn() => _channel.invokeMethod('disconnectVpn');

  Future<bool> _isVpnRunning() async =>
      await _channel.invokeMethod<bool>('isVpnRunning') ?? false;

  /// 重载内核配置:走 Extension 本地路径(SetTunFd + StartWithContent)。
  /// iOS 上裸 RPC core.startWithContent 会因 tunFd 已被消费而失败。
  Future<void> _reloadCore(String content, {String? ruleSetProxy}) =>
      _channel.invokeMethod('reloadCore', {
        'configContent': content,
        'ruleSetProxy': ruleSetProxy ?? '',
      });
}
