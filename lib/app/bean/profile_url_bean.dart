import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/sub_userinfo_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 配置(URL)
@JsonSerializable()
@Json(discriminatorValue: ProfileType.URL)
class ProfileURL extends ProfileBase {
  /// 链接地址
  String url;

  /// 更新间隔(h)
  int interval;

  @JsonProperty(name: "sub-userinfo")
  SubUserinfo? userinfo;

  ProfileURL({
    required super.file,
    required super.name,
    required super.time,
    required this.url,
    required this.interval,
    this.userinfo,
  }) : super(type: ProfileType.URL);

  factory ProfileURL.defaultBean({
    required String url,
    required String file,
    required String name,
    required DateTime time,
  }) =>
      ProfileURL(url: url, file: file, name: name, time: time, interval: 0);

  factory ProfileURL.emptyBean() => ProfileURL(
      url: "", file: "", name: "", time: DateTime.now(), interval: 0);
}
