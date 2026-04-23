// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proxy_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProxyGroup _$ProxyGroupFromJson(Map<String, dynamic> json) => ProxyGroup(
      name: json['name'] as String,
      type: json['type'] as String,
      all: (json['all'] as List<dynamic>).map((e) => e as String).toList(),
      now: json['now'] as String,
    );

Map<String, dynamic> _$ProxyGroupToJson(ProxyGroup instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': instance.type,
      'all': instance.all,
      'now': instance.now,
    };
