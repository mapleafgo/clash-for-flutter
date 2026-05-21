import 'dart:ffi';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' as ipc;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'ipc/json_rpc_client.dart';

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

  /// Whether the service process is currently running.
  Future<bool> isRunning();

  /// Start the service process.
  Future<bool> start();

  /// Stop the service process.
  Future<bool> stop();

  /// Create the platform-appropriate ServiceManager.
  static ServiceManager create(String homeDir) {
    if (Platform.isWindows) return WindowsServiceManager(homeDir);
    if (Platform.isLinux || Platform.isMacOS) return UnixServiceManager(homeDir);
    throw UnsupportedError('Unsupported platform for ServiceManager');
  }

  /// IPC path matching cff-core's ipc.IpcPath(homeDir).
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
      final bundleStat =
          FileStat.statSync(ServiceManager.serviceBinaryPath());
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
          'sh', '-c',
          'setcap cap_net_admin+ep "\$1"',
          'sh', svcPath,
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
      final bundleStat =
          FileStat.statSync(ServiceManager.serviceBinaryPath());
      await File(_elevatedMarkerPath)
          .writeAsString(bundleStat.modified.millisecondsSinceEpoch.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isRunning() async {
    try {
      final socket = await ipc.connect(ipcPath).timeout(const Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> start() async {
    try {
      // macOS: prefer external copy (has setuid for TUN) over bundle binary
      final svcPath =
          Platform.isMacOS && File(_elevatedBinaryPath).existsSync()
              ? _elevatedBinaryPath
              : ServiceManager.serviceBinaryPath();
      _directProcess = await Process.start(
        svcPath,
        ['ipc', '--home', homeDir],
        mode: ProcessStartMode.detached,
      );
      // Wait until the IPC endpoint is actually reachable.
      return await _waitForIpcReady();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _directProcess?.kill();
    _directProcess = null;
    // The caller (LibCore.restart) stops the kernel and disconnects IPC
    // before calling stop(). cff-core self-terminates when kernel is
    // stopped and all GUI connections close — no need to forcefully kill
    // a setuid root process from user space.
    if (await _waitForIpcGone()) return true;
    // Last resort: signal the process (won't work for root, but harmless).
    await Process.run('pkill', ['-f', 'singcast-core.*ipc']);
    await _waitForIpcGone();
    return true;
  }

  /// Wait until IPC becomes reachable (after start).
  Future<bool> _waitForIpcReady() async {
    for (int i = 0; i < 30; i++) {
      if (await isRunning()) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
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
  Process? _directProcess;
  int? _elevatedHandle; // HANDLE from ShellExecuteExW

  WindowsServiceManager(this.homeDir);

  @override
  String get ipcPath => ServiceManager.defaultIpcPath(homeDir);

  /// Open a handle to the installed service with [access] rights.
  /// Returns the service handle, or 0 if the service is not installed
  /// or the caller lacks permission.
  int _openService(int access) {
    final nullPtr = Pointer<Utf16>.fromAddress(0);
    final scm = OpenSCManager(nullPtr, nullPtr, SC_MANAGER_CONNECT);
    if (scm == 0) return 0;
    try {
      final namePtr = _serviceName.toNativeUtf16();
      try {
        return OpenService(scm, namePtr, access);
      } finally {
        free(namePtr);
      }
    } finally {
      CloseServiceHandle(scm);
    }
  }

  @override
  Future<bool> isReady() async {
    final svc = _openService(SERVICE_QUERY_STATUS);
    if (svc == 0) return false;
    CloseServiceHandle(svc);
    return true;
  }

  @override
  Future<bool> setup() async {
    // 1. Stop current direct process to free the IPC path for the UAC temp
    await stop();

    // 2. UAC-elevate to start a temporary core ipc process
    final svcPath = ServiceManager.serviceBinaryPath();
    final ok = _shellExecuteRunas(svcPath, ['ipc', '--home', homeDir]);
    if (!ok) return false;

    // 3. Wait for IPC to become ready via connect-retry
    bool ready = false;
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final client = JsonRpcClient(path: ipcPath);
        await client.connect();
        // Connected — call service.install, then disconnect
        try {
          await client.call('service.install');
          ready = true;
        } on JsonRpcException {
          return false;
        } finally {
          await client.disconnect();
          client.dispose();
        }
        break;
      } catch (_) {}
    }
    if (!ready) return false;

    // 4. Wait for the temp process to exit (cff-core exits when GUI
    //    disconnects and kernel is not running).
    await _waitForElevatedExit();

    return true;
  }

  @override
  Future<bool> isRunning() async {
    try {
      final socket = await ipc.connect(ipcPath).timeout(const Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> start() async {
    final svc = _openService(SERVICE_QUERY_STATUS | SERVICE_START);
    if (svc != 0) {
      // Service installed — start via SCM.
      final result = StartService(svc, 0, Pointer<Pointer<Utf16>>.fromAddress(0));
      CloseServiceHandle(svc);
      // StartService returns non-zero on success.
      // If already running, GetLastError() == ERROR_SERVICE_ALREADY_RUNNING.
      if (result == 0 && GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) {
        return false;
      }
    } else {
      // No service — direct process (non-TUN, no privileges needed)
      final svcPath = ServiceManager.serviceBinaryPath();
      _directProcess = await Process.start(
        svcPath,
        ['ipc', '--home', homeDir],
        mode: ProcessStartMode.detached,
      );
    }
    // Wait until the IPC endpoint is actually reachable.
    if (!await _waitForIpcReady()) return false;
    return true;
  }

  @override
  Future<bool> stop() async {
    final svc = _openService(SERVICE_QUERY_STATUS | SERVICE_STOP);
    if (svc != 0) {
      try {
        final status = calloc<SERVICE_STATUS>();
        try {
          ControlService(svc, SERVICE_CONTROL_STOP, status);
        } finally {
          free(status);
        }
      } finally {
        CloseServiceHandle(svc);
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
    return true;
  }

  /// Wait until IPC becomes reachable (after start).
  Future<bool> _waitForIpcReady() async {
    for (int i = 0; i < 30; i++) {
      if (await isRunning()) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
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

  /// Wait for the elevated temp process to exit via HANDLE.
  Future<void> _waitForElevatedExit() async {
    if (_elevatedHandle != null) {
      while (WaitForSingleObject(_elevatedHandle!, 100) == WAIT_TIMEOUT) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      CloseHandle(_elevatedHandle!);
      _elevatedHandle = null;
    } else {
      await _waitForIpcGone();
    }
  }

  /// UAC-elevate via ShellExecuteExW with "runas" verb.
  bool _shellExecuteRunas(String exe, List<String> args) {
    final exePtr = exe.toNativeUtf16();
    final paramsPtr = args.join(' ').toNativeUtf16();
    final verbPtr = 'runas'.toNativeUtf16();
    final dirPtr = File(exe).parent.path.toNativeUtf16();

    try {
      final info = calloc<SHELLEXECUTEINFO>();
      info.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
      info.ref.fMask = 0x00000100 | 0x00000040; // NOCLOSEPROCESS | NOASYNC
      info.ref.lpVerb = verbPtr;
      info.ref.lpFile = exePtr;
      info.ref.lpParameters = paramsPtr;
      info.ref.lpDirectory = dirPtr;
      info.ref.nShow = SW_HIDE;

      final result = ShellExecuteEx(info);
      if (result == FALSE) return false;

      _elevatedHandle = info.ref.hProcess;
      return true;
    } finally {
      free(exePtr);
      free(paramsPtr);
      free(verbPtr);
      free(dirPtr);
    }
  }
}
