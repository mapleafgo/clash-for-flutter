// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'net_speed.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NetSpeed _$NetSpeedFromJson(Map<String, dynamic> json) => NetSpeed(
      up: (json['up'] as num?)?.toInt() ?? 0,
      down: (json['down'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$NetSpeedToJson(NetSpeed instance) => <String, dynamic>{
      'up': instance.up,
      'down': instance.down,
    };
