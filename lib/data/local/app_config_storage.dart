import 'dart:convert';
import 'dart:io';

import 'package:clash_for_flutter/domain/profile.dart';
import 'package:clash_for_flutter/utils/constants.dart';

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
  final String mmdbUrl;
  final String delayTestUrl;
  final bool? tunIf;

  AppStoredConfig({
    this.selectedFile,
    required this.profiles,
    required this.mmdbUrl,
    required this.delayTestUrl,
    this.tunIf,
  });

  factory AppStoredConfig.fromJson(Map<String, dynamic> json) =>
      AppStoredConfig(
        selectedFile: json['selected-file'] as String?,
        profiles: (json['profiles'] as List?)
                ?.map((e) => Profile.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        mmdbUrl: json['mmdb-url'] as String? ?? Defaults.mmdbUrl,
        delayTestUrl: json['delay-test-url'] as String? ?? Defaults.delayTestUrl,
        tunIf: json['tun-if'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'selected-file': selectedFile,
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'mmdb-url': mmdbUrl,
        'delay-test-url': delayTestUrl,
        'tun-if': tunIf,
      };

  factory AppStoredConfig.empty() => AppStoredConfig(
        profiles: [],
        mmdbUrl: Defaults.mmdbUrl,
        delayTestUrl: Defaults.delayTestUrl,
      );
}