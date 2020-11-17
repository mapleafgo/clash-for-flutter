import 'package:flutter/services.dart';

class PACProxy {
  static const MethodChannel _channel = const MethodChannel('pac-proxy');

  /// 初始化pac代理
  static Future<void> init({String pac}) => _channel.invokeMethod('init', pac);

  /// 开启代理
  static Future<void> open(String port) => _channel.invokeMethod('open', port);

  /// 关闭代理
  static Future<void> close() => _channel.invokeMethod('close');
}
