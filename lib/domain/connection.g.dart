// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Connection _$ConnectionFromJson(Map<String, dynamic> json) => Connection(
      id: json['id'] as String,
      upload: (json['upload'] as num).toInt(),
      download: (json['download'] as num).toInt(),
      start: json['start'] as String,
      chains:
          (json['chains'] as List<dynamic>).map((e) => e as String).toList(),
      rule: json['rule'] as String,
      rulePayload: json['rulePayload'] as String,
      metadata:
          ConnectionMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ConnectionToJson(Connection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'upload': instance.upload,
      'download': instance.download,
      'start': instance.start,
      'chains': instance.chains,
      'rule': instance.rule,
      'rulePayload': instance.rulePayload,
      'metadata': instance.metadata,
    };

ConnectionMetadata _$ConnectionMetadataFromJson(Map<String, dynamic> json) =>
    ConnectionMetadata(
      network: json['network'] as String,
      type: json['type'] as String,
      host: json['host'] as String,
      processPath: json['processPath'] as String,
      sourceIP: json['sourceIP'] as String,
      sourcePort: json['sourcePort'] as String,
      destinationIP: json['destinationIP'] as String,
      destinationPort: json['destinationPort'] as String,
      process: json['process'] as String,
      dnsMode: json['dnsMode'] as String,
    );

Map<String, dynamic> _$ConnectionMetadataToJson(ConnectionMetadata instance) =>
    <String, dynamic>{
      'network': instance.network,
      'type': instance.type,
      'host': instance.host,
      'processPath': instance.processPath,
      'sourceIP': instance.sourceIP,
      'sourcePort': instance.sourcePort,
      'destinationIP': instance.destinationIP,
      'destinationPort': instance.destinationPort,
      'process': instance.process,
      'dnsMode': instance.dnsMode,
    };

ConnectionsSnapshot _$ConnectionsSnapshotFromJson(Map<String, dynamic> json) =>
    ConnectionsSnapshot(
      uploadTotal: (json['uploadTotal'] as num).toInt(),
      downloadTotal: (json['downloadTotal'] as num).toInt(),
      connections: (json['connections'] as List<dynamic>)
          .map((e) => Connection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ConnectionsSnapshotToJson(
        ConnectionsSnapshot instance) =>
    <String, dynamic>{
      'uploadTotal': instance.uploadTotal,
      'downloadTotal': instance.downloadTotal,
      'connections': instance.connections,
    };
