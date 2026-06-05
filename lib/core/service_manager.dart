import 'dart:ffi';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' as ipc;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../domain/enums.dart';
import '../utils/log_file.dart';

/// Manages the singcast-service process lifecycle.
abstract class ServiceManager {
  /// IPC path for the current platform.
  String get ipcPath;

  /// Whether the service is ready for privileged operations (setuid/Service installed).
  /// Only relevant for TUN mode.
  Future<bool> isReady();

  /// One-time privilege setup (setuid on macOS/Linux, Windows Service install).
  /// Called only when the user enables TUN for the first time.
  Future<bool> setup();

  /// Cleanup persistent resources on app uninstall (e.g., delete Windows Service).
  Future<void> uninstall();

  /// Whether the service process is currently running.
  Future<bool> isRunning();

  /// Start the service process.
  Future<bool> start();

  /// Stop the service process.
  Future<bool> stop();

  /// Start as direct process, bypassing any service/privilege mechanism.
  /// Used for degraded/fallback startup without UAC elevation.
  Future<bool> startDirect();

  /// Create the platform-appropriate ServiceManager.
  static ServiceManager create(String homeDir) {
    if (Platform.isWindows) return WindowsServiceManager(homeDir);
    if (Platform.isLinux || Platform.isMacOS) {
      return UnixServiceManager(homeDir);
    }
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
}

/// Unix (Linux + macOS): setcap/setuid via pkexec/osascript.
class UnixServiceManager extends ServiceManager {
  final String homeDir;
  Process? _directProcess;

  UnixServiceManager(this.homeDir);

  @override
  String get ipcPath => ServiceManager.defaultIpcPath(homeDir);

  /// macOS: path to the setuid copy outside the app bundle.
  /// Avoids chown on files inside signed/translocated app bundles.
  String get _elevatedBinaryPath => '$homeDir/singcast-core';

  /// macOS: marker file tracking the bundle binary's mtime at copy time.
  /// Invalidated when the app updates (bundle binary changes).
  String get _elevatedMarkerPath => '$homeDir/singcast-core.marker';

