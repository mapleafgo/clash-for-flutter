import 'package:dart_json_mapper/dart_json_mapper.dart';

/// 订阅信息
@JsonSerializable()
class SubUserinfo {
  int? upload;
  int? download;
  int? total;
  int? expire;

  SubUserinfo({
    this.upload,
    this.download,
    this.total,
    this.expire,
  });

  factory SubUserinfo.formHString(String info) {
    var list = info.split(";");
    Map<String, int?> map = {};
    for (var i in list) {
      var j = i.trim().split("=");
      map[j[0]] = int.tryParse(j[1]);
    }
    return SubUserinfo(
      upload: map["upload"],
      download: map["download"],
      total: map["total"],
      expire: map["expire"],
    );
  }
}
