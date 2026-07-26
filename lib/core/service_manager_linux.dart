import 'dart:io';

import '../domain/enums.dart';
import 'service_manager.dart';

/// Linux core 实际运行通道。
enum LinuxCoreRunMode { system, direct }

/// Linux: systemd 服务 + polkit。
class LinuxServiceManager extends ServiceManager with ServiceManagerLogging {
  final String homeDir;
  Process? _directProcess;

  LinuxServiceManager(this.homeDir);

  /// unit 是否已安装（与当前运行模式分离）。
  bool _unitInstalled = false;

  /// 当前实际运行模式。fallback 直跑后为 direct，避免 stop 误走 systemctl。
  LinuxCoreRunMode _runMode = LinuxCoreRunMode.direct;

  /// 是否已发生过降级直跑；isReady 探测时不要自动切回 system。
  bool _degradedSticky = false;

  int? _directPid;

  @override
  String get ipcPath {
    if (_runMode == LinuxCoreRunMode.system) {
      return kLinuxSystemIpcPath;
    }
    return ServiceManager.defaultIpcPath(homeDir);
  }

  /// unit 文件是否存在。不表示当前已连系统服务或具备 TUN 能力。
  bool get isUnitInstalled => _unitInstalled;

  /// unit 已装但当前直跑（ACL/连接失败后的降级态）。
  bool get isDegradedRun =>
      _unitInstalled && _runMode == LinuxCoreRunMode.direct;

  /// 标记当前为系统服务运行，清除降级 sticky。
  void markSystemRun() {
    _runMode = LinuxCoreRunMode.system;
    _degradedSticky = false;
  }

  /// 标记当前为降级直跑。若 unit 已装，设置 sticky 防止 isReady 自动切回 system。
  void markDirectRun() {
    _runMode = LinuxCoreRunMode.direct;
    if (_unitInstalled) _degradedSticky = true;
  }

  @override
  Future<bool> isReady() async {
    try {
      final result = await Process.run('systemctl', [
        'cat',
        kLinuxServiceUnitName,
      ]);
      final ready = result.exitCode == 0;
      _unitInstalled = ready;
      if (!ready) {
        _runMode = LinuxCoreRunMode.direct;
        _degradedSticky = false;
      } else if (!_degradedSticky) {
        // 冷启动：unit 在且未降级过，优先系统服务
        _runMode = LinuxCoreRunMode.system;
      }
      return ready;
    } catch (e) {
      logMsg('isReady failed: $e', level: LogLevel.warning);
      return false;
    }
  }

  @override
  Future<bool> setup() async {
    try {
      final svcPath = ServiceManager.serviceBinaryPath();
      final result = await Process.run('pkexec', [
        svcPath,
        'service',
        'install',
      ]);
      final ok = result.exitCode == 0;
      if (ok) {
        _unitInstalled = true;
        markSystemRun();
        logMsg('service install ok');
      } else {
        logMsg(
          'service install failed: ${procSummary(result)}',
          level: LogLevel.error,
        );
      }
      return ok;
    } catch (e) {
      logMsg('setup failed: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<void> uninstall() async {
    try {
      final svcPath = ServiceManager.serviceBinaryPath();
      final result = await Process.run('pkexec', [
        svcPath,
        'service',
        'uninstall',
      ]);
      if (result.exitCode != 0) {
        logMsg(
          'service uninstall failed: ${procSummary(result)}',
          level: LogLevel.error,
        );
      }
    } catch (e) {
      logMsg('service uninstall exception: $e', level: LogLevel.error);
    }
    _unitInstalled = false;
    _runMode = LinuxCoreRunMode.direct;
    _degradedSticky = false;
  }

  @override
  Future<bool> start() async {
    try {
      if (_unitInstalled && _runMode == LinuxCoreRunMode.system) {
        final result = await Process.run('systemctl', [
          'start',
          kLinuxServiceUnitName,
        ]);
        if (result.exitCode == 0) {
          markSystemRun();
          return true;
        }
        logMsg(
          'systemctl start failed: ${procSummary(result)}',
          level: LogLevel.error,
        );
        return false;
      }
      return startDirect();
    } catch (e) {
      logMsg('start failed: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<bool> startDirect() async {
    try {
      _directProcess = await Process.start(ServiceManager.serviceBinaryPath(), [
        'ipc',
        '--home',
        homeDir,
      ], mode: ProcessStartMode.detached);
      _directPid = _directProcess?.pid;
      markDirectRun();
      return true;
    } catch (e) {
      logMsg('startDirect failed: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    if (_runMode == LinuxCoreRunMode.system) {
      final result = await Process.run('systemctl', [
        'stop',
        kLinuxServiceUnitName,
      ]);
      if (result.exitCode != 0) {
        logMsg(
          'systemctl stop failed: ${procSummary(result)}',
          level: LogLevel.warning,
        );
      }
      return result.exitCode == 0 || await waitForIpcGone();
    }
    _directProcess?.kill();
    _directProcess = null;
    if (await waitForIpcGone()) {
      _directPid = null;
      return true;
    }
    // 仅杀本 home 下的直跑 core，避免误杀 systemd 服务或其他实例
    final pid = _directPid;
    if (pid != null) {
      await Process.run('kill', ['-TERM', '$pid']);
      if (await waitForIpcGone()) {
        _directPid = null;
        return true;
      }
    }
    await Process.run('pkill', [
      '-u',
      Platform.environment['USER'] ?? Platform.environment['LOGNAME'] ?? 'nobody',
      '-f',
      'singcast-core ipc --home $homeDir',
    ]);
    await waitForIpcGone();
    _directPid = null;
    return true;
  }

  /// 幂等 reinstall：pkexec `service install` 重写 unit（含 SINGCAST_GUI_UID）与 polkit，
  /// 再 `systemctl restart` 使新 env/ACL 生效。
  /// 副作用：会重启系统服务；需用户授权；失败时 runMode 不变。
  /// 用于包预装后 unit 已在但 socket ACL 缺当前用户的降级态。
  Future<bool> reinstallForCurrentUser() async {
    try {
      final svcPath = ServiceManager.serviceBinaryPath();
      final result = await Process.run('pkexec', [
        svcPath,
        'service',
        'install',
      ]);
      final ok = result.exitCode == 0;
      if (ok) {
        _unitInstalled = true;
        markSystemRun();
        final restart = await Process.run('systemctl', [
          'restart',
          kLinuxServiceUnitName,
        ]);
        if (restart.exitCode != 0) {
          logMsg(
            'systemctl restart after reinstall failed: ${procSummary(restart)}',
            level: LogLevel.error,
          );
          return false;
        }
        logMsg('service reinstalled for current user and restarted');
      } else {
        logMsg(
          'reinstallForCurrentUser failed: ${procSummary(result)}',
          level: LogLevel.error,
        );
      }
      return ok;
    } catch (e) {
      logMsg('reinstallForCurrentUser exception: $e', level: LogLevel.error);
      return false;
    }
  }
}