  bool _elevatedUpToDate() {
    try {
      final marker = File(_elevatedMarkerPath);
      if (!marker.existsSync()) return false;
      final markerMtime = marker.readAsStringSync().trim();
      final bundleStat = FileStat.statSync(ServiceManager.serviceBinaryPath());
      return markerMtime ==
          bundleStat.modified.millisecondsSinceEpoch.toString();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isReady() async {
    try {
      if (Platform.isLinux) {
        final svcPath = ServiceManager.serviceBinaryPath();
        final result = await Process.run('getcap', [svcPath]);
        return (result.stdout ?? '').toString().contains('cap_net_admin');
      }
      // macOS: check setuid on the external copy (outside app bundle)
      if (!File(_elevatedBinaryPath).existsSync()) return false;
      if (!_elevatedUpToDate()) return false;
      final stat = await FileStat.stat(_elevatedBinaryPath);
      return (stat.mode & 0x800) != 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setup() async {
    try {
      if (Platform.isLinux) {
        final svcPath = ServiceManager.serviceBinaryPath();
        final result = await Process.run('pkexec', [
          'sh',
          '-c',
          'setcap cap_net_admin+ep "\$1"',
          'sh',
          svcPath,
        ]);
        return result.exitCode == 0;
      }
      // macOS: copy binary outside app bundle, then setuid the external copy.
      // This avoids chown on bundle contents which breaks code signing and
      // can fail under App Translocation / Gatekeeper on newer macOS.
      final elevated = _elevatedBinaryPath;
      await Directory(homeDir).create(recursive: true);
      // User owns the directory, so unlink works even for root-owned files.
      if (File(elevated).existsSync()) {
        await File(elevated).delete();
      }
      await File(ServiceManager.serviceBinaryPath()).copy(elevated);
      await Process.run('chmod', ['+x', elevated]);
      final result = await Process.run('osascript', [
        '-e',
        'do shell script "chown root:admin \\"$elevated\\" && chmod +sx \\"$elevated\\"" with administrator privileges',
      ]);
      if (result.exitCode != 0) return false;
      // Write marker for staleness detection on next launch
      final bundleStat = FileStat.statSync(ServiceManager.serviceBinaryPath());
      await File(
        _elevatedMarkerPath,
      ).writeAsString(bundleStat.modified.millisecondsSinceEpoch.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> uninstall() async {
    // macOS: delete the setuid copy so start() falls back to bundle binary.
    if (Platform.isMacOS) {
      try {
        if (File(_elevatedBinaryPath).existsSync()) {
          await File(_elevatedBinaryPath).delete();
        }
        final marker = File(_elevatedMarkerPath);
        if (marker.existsSync()) await marker.delete();
      } catch (_) {}
    }
    // Linux: no persistent resources (setcap modifies the bundle binary in-place).
  }

  @override
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

  @override
  Future<bool> start() async {
    try {
      String svcPath = ServiceManager.serviceBinaryPath();
      if (Platform.isMacOS && File(_elevatedBinaryPath).existsSync()) {
        if (_elevatedUpToDate()) {
          svcPath = _elevatedBinaryPath;
        } else {
          // Stale — clean up so we fall through to bundle binary
          await uninstall();
        }
      }
      _directProcess = await Process.start(svcPath, [
        'ipc',
        '--home',
        homeDir,
      ], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
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
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _directProcess?.kill();
    _directProcess = null;
    // The caller (LibCore.restart) stops the kernel and disconnects IPC
    // before calling stop(). singcast-cli self-terminates when kernel is
    // stopped and all GUI connections close — no need to forcefully kill
    // a setuid root process from user space.
    if (await _waitForIpcGone()) return true;
    // Last resort: signal the process (won't work for root, but harmless).
    await Process.run('pkill', ['-f', 'singcast-core.*ipc']);
    await _waitForIpcGone();
    return true;
  }

  /// Wait until IPC is no longer reachable (after stop).
  Future<bool> _waitForIpcGone() async {
    for (int i = 0; i < 20; i++) {
      if (!await isRunning()) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }
}

/// Windows: uses Windows Service (SCM) after one-time UAC install.
class WindowsServiceManager extends ServiceManager {
  static const _serviceName = 'SingcastService';

  final String homeDir;
  final bool _portable;
  bool _elevated = false;
  Process? _directProcess;

  WindowsServiceManager(this.homeDir) : _portable = _detectPortable();

  /// Portable mode: no Inno uninstaller found in the app directory.
  static bool _detectPortable() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    try {
      for (final entity in Directory(exeDir).listSync()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('unins') && name.endsWith('.exe')) return false;
      }
    } catch (_) {}
    return true;
  }

  @override
  String get ipcPath => ServiceManager.defaultIpcPath(homeDir);

  /// Open a handle to the installed service with [access] rights.
  /// Returns the service handle, or null if not installed or no permission.
  SC_HANDLE? _openService(int access) {
    final scm = OpenSCManager(null, null, SC_MANAGER_CONNECT);
    if (!scm.value.isValid) return null;
    try {
      final namePtr = _serviceName.toNativeUtf16();
      try {
        final svc = OpenService(scm.value, PCWSTR(namePtr), access);
        return svc.value.isValid ? svc.value : null;
      } finally {
        free(namePtr);
      }
    } finally {
      scm.value.close();
    }
  }

  @override
  Future<bool> isReady() async {
    if (_portable) return _elevated;
    final svc = _openService(SERVICE_QUERY_STATUS);
    if (svc == null) return false;
    svc.close();
    return true;
  }

  /// UAC-elevate via ShellExecuteExW with "runas" verb.
  /// Returns the process HANDLE, or null on failure.
  HANDLE? _runas(String params) {
    final svcPath = ServiceManager.serviceBinaryPath();
    final exePtr = svcPath.toNativeUtf16();
    final paramsPtr = params.toNativeUtf16();
    final verbPtr = 'runas'.toNativeUtf16();
    final dirPtr = File(svcPath).parent.path.toNativeUtf16();

    final info = calloc<SHELLEXECUTEINFO>();
    try {
      info.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
      info.ref.fMask = 0x00000100 | 0x00000040; // NOCLOSEPROCESS | NOASYNC
      info.ref.lpVerb = PWSTR(verbPtr);
      info.ref.lpFile = PWSTR(exePtr);
      info.ref.lpParameters = PWSTR(paramsPtr);
      info.ref.lpDirectory = PWSTR(dirPtr);
      info.ref.nShow = SW_HIDE;

      final result = ShellExecuteEx(info);
      if (!result.value) return null;
      return info.ref.hProcess;
    } finally {
      free(info);
      free(exePtr);
      free(paramsPtr);
      free(verbPtr);
      free(dirPtr);
    }
  }

  @override
  Future<bool> setup() async {
    await stop();
    if (_portable) return true;

    final params = [
      'service',
      'install',
      '--home',
      homeDir,
    ].map((a) => a.contains(' ') ? '"$a"' : a).join(' ');
    final handle = _runas(params);
    if (handle == null) {
      LogFileWriter.instance?.log(
        'ShellExecuteEx runas failed',
        level: LogLevel.error,
        name: 'service',
      );
      return false;
    }
    while (WaitForSingleObject(handle, 100).value == WAIT_TIMEOUT) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    handle.close();

    return await isReady();
  }

  @override
  Future<void> uninstall() async {
    if (_portable) return;
    await stop();

    if (!await isReady()) return;
    final svcPath = ServiceManager.serviceBinaryPath();
    await Process.run(svcPath, ['service', 'uninstall']);
  }

  @override
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

  @override
  Future<bool> start() async {
    final svc = _openService(SERVICE_QUERY_STATUS | SERVICE_START);
    if (svc != null) {
      final result = StartService(svc, 0, null);
      svc.close();
      if (!result.value && result.error != ERROR_SERVICE_ALREADY_RUNNING) {
        return false;
      }
      return true;
    }
    if (_portable) {
      final params = [
        'ipc',
        '--home',
        homeDir,
      ].map((a) => a.contains(' ') ? '"$a"' : a).join(' ');
      final handle = _runas(params);
      if (handle == null) return false;
      handle.close();
      _elevated = true;
      return true;
    }
    return _startDirectProcess();
  }

  @override
  Future<bool> startDirect() => _startDirectProcess();

  Future<bool> _startDirectProcess() async {
    try {
      final svcPath = ServiceManager.serviceBinaryPath();
      _directProcess = await Process.start(svcPath, [
        'ipc',
        '--home',
        homeDir,
      ], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    final svc = _openService(SERVICE_QUERY_STATUS | SERVICE_STOP);
    if (svc != null) {
      try {
        final status = calloc<SERVICE_STATUS>();
        try {
          ControlService(svc, SERVICE_CONTROL_STOP, status);
        } finally {
          free(status);
        }
      } finally {
        svc.close();
      }
      if (!await _waitForIpcGone()) {
        // Service didn't stop gracefully — force kill the process.
        await Process.run('taskkill', ['/F', '/IM', 'singcast-core.exe']);
        await _waitForIpcGone();
      }
      return true;
    }
    // Kill direct process
    _directProcess?.kill();
    _directProcess = null;
    await _waitForIpcGone();
    _elevated = false;
    return true;
  }

  /// Wait until IPC is no longer reachable (after stop).
  /// Returns true if IPC went away within the timeout.
  Future<bool> _waitForIpcGone() async {
    for (int i = 0; i < 20; i++) {
      if (!await isRunning()) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }
}
