import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'log.g.dart';

@JsonSerializable()
class LogEntry {
  final LogLevel type;
  final String payload;

  LogEntry({required this.type, required this.payload});

  factory LogEntry.fromJson(Map<String, dynamic> json) =>
      _$LogEntryFromJson(json);
  Map<String, dynamic> toJson() => _$LogEntryToJson(this);
}