import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 分组类型
@jsonSerializable
enum GroupType { Selector, URLTest, Fallback, LoadBalance }

extension GroupTypeValue on GroupType {
  static List<String> get valueList => GroupType.values.map((e) => e.toString().split(".").last).toList();

  String get value => GroupTypeValue.valueList[index];
}

@jsonSerializable
enum VehicleType { HTTP, File, Compatible }

extension VehicleTypeValue on VehicleType {
  static List<String> get valueList => VehicleType.values.map((e) => e.toString().split(".").last).toList();

  String get value => VehicleTypeValue.valueList[index];
}

/// 使用的选择代理
@jsonSerializable
enum UsedProxy { DIRECT, REJECT, GLOBAL }

extension UsedProxyValue on UsedProxy {
  static List<String> get valueList => UsedProxy.values.map((e) => e.toString().split(".").last).toList();

  String get value => UsedProxyValue.valueList[index];
}

@jsonSerializable
enum Mode { Rule, Global, Direct }

extension ModeValue on Mode {
  static List<String> get valueList => Mode.values.map((e) => e.toString().split(".").last).toList();

  String get value => ModeValue.valueList[index];
}

enum DataUnit { Byte, KB, MB, GB, TB, PB }

extension DataUnitValue on DataUnit {
  static List<String> get valueList => DataUnit.values.map((e) => e.toString().split(".").last).toList();

  String get value => DataUnitValue.valueList[index];
}

/// 排序类型
enum SortType { Default, Name, Delay }

extension SortTypeShowName on SortType {
  static List<String> get showNameList => ["默认", "名称", "延迟"];

  String get showName => SortTypeShowName.showNameList[index];
}

/// 配置类型
@jsonSerializable
enum ProfileType { URL, FILE }

extension ProfileTypeValue on ProfileType {
  static List<String> get valueList => ProfileType.values.map((e) => e.toString().split(".").last).toList();

  String get value => ProfileTypeValue.valueList[index];
}

/// 日志等级
@jsonSerializable
enum LogLevel { debug, info, warning, error, silent }

extension LogLevelValue on LogLevel {
  static List<String> get valueList => LogLevel.values.map((e) => e.toString().split(".").last).toList();

  String get value => LogLevelValue.valueList[index];
}
