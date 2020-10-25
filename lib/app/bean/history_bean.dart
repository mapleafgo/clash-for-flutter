import 'package:json_annotation/json_annotation.dart';

part 'history_bean.g.dart';

@JsonSerializable()
class History {
  String time;
  int delay;

  History({this.time, this.delay});

  factory History.fromJson(Map<String, dynamic> json) =>
      _$HistoryFromJson(json);
  Map<String, dynamic> toJson() => _$HistoryToJson(this);
}
