import 'dart:io';

import 'package:signals_flutter/signals_flutter.dart';

final coreElevated = signal(false);

void detectElevation() {
  if (Platform.isLinux) {
    if (_isRunningAsRoot()) {
      coreElevated.value = true;
      return;
    }
    _checkCapabilityAsync();
  } else if (Platform.isMacOS) {
    coreElevated.value = _isRunningAsRoot();
  } else if (Platform.isWindows) {
    coreElevated.value = true;
  }
}

bool _isRunningAsRoot() {
  return Platform.environment['USER'] == 'root' ||
      Platform.environment['SUDO_UID'] != null ||
      Platform.environment['PKEXEC_UID'] != null;
}

Future<void> _checkCapabilityAsync() async {
  try {
    final result = await Process.run(
      'getcap',
      [Platform.resolvedExecutable],
    );
    final output = (result.stdout ?? '').toString();
    coreElevated.value = output.contains('cap_net_admin');
  } catch (_) {
    coreElevated.value = false;
  }
}

Future<bool> setupTunCapability() async {
  if (!Platform.isLinux) return false;
  try {
    final result = await Process.run(
      'pkexec',
      ['setcap', 'cap_net_admin,cap_net_bind_service+ep', Platform.resolvedExecutable],
    );
    if (result.exitCode == 0) {
      coreElevated.value = true;
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<void> relaunchSelf() async {
  await Process.start(
    Platform.resolvedExecutable,
    [],
    workingDirectory: Directory.current.path,
    mode: ProcessStartMode.detached,
  );
  exit(0);
}

Future<void> relaunchElevated() async {
  final exe = Platform.resolvedExecutable;

  if (Platform.isLinux) {
    await Process.start(
      'pkexec',
      ['--disable-internal-agent', exe],
      mode: ProcessStartMode.detached,
    );
  } else if (Platform.isMacOS) {
    await Process.start(
      'osascript',
      [
        '-e',
        'do shell script "open \\"$exe\\"" with administrator privileges',
      ],
      mode: ProcessStartMode.detached,
    );
  } else if (Platform.isWindows) {
    await Process.start(
      'powershell',
      ['-Command', 'Start-Process -Verb RunAs -FilePath "\$exe"'],
      mode: ProcessStartMode.detached,
    );
  }

  exit(0);
}

class TunElevationException implements Exception {
  final String message;
  TunElevationException(this.message);

  @override
  String toString() => 'TunElevationException: $message';
}
