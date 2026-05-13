// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClashConfig _$ClashConfigFromJson(Map<String, dynamic> json) => ClashConfig(
  mixedPort: (json['mixed-port'] as num?)?.toInt(),
  allowLan: json['allow-lan'] as bool?,
  mode: $enumDecodeNullable(_$ModeEnumMap, json['mode']),
  logLevel: $enumDecodeNullable(_$LogLevelEnumMap, json['log-level']),
  ipv6: json['ipv6'] as bool?,
  tun: json['tun'] == null
      ? null
      : TunConfig.fromJson(json['tun'] as Map<String, dynamic>),
  externalController: json['external-controller'] as bool?,
  externalControllerAddr: json['external-controller-addr'] as String?,
  portEnabled: json['port-enabled'] as bool?,
  mixedSystemProxy: json['mixed-system-proxy'] as bool?,
);

Map<String, dynamic> _$ClashConfigToJson(ClashConfig instance) =>
    <String, dynamic>{
      'mixed-port': instance.mixedPort,
      'allow-lan': instance.allowLan,
      'mode': _$ModeEnumMap[instance.mode],
      'log-level': _$LogLevelEnumMap[instance.logLevel],
      'ipv6': instance.ipv6,
      'tun': instance.tun,
      'external-controller': instance.externalController,
      'external-controller-addr': instance.externalControllerAddr,
      'port-enabled': instance.portEnabled,
      'mixed-system-proxy': instance.mixedSystemProxy,
    };

const _$ModeEnumMap = {
  Mode.rule: 'rule',
  Mode.global: 'global',
  Mode.direct: 'direct',
};

const _$LogLevelEnumMap = {
  LogLevel.debug: 'debug',
  LogLevel.info: 'info',
  LogLevel.warning: 'warning',
  LogLevel.error: 'error',
};

TunConfig _$TunConfigFromJson(Map<String, dynamic> json) =>
    TunConfig(enable: json['enable'] as bool?);

Map<String, dynamic> _$TunConfigToJson(TunConfig instance) => <String, dynamic>{
  'enable': instance.enable,
};
