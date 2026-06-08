import 'dart:convert';
import 'dart:io';

import 'package:singcast/domain/profile.dart';
import 'package:singcast/utils/constants.dart';

const _sentinel = Object();

class AppSettingsStorage {
  static File get _file => File('${Constants.homeDir.path}${Constants.appSettings}');

  static Map<String, dynamic> load() {
    _migrateFromCfm();
    if (!_file.existsSync()) return {};
    try {
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static void save(Map<String, dynamic> settings) {
    _file.createSync(recursive: true);
    _file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  static Future<void> saveAsync(Map<String, dynamic> settings) async {
    await _file.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  /// 一次性迁移 cfm.json → settings.json，迁移后删除旧文件。
  static void _migrateFromCfm() {
    final cfm = File('${Constants.homeDir.path}/cfm.json');
    if (!cfm.existsSync()) return;
    if (_file.existsSync()) {
      // settings.json 已存在，直接删除旧文件
      cfm.deleteSync();
      return;
    }
    try {
      final old = jsonDecode(cfm.readAsStringSync()) as Map<String, dynamic>;
      save(old);
      cfm.deleteSync();
    } catch (_) {
      // 迁移失败不影响启动
    }
  }
}

class AppStoredConfig {
  final String? selectedFile;
  final List<Profile> profiles;
  final String delayTestUrl;
  final bool? tunIf;
  final String subUA;
  final String? themeMode;
  final String? ignoredVersion;
  final bool autoCheckUpdate;

  AppStoredConfig({
    this.selectedFile,
    required this.profiles,
    required this.delayTestUrl,
    this.tunIf,
    String? subUA,
    this.themeMode,
    this.ignoredVersion,
    this.autoCheckUpdate = true,
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
        themeMode: json['theme-mode'] as String?,
        ignoredVersion: json['ignored-version'] as String?,
        autoCheckUpdate: json['auto-check-update'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'selected-file': selectedFile,
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'delay-test-url': delayTestUrl,
        'tun-if': tunIf,
        if (subUA != Defaults.subUA) 'sub-ua': subUA,
        if (themeMode != null) 'theme-mode': themeMode,
        if (ignoredVersion != null) 'ignored-version': ignoredVersion,
        if (!autoCheckUpdate) 'auto-check-update': autoCheckUpdate,
      };

  factory AppStoredConfig.empty() => AppStoredConfig(
        profiles: [],
        delayTestUrl: Defaults.delayTestUrl,
      );

  AppStoredConfig copyWith({
    String? selectedFile,
    List<Profile>? profiles,
    String? delayTestUrl,
    bool? tunIf,
    String? subUA,
    String? themeMode,
    Object? ignoredVersion = _sentinel,
    bool? autoCheckUpdate,
  }) =>
      AppStoredConfig(
        selectedFile: selectedFile ?? this.selectedFile,
        profiles: profiles ?? this.profiles,
        delayTestUrl: delayTestUrl ?? this.delayTestUrl,
        tunIf: tunIf ?? this.tunIf,
        subUA: subUA ?? this.subUA,
        themeMode: themeMode ?? this.themeMode,
        ignoredVersion: ignoredVersion == _sentinel
            ? this.ignoredVersion
            : ignoredVersion as String?,
        autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      );
}
