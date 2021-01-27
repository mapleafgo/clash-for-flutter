import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class NetSpeed {
  int up;
  int down;

  @override
  String toString() {
    return "$up $down";
  }
}
