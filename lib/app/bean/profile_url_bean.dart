import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
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

  ProfileURL({
    required String file,
    required String name,
    required DateTime time,
    required this.url,
    required this.interval,
  }) : super(name: name, file: file, type: ProfileType.URL, time: time);

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
