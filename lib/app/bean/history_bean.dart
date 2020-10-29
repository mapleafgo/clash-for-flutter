import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class History {
  String time;
  int delay;

  History({this.time, this.delay});
}
