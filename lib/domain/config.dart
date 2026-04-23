import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'config.g.dart';

@JsonSerializable()
class ClashConfig {
  @JsonKey(name: 'mixed-port')
  final int? mixedPort;
  @JsonKey(name: 'redir-port')
  final int? redirPort;
  @JsonKey(name: 'tproxy-port')
  final int? tproxyPort;
  @JsonKey(name: 'allow-lan')
  final bool? allowLan;
  final Mode? mode;
  @JsonKey(name: 'log-level')
  final LogLevel? logLevel;
  final bool? ipv6;
  final TunConfig? tun;

  ClashConfig({
    this.mixedPort,
    this.redirPort,
    this.tproxyPort,
    this.allowLan,
    this.mode,
    this.logLevel,
    this.ipv6,
    this.tun,
  });

  factory ClashConfig.fromJson(Map<String, dynamic> json) =>
      _$ClashConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ClashConfigToJson(this);

  factory ClashConfig.defaults() => ClashConfig(mixedPort: 7890);

  bool get tunEnabled => tun?.enable ?? false;
  int get port => mixedPort ?? 0;
}

@JsonSerializable()
class TunConfig {
  final bool? enable;
  TunConfig({this.enable});
  factory TunConfig.fromJson(Map<String, dynamic> json) =>
      _$TunConfigFromJson(json);
  Map<String, dynamic> toJson() => _$TunConfigToJson(this);
}