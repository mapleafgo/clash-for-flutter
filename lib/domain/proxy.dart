import 'package:json_annotation/json_annotation.dart';

part 'proxy.g.dart';

@JsonSerializable()
class Proxy {
  final String name;
  final String? type;
  final List<ProxyHistory>? history;

  Proxy({required this.name, this.type, this.history});

  factory Proxy.fromJson(Map<String, dynamic> json) => _$ProxyFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyToJson(this);
}

@JsonSerializable()
class ProxyHistory {
  final String time;
  final int delay;
  ProxyHistory({required this.time, required this.delay});
  factory ProxyHistory.fromJson(Map<String, dynamic> json) =>
      _$ProxyHistoryFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyHistoryToJson(this);
}