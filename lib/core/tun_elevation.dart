import 'dart:io';

import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/core/win_elevation.dart';

final coreElevated = signal(false);

/// 检测当前进程是否具备 TUN 所需的特权。
///
/// - Linux: 检查 root 或 cap_net_admin capability（异步）
/// - macOS: 检查 root（osascript 提权后进程以 root 运行）
/// - Windows: 通过 FFI 检查 TokenElevation（同步，无需 PowerShell）
///
/// Linux getcap 是异步的，调用方应 await [elevationReady] 确保检测完成。
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
    coreElevated.value = isWindowsAdmin();
  }
}

/// 等待异步提权检测完成（仅 Linux getcap 需要）。
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

/// Linux: 通过 pkexec setcap 给可执行文件授予 cap_net_admin。
/// 授权持久化在文件属性中，下次启动即生效。
///
/// setcap 会使二进制变为 AT_SECURE，glibc 在此模式下对非 root 拥有的目录
/// 拒绝 $ORIGIN 展开，导致插件 .so 加载失败。因此在 setcap 之前，先用
/// patchelf 将实际的 lib 目录写入 RUNPATH。
///
/// patchelf 无法修改正在运行的二进制（ETXTBSY），因此先复制到临时文件、
/// 在副本上修改 RUNPATH，再用 rename() 原子替换原文件（rename 对正在
/// 运行的进程有效：进程仍持有旧 inode，新文件通过目录项替换）。
///
/// 安装目录通常属于 root，普通用户无权写入，因此整个流程通过
/// pkexec sh -c 以 root 身份执行，避免多次提权弹窗。
Future<bool> setupTunCapability() async {
  if (!Platform.isLinux) return false;
  try {
    final exe = Platform.resolvedExecutable;
    final libDir = '${File(exe).parent.path}/lib';

    // 已经具备 capability，无需重复提权
    final capCheck = await Process.run('getcap', [exe]);
    if ((capCheck.stdout ?? '').toString().contains('cap_net_admin')) {
      return true;
    }

    final script = r'''
set -e
rm -f "$1.tmp_patchelf"
cp -p "$1" "$1.tmp_patchelf"
if patchelf --set-rpath "$2:\$ORIGIN/lib" "$1.tmp_patchelf" 2>/dev/null; then
    mv -T "$1.tmp_patchelf" "$1"
elif [ "$(stat -c '%u' "$1.tmp_patchelf")" = "0" ] && \
     [ "$(stat -c '%u' "$(dirname "$1")")" = "0" ]; then
    # 二进制和目录均属 root：AT_SECURE 下 $ORIGIN 仍可展开，patchelf 非必需
    mv -T "$1.tmp_patchelf" "$1"
else
    # 用户拥有的二进制必须通过 patchelf 写入显式路径，否则 setcap 后 .so 加载失败
    rm -f "$1.tmp_patchelf"
    exit 1
fi
setcap cap_net_admin,cap_net_raw,cap_net_bind_service+ep "$1"
''';

    final result = await Process.run('pkexec', [
      'sh', '-c', script, 'sh', exe, libDir,
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
      ['--enable-tun'],
      workingDirectory: Directory.current.path,
      mode: ProcessStartMode.detached,
    );
    await Future.delayed(const Duration(milliseconds: 200));
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
    if (Platform.isMacOS) {
      // osascript 弹出系统授权对话框，用户输入密码后以 root 运行可执行文件。
      // & 后台运行：do shell script 同步等待命令完成，GUI 应用不退出会导致 osascript 挂起。
      // 传递 --home-dir 确保以 root 运行时仍使用用户的配置目录。
      // Process.run 等待 osascript 返回，用户取消授权时 exitCode != 0。
      final cmd = homeDir != null
          ? "'$exe' --home-dir '$homeDir' --enable-tun"
          : "'$exe' --enable-tun";
      final result = await Process.run(
        'osascript',
        ['-e', 'do shell script "$cmd &" with administrator privileges'],
      );
      if (result.exitCode != 0) return false;
      // osascript 返回后新进程刚启动，等待其完成初始化
      await Future.delayed(const Duration(milliseconds: 200));
    } else if (Platform.isWindows) {
      // 通过 ShellExecuteExW + "runas" 直接触发 UAC，不依赖 PowerShell。
      // 调用阻塞直到用户响应 UAC 对话框，成功时新进程已启动，无需 delay。
      // --elevated 标志让 main.cpp 跳过 FindWindow 单例检测。
      final exeDir = File(exe).parent.path;
      return runElevated(exe: exe, args: '--elevated --enable-tun', workingDir: exeDir);
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
