import 'dart:async';

import 'package:clash_for_flutter/core_control.dart' as core;
import 'package:clash_for_flutter/data/local/core_config_storage.dart';
import 'package:clash_for_flutter/domain/config.dart';
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:signals_flutter/signals_flutter.dart';

final clashConfig = signal(ClashConfig.defaults());

Timer? _syncTimer;

void initCoreConfig() {
  effect(() {
    clashConfig.value;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      CoreConfigStorage.save(clashConfig.value);
      api.patchConfigs(clashConfig.value);
    });
  });
}

Future<void> syncFromCore() async {
  final config = await api.getConfigs();
  if (config != null) clashConfig.value = config;
}

void updateClashConfig({
  int? mixedPort,
  int? redirPort,
  int? tproxyPort,
  bool? allowLan,
  Mode? mode,
  LogLevel? logLevel,
  bool? ipv6,
}) {
  final old = clashConfig.value;
  clashConfig.value = ClashConfig(
    mixedPort: mixedPort ?? old.mixedPort,
    redirPort: redirPort ?? old.redirPort,
    tproxyPort: tproxyPort ?? old.tproxyPort,
    allowLan: allowLan ?? old.allowLan,
    mode: mode ?? old.mode,
    logLevel: logLevel ?? old.logLevel,
    ipv6: ipv6 ?? old.ipv6,
    tun: old.tun,
  );
}

Future<void> openTun() async {
  if (Constants.isDesktop) {
    await api.patchConfigs(ClashConfig(tun: TunConfig(enable: true)));
  } else {
    await core.CoreControl.startVpn();
  }
  await syncFromCore();
}

Future<void> closeTun() async {
  if (Constants.isDesktop) {
    await api.patchConfigs(ClashConfig(tun: TunConfig(enable: false)));
  } else {
    await core.CoreControl.stopVpn();
  }
  await syncFromCore();
}
