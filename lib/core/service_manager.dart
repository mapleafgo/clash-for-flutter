import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' as ipc;

import '../domain/enums.dart';
import '../utils/log_file.dart';
export 'service_manager_linux.dart';
export 'service_manager_macos.dart';
export 'service_manager_windows.dart';

import 'service_manager_linux.dart' show LinuxServiceManager;
import 'service_manager_macos.dart' show MacOSServiceManager;
import 'service_manager_windows.dart' show WindowsServiceManager;

/// Linux 服务模式固定 IPC socket 路径。
const String kLinuxSystemIpcPath = '/run/singcast/command.sock';

/// Linux systemd unit 名称。
const String kLinuxServiceUnitName = 'singcast-core.service';

/// Manages the singcast-service process lifecycle.
abstract class ServiceManager {
  /// IPC path for the current platform.
  String get ipcPath;

  /// 提权/服务是否已安装（仅用于 TUN elevation 流程）。
  /// Linux: unit 是否存在（不等于当前已连系统服务或具备 TUN 能力）。
  /// macOS/Windows: setuid/Service 是否已装好。
  Future<bool> isReady();

  /// 首次开 TUN 时的一次性提权安装。
  Future<bool> setup();

  /// 卸载持久化提权资源（Windows Service / macOS setuid / Linux unit）。
  Future<void> uninstall();

  /// 启动服务进程（提权路径优先）。
  Future<bool> start();

  /// 停止服务进程。
  Future<bool> stop();

  /// 降级：直接拉起内置 core，不走服务/提权。
  Future<bool> startDirect();

  /// Create the platform-appropriate ServiceManager.
  static ServiceManager create(String homeDir) {
    if (Platform.isWindows) return WindowsServiceManager(homeDir);
    if (Platform.isLinux) return LinuxServiceManager(homeDir);
    if (Platform.isMacOS) return MacOSServiceManager(homeDir);
    throw UnsupportedError('Unsupported platform for ServiceManager');
  }

  /// IPC path matching singcast-cli's ipc.IpcPath(homeDir).
  static String defaultIpcPath(String homeDir) {
    if (Platform.isWindows) return r'\\.\pipe\singcast';
    return '$homeDir/command.sock';
  }

  /// Path to the core binary, relative to the app executable.
  static String serviceBinaryPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'singcast-core.exe' : 'singcast-core';
    return '$exeDir/$name';
  }

  /// Whether the service process is currently running (IPC reachable).
  Future<bool> isRunning() async {
    try {
      final socket = await ipc
          .connect(ipcPath)
          .timeout(const Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// stop 后等待 IPC 消失的轮询上限：20 × 500ms = 10s。
  /// 覆盖内核优雅退出(关闭 TUN/连接排水)的最坏耗时，各平台 stop 语义都依赖它。
  static const _ipcGoneMaxAttempts = 20;
  static const _ipcGonePollInterval = Duration(milliseconds: 500);

  /// Wait until IPC is no longer reachable (after stop).
  Future<bool> waitForIpcGone() async {
    for (int i = 0; i < _ipcGoneMaxAttempts; i++) {
      if (!await isRunning()) return true;
      await Future.delayed(_ipcGonePollInterval);
    }
    return false;
  }
}

/// ServiceManager 共享日志工具（Linux / macOS / Windows 通过 with 混入）。
mixin ServiceManagerLogging {
  void logMsg(String message, {LogLevel level = LogLevel.info}) {
    LogFileWriter.instance?.log(message, level: level, name: 'service');
  }

  String procSummary(ProcessResult r) {
    final out = (r.stdout ?? '').toString().trim();
    final err = (r.stderr ?? '').toString().trim();
    final detail = err.isNotEmpty ? err : out;
    if (detail.isEmpty) return 'exit=${r.exitCode}';
    final clipped = detail.length > 300
        ? '${detail.substring(0, 300)}...'
        : detail;
    return 'exit=${r.exitCode} $clipped';
  }
}

/// 兼容旧调用方类型判断。
@Deprecated('use LinuxServiceManager')
typedef UnixServiceManager = LinuxServiceManager;
