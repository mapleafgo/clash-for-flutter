import 'enums.dart';


class ClashConfig {
  final int? mixedPort;
  final bool? allowLan;
  final Mode? mode;
  final LogLevel? logLevel;
  final bool? ipv6;
  final TunConfig? tun;
  final bool? externalController;
  final String? externalControllerAddr;
  final bool? portEnabled;
  final bool? mixedSystemProxy;

  ClashConfig({
    this.mixedPort,
    this.allowLan,
    this.mode,
    this.logLevel,
    this.ipv6,
    this.tun,
    this.externalController,
    this.externalControllerAddr,
    this.portEnabled,
    this.mixedSystemProxy,
  });

  factory ClashConfig.defaults() => ClashConfig(
      mixedPort: 7890,
      externalControllerAddr: '127.0.0.1:9090',
      portEnabled: false);

  ClashConfig copyWith({
    int? mixedPort,
    bool? allowLan,
    Mode? mode,
    LogLevel? logLevel,
    bool? ipv6,
    TunConfig? tun,
    bool? externalController,
    String? externalControllerAddr,
    bool? portEnabled,
    bool? mixedSystemProxy,
  }) =>
      ClashConfig(
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
        mixedSystemProxy: mixedSystemProxy ?? this.mixedSystemProxy,
      );

  bool get tunEnabled => tun?.enable ?? false;
  bool get apiEnabled => externalController ?? false;
  String get apiAddr => externalControllerAddr ?? '127.0.0.1:9090';
  bool get userPortEnabled => portEnabled ?? false;
  bool get systemProxyEnabled => mixedSystemProxy ?? false;
}

class TunConfig {
  final bool? enable;
  TunConfig({this.enable});

}
