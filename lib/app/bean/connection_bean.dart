import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class Connection {
  String id;
  int upload;
  int download;
  String start;
  List<String> chains;
  String rule;
  String rulePayload;
  Metadata metadata;

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

  Connection.empty()
      : this(
          id: "",
          upload: 0,
          download: 0,
          start: "",
          chains: [],
          rule: "",
          rulePayload: "",
          metadata: Metadata(
            network: "",
            type: "",
            host: "",
            processPath: "",
            sourceIP: "",
            sourcePort: "",
            destinationIP: "",
            destinationPort: "",
            dnsMode: "",
            specialProxy: "",
          ),
        );
}

@JsonSerializable()
class Metadata {
  String network;
  String type;
  String host;
  String processPath;
  String sourceIP;
  String sourcePort;
  String destinationIP;
  String destinationPort;
  String dnsMode;
  String specialProxy;

  Metadata({
    required this.network,
    required this.type,
    required this.host,
    required this.processPath,
    required this.sourceIP,
    required this.sourcePort,
    required this.destinationIP,
    required this.destinationPort,
    required this.dnsMode,
    required this.specialProxy,
  });
}

@JsonSerializable()
class Snapshot {
  int uploadTotal;
  int downloadTotal;
  List<Connection> connections;

  Snapshot({
    required this.uploadTotal,
    required this.downloadTotal,
    required this.connections,
  });

  Snapshot.empty() : this(uploadTotal: 0, downloadTotal: 0, connections: []);
}
