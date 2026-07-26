import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../domain/enums.dart';
import 'service_manager.dart';

/// Windows: SCM 服务 + UAC 提权（ShellExecuteEx runas）。
class WindowsServiceManager extends ServiceManager with ServiceManagerLogging {
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
    ].map((a) => a.contains(' ') ? '"$a"' : a).join(' ');
    final handle = _runas(params);
    if (handle == null) {
      logMsg('ShellExecuteEx runas failed', level: LogLevel.error);
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
    final result = await Process.run(svcPath, ['service', 'uninstall']);
    if (result.exitCode != 0) {
      logMsg(
        'Windows service uninstall failed: ${procSummary(result)}',
        level: LogLevel.warning,
      );
    }
  }

  @override
  Future<bool> start() async {
    final svc = _openService(SERVICE_QUERY_STATUS | SERVICE_START);
    if (svc != null) {
      final result = StartService(svc, 0, null);
      svc.close();
      if (!result.value && result.error != ERROR_SERVICE_ALREADY_RUNNING) {
        logMsg(
          'StartService failed: error=${result.error}',
          level: LogLevel.error,
        );
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
    } catch (e) {
      logMsg('_startDirectProcess failed: $e', level: LogLevel.error);
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
      if (!await waitForIpcGone()) {
        // Service didn't stop gracefully — force kill the process.
        logMsg(
          'Service stop timeout, force killing singcast-core.exe',
          level: LogLevel.warning,
        );
        await Process.run('taskkill', ['/F', '/IM', 'singcast-core.exe']);
        await waitForIpcGone();
      }
      return true;
    }
    // Kill direct process
    _directProcess?.kill();
    _directProcess = null;
    await waitForIpcGone();
    _elevated = false;
    return true;
  }
}
