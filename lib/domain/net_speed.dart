import 'package:json_annotation/json_annotation.dart';

part 'net_speed.g.dart';

@JsonSerializable()
class NetSpeed {
  final int up;
  final int down;
  NetSpeed({this.up = 0, this.down = 0});
  factory NetSpeed.fromJson(Map<String, dynamic> json) =>
      _$NetSpeedFromJson(json);
  Map<String, dynamic> toJson() => _$NetSpeedToJson(this);
}