import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';

const _sentinel = Object();

class AppSettingsStorage {
  static File get _file =>
      File(p.join(Constants.homeDir.path, Constants.appSettings));

  static Map<String, dynamic> load() {
    _migrateFromCfm();
    if (!_file.existsSync()) return {};
    try {
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      LogFileWriter.instance?.log(
        'Failed to load settings: $e',
        level: LogLevel.warning,
        name: 'settings',
      );
      // 保留损坏文件供手动恢复：settings.json 存有全部订阅列表，
      // 直接丢弃等于静默清空用户数据。
      try {
        _file.renameSync('${_file.path}.bak');
      } catch (_) {}
      return {};
    }
  }

  static void save(Map<String, dynamic> settings) {
    // 先写临时文件再 rename 原子替换，避免写入中途崩溃产生半截 JSON。
    final tmp = File('${_file.path}.tmp');
    tmp.createSync(recursive: true);
    tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(settings));
    tmp.renameSync(_file.path);
  }

  /// 一次性迁移 cfm.json → settings.json，迁移后删除旧文件。
  static void _migrateFromCfm() {
    final cfm = File(p.join(Constants.homeDir.path, 'cfm.json'));
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
  final String? locale;
  final bool autoStart;
  final TunStack tunStack;
  final String ruleSetProxy;

  AppStoredConfig({
    this.selectedFile,
    required this.profiles,
    required this.delayTestUrl,
    this.tunIf,
    String? subUA,
    this.themeMode,
    this.ignoredVersion,
    this.autoCheckUpdate = true,
    this.locale,
    this.autoStart = false,
    this.tunStack = TunStack.mixed,
    String? ruleSetProxy,
  }) : subUA = subUA ?? Defaults.subUA,
       ruleSetProxy = ruleSetProxy ?? Defaults.ruleSetProxy;

  factory AppStoredConfig.fromJson(Map<String, dynamic> json) =>
      AppStoredConfig(
        selectedFile: json['selected-file'] as String?,
        profiles:
            (json['profiles'] as List?)
                ?.map((e) => Profile.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        delayTestUrl:
            json['delay-test-url'] as String? ?? Defaults.delayTestUrl,
        tunIf: json['tun-if'] as bool?,
        subUA: json['sub-ua'] as String? ?? Defaults.subUA,
        themeMode: json['theme-mode'] as String?,
        ignoredVersion: json['ignored-version'] as String?,
        autoCheckUpdate: json['auto-check-update'] as bool? ?? true,
        locale: json['locale'] as String?,
        autoStart: json['auto-start'] as bool? ?? false,
        tunStack: _parseTunStack(json['tun-stack'] as String?),
        ruleSetProxy: json['rule-set-proxy'] as String?,
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
    if (locale != null) 'locale': locale,
    if (autoStart) 'auto-start': autoStart,
    if (tunStack != TunStack.mixed) 'tun-stack': tunStack.name,
    if (ruleSetProxy != Defaults.ruleSetProxy) 'rule-set-proxy': ruleSetProxy,
  };

  factory AppStoredConfig.empty() =>
      AppStoredConfig(profiles: [], delayTestUrl: Defaults.delayTestUrl);

  AppStoredConfig copyWith({
    String? selectedFile,
    List<Profile>? profiles,
    String? delayTestUrl,
    bool? tunIf,
    String? subUA,
    String? themeMode,
    Object? ignoredVersion = _sentinel,
    bool? autoCheckUpdate,
    String? locale,
    bool? autoStart,
    TunStack? tunStack,
    String? ruleSetProxy,
  }) => AppStoredConfig(
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
    locale: locale ?? this.locale,
    autoStart: autoStart ?? this.autoStart,
    tunStack: tunStack ?? this.tunStack,
    ruleSetProxy: ruleSetProxy ?? this.ruleSetProxy,
  );
}

/// 解析持久化的 tun-stack 字符串，未知值回退到默认 [TunStack.mixed]。
TunStack _parseTunStack(String? value) {
  if (value == null) return TunStack.mixed;
  return TunStack.values.firstWhere(
    (e) => e.name == value,
    orElse: () => TunStack.mixed,
  );
}
