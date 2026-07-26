import 'dart:io';

import '../domain/enums.dart';
import 'service_manager.dart';

/// macOS: setuid 副本（osascript）。
class MacOSServiceManager extends ServiceManager with ServiceManagerLogging {
  final String homeDir;
  Process? _directProcess;

  MacOSServiceManager(this.homeDir);

  @override
  String get ipcPath => ServiceManager.defaultIpcPath(homeDir);

  /// setuid 副本路径（app bundle 外，避免破坏签名）。
  String get _elevatedBinaryPath => '$homeDir/singcast-core';

  /// bundle 二进制 mtime 标记，app 更新后失效。
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
      if (!File(_elevatedBinaryPath).existsSync()) return false;
      if (!_elevatedUpToDate()) return false;
      final stat = await FileStat.stat(_elevatedBinaryPath);
      const setuidBit = 0x800;
      return (stat.mode & setuidBit) != 0;
    } catch (e) {
      logMsg('isReady failed: $e', level: LogLevel.warning);
      return false;
    }
  }

  @override
  Future<bool> setup() async {
    try {
      final elevated = _elevatedBinaryPath;
      await Directory(homeDir).create(recursive: true);
      if (File(elevated).existsSync()) {
        await File(elevated).delete();
      }
      await File(ServiceManager.serviceBinaryPath()).copy(elevated);
      await Process.run('chmod', ['+x', elevated]);
      final result = await Process.run('osascript', [
        '-e',
        'do shell script "chown root:admin \\"$elevated\\" && chmod +sx \\"$elevated\\"" with administrator privileges',
      ]);
      if (result.exitCode != 0) {
        logMsg(
          'macOS setuid failed: ${procSummary(result)}',
          level: LogLevel.error,
        );
        return false;
      }
      final bundleStat = FileStat.statSync(ServiceManager.serviceBinaryPath());
      await File(
        _elevatedMarkerPath,
      ).writeAsString(bundleStat.modified.millisecondsSinceEpoch.toString());
      return true;
    } catch (e) {
      logMsg('setup failed: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<void> uninstall() async {
    try {
      if (File(_elevatedBinaryPath).existsSync()) {
        await File(_elevatedBinaryPath).delete();
      }
      final marker = File(_elevatedMarkerPath);
      if (marker.existsSync()) await marker.delete();
    } catch (e) {
      logMsg('macOS uninstall failed: $e', level: LogLevel.warning);
    }
  }

  @override
  Future<bool> start() async {
    try {
      String svcPath = ServiceManager.serviceBinaryPath();
      if (File(_elevatedBinaryPath).existsSync()) {
        if (_elevatedUpToDate()) {
          svcPath = _elevatedBinaryPath;
        } else {
          await uninstall();
        }
      }
      _directProcess = await Process.start(svcPath, [
        'ipc',
        '--home',
        homeDir,
      ], mode: ProcessStartMode.detached);
      return true;
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
      return true;
    } catch (e) {
      logMsg('startDirect failed: $e', level: LogLevel.error);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _directProcess?.kill();
    _directProcess = null;
    if (await waitForIpcGone()) return true;
    logMsg(
      'Process still alive after kill, force pkill singcast-core',
      level: LogLevel.warning,
    );
    await Process.run('pkill', ['-f', 'singcast-core.*ipc']);
    await waitForIpcGone();
    return true;
  }
}
