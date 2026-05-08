import 'dart:convert';
import 'dart:io';

import 'package:singcast/domain/profile.dart';
import 'package:singcast/utils/constants.dart';

class AppConfigStorage {
  static final _file =
      File('${Constants.homeDir.path}${Constants.clashForMe}');

  static AppStoredConfig load() {
    if (!_file.existsSync()) return AppStoredConfig.empty();
    final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    return AppStoredConfig.fromJson(json);
  }

  static void save(AppStoredConfig config) {
    _file.createSync(recursive: true);
    _file.writeAsStringSync(jsonEncode(config.toJson()));
  }
}

class AppStoredConfig {
  final String? selectedFile;
  final List<Profile> profiles;
  final String delayTestUrl;
  final bool? tunIf;
  final String subUA;

  AppStoredConfig({
    this.selectedFile,
    required this.profiles,
    required this.delayTestUrl,
    this.tunIf,
    String? subUA,
  }) : subUA = subUA ?? Defaults.subUA;

  factory AppStoredConfig.fromJson(Map<String, dynamic> json) =>
      AppStoredConfig(
        selectedFile: json['selected-file'] as String?,
        profiles: (json['profiles'] as List?)
                ?.map((e) => Profile.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        delayTestUrl: json['delay-test-url'] as String? ?? Defaults.delayTestUrl,
        tunIf: json['tun-if'] as bool?,
        subUA: json['sub-ua'] as String? ?? Defaults.subUA,
      );

  Map<String, dynamic> toJson() => {
        'selected-file': selectedFile,
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'delay-test-url': delayTestUrl,
        'tun-if': tunIf,
        // UA 为默认时不持久化，加载时直接用即时版本常量
        if (subUA != Defaults.subUA) 'sub-ua': subUA,
      };

  factory AppStoredConfig.empty() => AppStoredConfig(
        profiles: [],
        delayTestUrl: Defaults.delayTestUrl,
      );
}
