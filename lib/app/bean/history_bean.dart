import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class History {
  String time;
  int delay;

  History({required this.time, required this.delay});
}
