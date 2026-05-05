import 'dart:io';

import 'package:signals_flutter/signals_flutter.dart';

final coreElevated = signal(false);

/// 检测当前进程是否具备 TUN 所需的特权。
///
/// - Linux: 检查 root 或 cap_net_admin capability
/// - macOS: 检查 root（osascript 提权后进程以 root 运行）
/// - Windows: 检查管理员组成员身份
///
/// 注意: Linux getcap 和 Windows 管理员检测是异步的，
/// 调用方应 await [elevationReady] 确保检测完成。
void detectElevation() {
  if (Platform.isLinux) {
    if (_isRunningAsRoot()) {
      coreElevated.value = true;
      return;
    }
    _ready = _checkCapabilityAsync();
  } else if (Platform.isMacOS) {
    coreElevated.value = _isRunningAsRoot();
  } else if (Platform.isWindows) {
    _ready = _checkWindowsAdminAsync();
  }
}

/// 等待异步提权检测完成（Linux getcap / Windows 管理员检测）。
Future<void> get elevationReady => _ready ?? Future.value();
Future<void>? _ready;

bool _isRunningAsRoot() {
  return Platform.environment['USER'] == 'root' ||
      Platform.environment['SUDO_UID'] != null ||
      Platform.environment['PKEXEC_UID'] != null;
}

Future<void> _checkCapabilityAsync() async {
  try {
    final result = await Process.run('getcap', [Platform.resolvedExecutable]);
    coreElevated.value =
        (result.stdout ?? '').toString().contains('cap_net_admin');
  } catch (_) {
    coreElevated.value = false;
  }
}

Future<void> _checkWindowsAdminAsync() async {
  try {
    final result = await Process.run('powershell', [
      '-Command', '-NoProfile',
      '(New-Object Security.Principal.WindowsPrincipal('
          '[Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole('
          '[Security.Principal.WindowsBuiltInRole]::Administrator)',
    ]);
    coreElevated.value = result.exitCode == 0 &&
        (result.stdout ?? '').toString().trim() == 'True';
  } catch (_) {
    coreElevated.value = false;
  }
}

/// Linux: 通过 pkexec setcap 给可执行文件授予 cap_net_admin。
/// 授权持久化在文件属性中，下次启动即生效。
Future<bool> setupTunCapability() async {
  if (!Platform.isLinux) return false;
  try {
    final result = await Process.run('pkexec', [
      'setcap',
      'cap_net_admin,cap_net_raw,cap_net_bind_service+ep',
      Platform.resolvedExecutable,
    ]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// 以当前用户身份重启应用（Linux setcap 后使用）。
Future<bool> relaunchSelf() async {
  try {
    await Process.start(
      Platform.resolvedExecutable,
      [],
      workingDirectory: Directory.current.path,
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// 以管理员/特权身份重启应用。
/// 仅用于 macOS/Windows，Linux 使用 [relaunchSelf]。
///
/// [homeDir] 仅 macOS 需要：以 root 运行时 getApplicationSupportDirectory
/// 返回 /var/root/...，需显式传递用户数据目录。
Future<bool> relaunchElevated({String? homeDir}) async {
  final exe = Platform.resolvedExecutable;

  try {
    if (Platform.isLinux) {
      await Process.start(
        'pkexec',
        ['--disable-internal-agent', exe],
        mode: ProcessStartMode.detached,
      );
    } else if (Platform.isMacOS) {
      // osascript 弹出系统授权对话框，用户输入密码后以 root 运行可执行文件。
      // & 后台运行：do shell script 同步等待命令完成，GUI 应用不退出会导致 osascript 挂起。
      // 传递 --home-dir 确保以 root 运行时仍使用用户的配置目录。
      final cmd = homeDir != null
          ? "'$exe' --home-dir '$homeDir'"
          : "'$exe'";
      await Process.start(
        'osascript',
        ['-e', 'do shell script "$cmd &" with administrator privileges'],
        mode: ProcessStartMode.detached,
      );
    } else if (Platform.isWindows) {
      // Windows 以管理员运行仍是同一用户，%APPDATA% 路径不变，无需 --home-dir。
      // Start-Process -Verb RunAs 触发 UAC，启动后立即返回，不会阻塞。
      await Process.start(
        'powershell',
        ['-Command', '-NoProfile', 'Start-Process -Verb RunAs -FilePath "$exe"'],
      );
    }

    return true;
  } catch (_) {
    return false;
  }
}

class TunElevationException implements Exception {
  final String message;
  TunElevationException(this.message);

  @override
  String toString() => 'TunElevationException: $message';
}
