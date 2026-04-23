import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';
import 'subscription_info.dart';

part 'profile.g.dart';

@JsonSerializable()
class Profile {
  final String file;
  final String name;
  final ProfileType type;
  final DateTime time;
  final String? url;
  final int interval;
  final SubscriptionInfo? userinfo;

  Profile({
    required this.file,
    required this.name,
    required this.type,
    required this.time,
    this.url,
    this.interval = 0,
    this.userinfo,
  });

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
  Map<String, dynamic> toJson() => _$ProfileToJson(this);
}