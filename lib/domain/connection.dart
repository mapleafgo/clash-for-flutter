import 'package:json_annotation/json_annotation.dart';

part 'connection.g.dart';

@JsonSerializable()
class Connection {
  final String id;
  final int upload;
  final int download;
  final String start;
  final List<String> chains;
  final String rule;
  @JsonKey(name: 'rulePayload')
  final String rulePayload;
  final ConnectionMetadata metadata;

  Connection({
    required this.id,
    required this.upload,
    required this.download,
    required this.start,
    required this.chains,
    required this.rule,
    required this.rulePayload,
    required this.metadata,
  });

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionToJson(this);
}

@JsonSerializable()
class ConnectionMetadata {
  final String network;
  final String type;
  final String host;
  @JsonKey(name: 'processPath')
  final String processPath;
  final String sourceIP;
  final String sourcePort;
  final String destinationIP;
  final String destinationPort;
  final String process;
  final String dnsMode;

  ConnectionMetadata({
    required this.network,
    required this.type,
    required this.host,
    required this.processPath,
    required this.sourceIP,
    required this.sourcePort,
    required this.destinationIP,
    required this.destinationPort,
    required this.process,
    required this.dnsMode,
  });

  factory ConnectionMetadata.fromJson(Map<String, dynamic> json) =>
      _$ConnectionMetadataFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionMetadataToJson(this);
}

@JsonSerializable()
class ConnectionsSnapshot {
  final int uploadTotal;
  final int downloadTotal;
  final List<Connection> connections;

  ConnectionsSnapshot({
    required this.uploadTotal,
    required this.downloadTotal,
    required this.connections,
  });

  factory ConnectionsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$ConnectionsSnapshotFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionsSnapshotToJson(this);
}