// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SubscriptionInfo _$SubscriptionInfoFromJson(Map<String, dynamic> json) =>
    SubscriptionInfo(
      upload: (json['upload'] as num?)?.toInt(),
      download: (json['download'] as num?)?.toInt(),
      total: (json['total'] as num?)?.toInt(),
      expire: (json['expire'] as num?)?.toInt(),
    );

Map<String, dynamic> _$SubscriptionInfoToJson(SubscriptionInfo instance) =>
    <String, dynamic>{
      'upload': instance.upload,
      'download': instance.download,
      'total': instance.total,
      'expire': instance.expire,
    };
