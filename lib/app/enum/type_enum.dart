import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 分组类型
@jsonSerializable
enum GroupType { Selector, URLTest, Fallback, LoadBalance }

extension GroupTypeValue on GroupType {
  static List<String> get valueList =>
      GroupType.values.map((e) => e.toString().split("\.").last).toList();

  String get value => GroupTypeValue.valueList[this.index];
}

@jsonSerializable
enum VehicleType { HTTP, File, Compatible }

extension VehicleTypeValue on VehicleType {
  static List<String> get valueList =>
      VehicleType.values.map((e) => e.toString().split("\.").last).toList();

  String get value => VehicleTypeValue.valueList[this.index];
}

/// 使用的选择代理
@jsonSerializable
enum UsedProxy { DIRECT, REJECT, GLOBAL }

extension UsedProxyValue on UsedProxy {
  static List<String> get valueList =>
      UsedProxy.values.map((e) => e.toString().split("\.").last).toList();

  String get value => UsedProxyValue.valueList[this.index];
}

@jsonSerializable
enum Mode { Rule, Global, Direct }

extension ModeValue on Mode {
  static List<String> get valueList =>
      Mode.values.map((e) => e.toString().split("\.").last).toList();

  String get value => ModeValue.valueList[this.index];
}

enum DataUnit { Byte, KB, MB, GB }

extension DataUnitValue on DataUnit {
  static List<String> get valueList =>
      DataUnit.values.map((e) => e.toString().split("\.").last).toList();

  String get value => DataUnitValue.valueList[this.index];
}

/// 排序类型
enum SortType { Default, Name, Delay }

extension SortTypeShowName on SortType {
  static List<String> get showNameList => ["默认", "名称", "延迟"];
  String get showName => SortTypeShowName.showNameList[this.index];
}
