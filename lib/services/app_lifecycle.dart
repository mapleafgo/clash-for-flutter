import 'dart:io' show Platform;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/services/app_config.dart' show flushAppConfig;
import 'package:singcast/utils/log_file.dart';

const _channel = MethodChannel('cn.mapleafgo/singcast_lifecycle');

/// macOS：注册 Cmd+Q / 注销前的清理钩子。
///
/// 常驻托盘的应用在 Cmd+Q 时会被直接杀掉 Flutter 引擎，detached 的
/// singcast-core 与已设置的系统代理都会残留——系统代理指向已死端口，
/// 用户退出应用后就上不了网。原生侧带 3 秒兜底超时，此处慢或抛异常
/// 都不会卡住退出。
void initTerminationHook() {
  if (!Platform.isMacOS) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'prepareTermination') return null;
    try {
      flushAppConfig();
    } catch (_) {}
    try {
      // dispose 会 stopCore，内核退出时还原系统代理
      await LibCore.instance.dispose();
    } catch (_) {}
    try {
      await LogFileWriter.instance?.close();
    } catch (_) {}
    return null;
  });
}
