// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Profile _$ProfileFromJson(Map<String, dynamic> json) => Profile(
      file: json['file'] as String,
      name: json['name'] as String,
      type: $enumDecode(_$ProfileTypeEnumMap, json['type']),
      time: DateTime.parse(json['time'] as String),
      url: json['url'] as String?,
      interval: (json['interval'] as num?)?.toInt() ?? 0,
      userinfo: json['userinfo'] == null
          ? null
          : SubscriptionInfo.fromJson(json['userinfo'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ProfileToJson(Profile instance) => <String, dynamic>{
      'file': instance.file,
      'name': instance.name,
      'type': _$ProfileTypeEnumMap[instance.type]!,
      'time': instance.time.toIso8601String(),
      'url': instance.url,
      'interval': instance.interval,
      'userinfo': instance.userinfo,
    };

const _$ProfileTypeEnumMap = {
  ProfileType.url: 'url',
  ProfileType.file: 'file',
};
