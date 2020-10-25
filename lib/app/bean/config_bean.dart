import 'package:json_annotation/json_annotation.dart';

part 'config_bean.g.dart';

@JsonSerializable()
class Config {
  int port;
  @JsonKey(name: "socks-port")
  int socksPort;
  @JsonKey(name: "redir-port")
  int redirPort;
  @JsonKey(name: "mixed-port")
  int mixedPort;
  @JsonKey(name: "allow-lan")
  bool allowLan;
  String mode;
  @JsonKey(name: "log-level")
  String logLevel;

  Config(
      {this.port,
      this.socksPort,
      this.redirPort,
      this.mixedPort,
      this.allowLan,
      this.mode,
      this.logLevel});

  factory Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ConfigToJson(this);
}
