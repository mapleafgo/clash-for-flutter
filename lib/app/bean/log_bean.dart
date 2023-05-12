import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class LogData {
  DateTime? time;
  LogLevel type;
  String payload;

  LogData({
    this.time,
    required this.type,
    required this.payload,
  });
}
