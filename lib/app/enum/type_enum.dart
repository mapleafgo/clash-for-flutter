import 'package:dart_json_mapper/dart_json_mapper.dart';

class Name implements ICustomConverter, ICustomEnumConverter {
  Name() : super();

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
  static ProxieType toObject(String value) =>
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
  static GroupType toObject(int i) => GroupType.values[i];
  String get value => stringList[this.index];
}

@jsonSerializable
enum VehicleType { HTTP, File, Compatible }

extension VehicleTypeExtension on GroupType {
  static const stringList = [
    "HTTP",
    "File",
    "Compatible",
  ];
  static VehicleType toObject(int i) => VehicleType.values[i];
  String get value => stringList[this.index];
}

/// 使用的选择代理
@jsonSerializable
enum UsedProxy { DIRECT, REJECT, GLOBAL }

extension UsedProxyExtension on GroupType {
  static const stringList = [
    "DIRECT",
    "REJECT",
    "GLOBAL",
  ];
  static UsedProxy toObject(int i) => UsedProxy.values[i];
  String get value => stringList[this.index];
}

@jsonSerializable
enum Mode { Rule, Global, Direct }

extension ModeExtension on GroupType {
  static const stringList = [
    "Rule",
    "Global",
    "Direct",
  ];
  static Mode toObject(int i) => Mode.values[i];
  String get value => stringList[this.index];
}
