import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class Config {
  int port;
  @JsonProperty(name: "socks-port")
  int socksPort;
  @JsonProperty(name: "redir-port")
  int redirPort;
  @JsonProperty(name: "mixed-port")
  int mixedPort;
  @JsonProperty(name: "allow-lan")
  bool allowLan;
  String mode;
  @JsonProperty(name: "log-level")
  String logLevel;

  Config(
      {this.port,
      this.socksPort,
      this.redirPort,
      this.mixedPort,
      this.allowLan,
      this.mode,
      this.logLevel});
}
