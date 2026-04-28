import 'dart:async';
import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/core/tun_elevation.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:signals_flutter/signals_flutter.dart';

final clashConfig = signal(ClashConfig.defaults());

Timer? _syncTimer;

void initCoreConfig() {
  if (CoreConfigStorage.exists()) {
    clashConfig.value = CoreConfigStorage.load();
  }
  effect(() {
    final config = clashConfig.value;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      CoreConfigStorage.save(config);
    });
    _syncModeToCore(config.mode);
  });
  // 监听通知栏断开 VPN 事件，同步本地状态
  effect(() {
    if (LibCore.instance.vpnDisconnectedByUser.value) {
      _setTunEnabled(false);
      LibCore.instance.vpnDisconnectedByUser.value = false;
    }
  });
  detectElevation();
}

void _saveSync() {
  CoreConfigStorage.save(clashConfig.value);
}

Future<void> _syncModeToCore(Mode? mode) async {
  if (mode == null) return;
  try {
    await LibCore.instance.setMode(mode.name);
    LibCore.instance.modeSignal.value = mode.name;
  } catch (e) {
    print('[core_config] setMode(${mode.name}) failed: $e');
  }
}

void updateClashConfig({
  int? mixedPort,
  bool? allowLan,
  Mode? mode,
  LogLevel? logLevel,
  bool? ipv6,
}) {
  final old = clashConfig.value;
  clashConfig.value = ClashConfig(
    mixedPort: mixedPort ?? old.mixedPort,
    allowLan: allowLan ?? old.allowLan,
    mode: mode ?? old.mode,
    logLevel: logLevel ?? old.logLevel,
    ipv6: ipv6 ?? old.ipv6,
    tun: old.tun,
  );
}

void watchModeFromCore() {
  effect(() {
    final modeStr = LibCore.instance.modeSignal.value;
    final mode = Mode.values.where((m) => m.name == modeStr).firstOrNull;
    if (mode != null && clashConfig.value.mode != mode) {
      clashConfig.value = ClashConfig(
        mixedPort: clashConfig.value.mixedPort,
        allowLan: clashConfig.value.allowLan,
        mode: mode,
        logLevel: clashConfig.value.logLevel,
        ipv6: clashConfig.value.ipv6,
        tun: clashConfig.value.tun,
      );
    }
  });
}

Future<void> toggleTun(bool enable) async {
  if (enable) {
    await openTun();
  } else {
    await closeTun();
  }
}

Future<void> openTun() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await _openTunMobile();
  } else {
    await _openTunDesktop();
  }
}

Future<void> closeTun() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await _closeTunMobile();
  } else {
    await _closeTunDesktop();
  }
}

// --- Desktop TUN ---

Future<void> _openTunDesktop() async {
  if (!coreElevated.value) {
    if (Platform.isLinux) {
      // Linux: one-time setcap, then restart normally (no root needed)
      final ok = await setupTunCapability();
      if (!ok) {
        throw TunElevationException('授予网络权限失败，请确认 pkexec 可用');
      }
      _setTunEnabled(true);
      await relaunchSelf();
    } else {
      // macOS/Windows: restart with admin privileges
      _setTunEnabled(true);
      await relaunchElevated();
    }
    return;
  }
  _setTunEnabled(true);
  await _reloadCoreWithCurrentProfile();
}

Future<void> _closeTunDesktop() async {
  _setTunEnabled(false);
  await _reloadCoreWithCurrentProfile();
}

void _setTunEnabled(bool enable) {
  clashConfig.value = ClashConfig(
    mixedPort: clashConfig.value.mixedPort,
    allowLan: clashConfig.value.allowLan,
    mode: clashConfig.value.mode,
    logLevel: clashConfig.value.logLevel,
    ipv6: clashConfig.value.ipv6,
    tun: TunConfig(enable: enable),
  );
  _saveSync();
}

Future<void> _reloadCoreWithCurrentProfile() async {
  final file = selectedFile.value;
  if (file == null) return;

  final path = _resolveProfilePath(file);
  if (!File(path).existsSync()) return;

  try {
    final yamlContent = await File(path).readAsString();
    final merged = mergeProfileConfig(yamlContent);
    await LibCore.instance.stopCore();
    await LibCore.instance.startCoreWithContent(
      merged,
      ruleSetProxy: ruleSetProxy.value,
    );
  } catch (_) {}
}

// --- Mobile TUN ---

Future<void> _openTunMobile() async {
  final file = selectedFile.value;
  if (file == null) return;

  final path = _resolveProfilePath(file);
  if (!File(path).existsSync()) return;

  try {
    final yamlContent = await File(path).readAsString();
    final merged = mergeProfileConfig(yamlContent);
    await LibCore.instance.connectVpn(merged, ruleSetProxy: ruleSetProxy.value);

    _setTunEnabled(true);
  } catch (e) {
    rethrow;
  }
}

Future<void> _closeTunMobile() async {
  try {
    await LibCore.instance.disconnectVpn();
  } catch (_) {}

  _setTunEnabled(false);
}

String _resolveProfilePath(String file) {
  if (file.startsWith('/')) return file;
  return '${Constants.homeDir.path}${Constants.profilesPath}/$file';
}
