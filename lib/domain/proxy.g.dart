// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proxy.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Proxy _$ProxyFromJson(Map<String, dynamic> json) => Proxy(
      name: json['name'] as String,
      type: json['type'] as String?,
      history: (json['history'] as List<dynamic>?)
          ?.map((e) => ProxyHistory.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ProxyToJson(Proxy instance) => <String, dynamic>{
      'name': instance.name,
      'type': instance.type,
      'history': instance.history,
    };

ProxyHistory _$ProxyHistoryFromJson(Map<String, dynamic> json) => ProxyHistory(
      time: json['time'] as String,
      delay: (json['delay'] as num).toInt(),
    );

Map<String, dynamic> _$ProxyHistoryToJson(ProxyHistory instance) =>
    <String, dynamic>{
      'time': instance.time,
      'delay': instance.delay,
    };
