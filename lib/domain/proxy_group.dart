import 'package:json_annotation/json_annotation.dart';

part 'proxy_group.g.dart';

@JsonSerializable()
class ProxyGroup {
  final String name;
  final String type;
  final List<String> all;
  final String now;

  ProxyGroup({
    required this.name,
    required this.type,
    required this.all,
    required this.now,
  });

  factory ProxyGroup.fromJson(Map<String, dynamic> json) =>
      _$ProxyGroupFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyGroupToJson(this);
}