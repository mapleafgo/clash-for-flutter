import 'package:json_annotation/json_annotation.dart';

import 'enums.dart';

part 'config.g.dart';

@JsonSerializable()
class ClashConfig {
  @JsonKey(name: 'mixed-port')
  final int? mixedPort;
  @JsonKey(name: 'allow-lan')
  final bool? allowLan;
  final Mode? mode;
  @JsonKey(name: 'log-level')
  final LogLevel? logLevel;
  final bool? ipv6;
  final TunConfig? tun;
  @JsonKey(name: 'external-controller')
  final bool? externalController;
  @JsonKey(name: 'external-controller-addr')
  final String? externalControllerAddr;
  @JsonKey(name: 'port-enabled')
  final bool? portEnabled;

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
  });

  factory ClashConfig.fromJson(Map<String, dynamic> json) =>
      _$ClashConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ClashConfigToJson(this);

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
      );

  bool get tunEnabled => tun?.enable ?? false;
  int get port => mixedPort ?? 0;
  bool get apiEnabled => externalController ?? false;
  String get apiAddr => externalControllerAddr ?? '127.0.0.1:9090';
  bool get userPortEnabled => portEnabled ?? false;
}

@JsonSerializable()
class TunConfig {
  final bool? enable;
  TunConfig({this.enable});

  TunConfig copyWith({bool? enable}) => TunConfig(enable: enable ?? this.enable);

  factory TunConfig.fromJson(Map<String, dynamic> json) =>
      _$TunConfigFromJson(json);
  Map<String, dynamic> toJson() => _$TunConfigToJson(this);
}
