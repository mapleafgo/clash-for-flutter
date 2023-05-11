import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class ConnectionShow {
  String id;
  String host;
  String network;
  String process;
  String type;
  String chains;
  String rule;
  String speed;
  String upload;
  String download;
  String sourceIP;
  String time;

  ConnectionShow({
    required this.id,
    required this.host,
    required this.network,
    required this.process,
    required this.type,
    required this.chains,
    required this.rule,
    required this.speed,
    required this.upload,
    required this.download,
    required this.sourceIP,
    required this.time,
  });
}
