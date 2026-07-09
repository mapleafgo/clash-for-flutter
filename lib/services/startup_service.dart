import 'dart:io' show File, Platform;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:path/path.dart' as p;
import 'package:singcast/utils/constants.dart';
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

/// 自启命令行参数标记，注册时写入、启动时检测，单一来源。
const autostartArg = '--autostart';

/// 自启应用名称（注册表键名 / desktop 文件名）。
const _appName = 'Singcast';

/// 返回完整的自启命令行（可执行路径 + 参数）。
String _buildCommand() {
  final exe = Platform.resolvedExecutable;
  return '$exe $autostartArg';
}

// --- Windows ---

const _winRunKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';

Future<void> _enableWindows() async {
  final key = CURRENT_USER.create(_winRunKeyPath);
  key.setValue(_appName, RegistryValue.string(_buildCommand()));
}

Future<void> _disableWindows() async {
  final key = CURRENT_USER.create(_winRunKeyPath);
  try {
    key.removeValue(_appName);
  } on WindowsException {
    // 值不存在时静默忽略
  }
}

// --- macOS ---

const _macChannel = MethodChannel('launch_at_startup');

Future<void> _enableMacOS() async {
  await _macChannel.invokeMethod(
    'launchAtStartupSetEnabled',
    {'setEnabledValue': true},
  );
}

Future<void> _disableMacOS() async {
  await _macChannel.invokeMethod(
    'launchAtStartupSetEnabled',
    {'setEnabledValue': false},
  );
}

// --- Linux ---

String get _linuxAutostartPath =>
    p.join(Platform.environment['HOME'] ?? '', '.config', 'autostart',
        '$_appName.desktop');

Future<void> _enableLinux() async {
  final file = File(_linuxAutostartPath);
  await file.parent.create(recursive: true);
  await file.writeAsString('''
[Desktop Entry]
Type=Application
Name=$_appName
Exec="${Platform.resolvedExecutable}" $autostartArg
Terminal=false
X-GNOME-Autostart-enabled=true
''');
}

Future<void> _disableLinux() async {
  final file = File(_linuxAutostartPath);
  if (await file.exists()) await file.delete();
}

// --- 公共接口 ---

/// 开启或关闭开机自启。
///
/// 由设置页开关调用，实际注册/注销系统自启项。
/// 不修改 [autoStart] signal，调用方负责更新信号。
Future<void> setAutoStart(bool enabled) async {
  if (!Constants.isDesktop) return;
  if (Platform.isWindows) {
    if (enabled) {
      await _enableWindows();
    } else {
      await _disableWindows();
    }
  } else if (Platform.isMacOS) {
    if (enabled) {
      await _enableMacOS();
    } else {
      await _disableMacOS();
    }
  } else if (Platform.isLinux) {
    if (enabled) {
      await _enableLinux();
    } else {
      await _disableLinux();
    }
  }
}
