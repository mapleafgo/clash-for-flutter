import 'package:singcast/utils/constants.dart';

import 'enums.dart';

class SingboxConfig {
  final int? mixedPort;
  final bool? allowLan;
  final Mode? mode;
  final LogLevel? logLevel;
  final bool? ipv6;
  final TunConfig? tun;
  final bool? externalController;
  final String? externalControllerAddr;
  final bool? portEnabled;
  final bool? systemProxy;

  SingboxConfig({
    this.mixedPort,
    this.allowLan,
    this.mode,
    this.logLevel,
    this.ipv6,
    this.tun,
    this.externalController,
    this.externalControllerAddr,
    this.portEnabled,
    this.systemProxy,
  });

  factory SingboxConfig.defaults() => SingboxConfig(
      mixedPort: Constants.defaultMixedPort,
      externalControllerAddr: Constants.defaultApiAddr,
      portEnabled: false);

  SingboxConfig copyWith({
    int? mixedPort,
    bool? allowLan,
    Mode? mode,
    LogLevel? logLevel,
    bool? ipv6,
    TunConfig? tun,
    bool? externalController,
    String? externalControllerAddr,
    bool? portEnabled,
    bool? systemProxy,
  }) =>
      SingboxConfig(
        mixedPort: mixedPort ?? this.mixedPort,
        allowLan: allowLan ?? this.allowLan,
        mode: mode ?? this.mode,
        logLevel: logLevel ?? this.logLevel,
        ipv6: ipv6 ?? this.ipv6,
        tun: tun ?? this.tun,
        externalController: externalController ?? this.externalController,
        externalControllerAddr:
            externalControllerAddr ?? this.externalControllerAddr,
        portEnabled: portEnabled ?? this.portEnabled,
        systemProxy: systemProxy ?? this.systemProxy,
      );

  bool get tunEnabled => tun?.enable ?? false;
  bool get apiEnabled => externalController ?? false;
  String get apiAddr => externalControllerAddr ?? Constants.defaultApiAddr;
  bool get userPortEnabled => portEnabled ?? false;
  bool get systemProxyEnabled => systemProxy ?? false;
}

class TunConfig {
  final bool? enable;
  TunConfig({this.enable});

}
