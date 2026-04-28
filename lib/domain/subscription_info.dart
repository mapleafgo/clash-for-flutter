import 'package:json_annotation/json_annotation.dart';

part 'subscription_info.g.dart';

@JsonSerializable()
class SubscriptionInfo {
  final int? upload;
  final int? download;
  final int? total;
  final int? expire;

  SubscriptionInfo({this.upload, this.download, this.total, this.expire});

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionInfoFromJson(json);
  Map<String, dynamic> toJson() => _$SubscriptionInfoToJson(this);

  factory SubscriptionInfo.fromHeader(String info) {
    final map = <String, int?>{};
    for (final part in info.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2) map[kv[0].trim()] = int.tryParse(kv[1].trim());
    }
    return SubscriptionInfo(
      upload: map['upload'],
      download: map['download'],
      total: map['total'],
      expire: map['expire'],
    );
  }

  int get used => (upload ?? 0) + (download ?? 0);
}