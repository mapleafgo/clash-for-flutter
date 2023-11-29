import 'package:dart_json_mapper/dart_json_mapper.dart';

@JsonSerializable()
class Tun {
  bool? enable;
  String? device;
  String? stack;
  @JsonProperty(name: "include-android-user")
  String? includeAndroidUser;
  @JsonProperty(name: "include-package")
  List<String>? includePackage;
  @JsonProperty(name: "exclude-package")
  List<String>? excludePackage;

  Tun({
    this.enable,
    this.device,
    this.stack,
    this.includeAndroidUser,
    this.includePackage,
    this.excludePackage,
  });
}
