import 'package:dart_json_mapper/dart_json_mapper.dart';

const customEnumConverter = ConstCustomEnumConverter();

class ConstCustomEnumConverter
    implements ICustomConverter, ICustomEnumConverter {
  const ConstCustomEnumConverter();

  @override
  void setEnumValues(Iterable<dynamic> enumValues) {
    _customEnumConverter.setEnumValues(enumValues);
  }

  @override
  fromJSON(jsonValue, [JsonProperty jsonProperty]) {
    return _customEnumConverter.fromJSON(jsonValue, jsonProperty);
  }

  @override
  toJSON(object, [JsonProperty jsonProperty]) {
    return _customEnumConverter.toJSON(object, jsonProperty);
  }
}

final _customEnumConverter = CustomEnumConverter();

class CustomEnumConverter implements ICustomConverter, ICustomEnumConverter {
  CustomEnumConverter() : super();

  var _enumValues = [];

  @override
  void setEnumValues(Iterable<dynamic> enumValues) {
    _enumValues = enumValues;
  }

  @override
  fromJSON(jsonValue, [JsonProperty jsonProperty]) {
    return _enumValues.first.toObject(jsonValue);
  }

  @override
  toJSON(object, [JsonProperty jsonProperty]) {
    return object.value;
  }
}

/// 代理类型
@jsonSerializable
enum ProxieType { Direct, Reject, Shadowsocks, Vmess, Socks, Http, Snell }

extension ProxieTypeExtension on ProxieType {
  static const stringList = [
    "Direct",
    "Reject",
    "Shadowsocks",
    "Vmess",
    "Socks",
    "Http",
    "Snell",
  ];
  ProxieType toObject(String value) =>
      ProxieType.values[stringList.indexWhere((e) => e == value)];
  String get value => stringList[this.index];
}

/// 分组类型
@jsonSerializable
enum GroupType { Selector, URLTest, Fallback, LoadBalance }

extension GroupTypeExtension on GroupType {
  static const stringList = [
    "Selector",
    "URLTest",
    "Fallback",
    "LoadBalance",
  ];
  GroupType toObject(String value) =>
      GroupType.values[stringList.indexWhere((e) => e == value)];
  String get value => stringList[this.index];
}

@jsonSerializable
enum VehicleType { HTTP, File, Compatible }

extension VehicleTypeExtension on VehicleType {
  static const stringList = [
    "HTTP",
    "File",
    "Compatible",
  ];
  VehicleType toObject(String value) =>
      VehicleType.values[stringList.indexWhere((e) => e == value)];
  String get value => stringList[this.index];
}

/// 使用的选择代理
@jsonSerializable
enum UsedProxy { DIRECT, REJECT, GLOBAL }

extension UsedProxyExtension on UsedProxy {
  static const stringList = [
    "DIRECT",
    "REJECT",
    "GLOBAL",
  ];
  UsedProxy toObject(String value) =>
      UsedProxy.values[stringList.indexWhere((e) => e == value)];
  String get value => stringList[this.index];
}

@jsonSerializable
enum Mode { Rule, Global, Direct }

extension ModeExtension on Mode {
  static const stringList = [
    "Rule",
    "Global",
    "Direct",
  ];
  Mode toObject(String value) =>
      Mode.values[stringList.indexWhere((e) => e == value)];
  String get value => stringList[this.index];
}
