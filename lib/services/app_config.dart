import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode, WidgetBuilder, Widget;
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:singcast/domain/enums.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:singcast/services/core_config.dart' show themeMode;
import 'package:singcast/services/subscription.dart';

final selectedFile = signal<String?>(null);
final profiles = signal<List<Profile>>([]);
final profileError = signal<String?>(null);
final delayTestUrl = signal(Defaults.delayTestUrl);
final tunIf = signal<bool?>(null);
final subUA = signal(Defaults.subUA);
final ruleSetProxy = signal(Defaults.ruleSetProxy);
final autoCheckUpdate = signal(true);
/// 开机自启动设置（仅桌面端有效）。
final autoStart = signal(false);
/// TUN 协议栈选择（仅桌面端 TUN 模式生效）。
final tunStack = signal(TunStack.gvisor);
/// 应用语言设置。null = 跟随系统。
final appLocale = signal<String?>(null);
/// 语言版本号，每次 locale 变化递增，用于触发全局 UI 重建。
final localeVersion = signal(0);

/// 自动追踪 [localeVersion] 的 SignalBuilder，用于显示 i18n 文本 (t.xxx) 的场景。
Widget l10nBuilder(WidgetBuilder builder) => SignalBuilder(
      dependencies: [localeVersion],
      builder: builder,
    );
final initError = signal<String?>(null);
final vpnConnected = signal(false);

Timer? _saveTimer;
Timer? _subUpdateTimer;

void initAppConfig() {
  final config = AppSettingsStorage.load();
  final stored = AppStoredConfig.fromJson(config);
  final validProfiles = _filterExistingProfiles(stored.profiles);
  profiles.value = validProfiles;
  selectedFile.value = _resolveSelected(stored.selectedFile, validProfiles);
  delayTestUrl.value = stored.delayTestUrl;
  tunIf.value = stored.tunIf ?? !Constants.isDesktop;
  subUA.value = stored.subUA;
  autoCheckUpdate.value = stored.autoCheckUpdate;
  autoStart.value = stored.autoStart;
  tunStack.value = stored.tunStack;
  if (stored.themeMode != null) {
    final mode = _parseThemeMode(stored.themeMode!);
    if (mode != null) themeMode.value = mode;
  }
  if (stored.locale != null) {
    appLocale.value = stored.locale;
    LocaleSettings.setLocaleRaw(stored.locale!);
  }
  _startAutoSave();

  // locale 变化时递增 localeVersion，驱动全局 UI 重建
  appLocale.subscribe((_) {
    localeVersion.value++;
    // 通知 Android 重建通知栏文本（iOS 无前台服务通知栏，不调用）
    if (Platform.isAndroid) {
      const MethodChannel(Constants.methodChannelName)
          .invokeMethod('updateNotification', {'locale': appLocale.value});
    }
  });
}

ThemeMode? _parseThemeMode(String name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
      return ThemeMode.system;
    default:
      return null;
  }
}

List<Profile> _filterExistingProfiles(List<Profile> list) {
  final dir = Directory(p.join(Constants.homeDir.path, Constants.profilesDir));
  if (!dir.existsSync()) return [];
  final files = dir.listSync().map((e) => p.basename(e.path)).toSet();
  return list.where((e) => files.contains(e.file)).toList();
}

String? _resolveSelected(String? file, List<Profile> list) {
  if (file != null && list.any((e) => e.file == file)) return file;
  return list.isEmpty ? null : list.first.file;
}

void _startAutoSave() {
  effect(() {
    selectedFile.value;
    profiles.value;
    delayTestUrl.value;
    tunIf.value;
    subUA.value;
    themeMode.value;
    autoCheckUpdate.value;
    autoStart.value;
    appLocale.value;
    tunStack.value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  });
  _startSubUpdateTimer();
}

void _save() {
  // ignored-version 不在内存 signal 里，保存前先从磁盘取回：
  // 否则这次整份覆盖写会把用户点的"忽略此版本"抹掉，导致每次启动都弹更新框。
  final stored = AppStoredConfig.fromJson(AppSettingsStorage.load());
  AppSettingsStorage.save(AppStoredConfig(
    ignoredVersion: stored.ignoredVersion,
    selectedFile: selectedFile.value,
    profiles: profiles.value,
    delayTestUrl: delayTestUrl.value,
    tunIf: tunIf.value,
    subUA: subUA.value,
    themeMode: themeMode.value?.name,
    autoCheckUpdate: autoCheckUpdate.value,
    autoStart: autoStart.value,
    locale: appLocale.value,
    tunStack: tunStack.value,
  ).toJson());
}

void _startSubUpdateTimer() {
  _subUpdateTimer?.cancel();
  _subUpdateTimer = Timer.periodic(const Duration(hours: 1), (_) => checkSubUpdates());
}

Future<void> checkSubUpdates() async {
  final now = DateTime.now();
  final expired = profiles.value.where(
    (e) => e.type == ProfileType.url && e.url != null && e.interval > 0
        && now.isAfter(e.time.add(Duration(hours: e.interval))),
  ).toList();
  for (final profile in expired) {
    try {
      await refreshProfile(profile);
      LogFileWriter.instance?.log(
        '自动更新订阅成功: ${profile.name}',
        level: LogLevel.info,
        name: 'sub-update',
      );
    } catch (e) {
      LogFileWriter.instance?.log(
        '自动更新订阅失败: $e',
        level: LogLevel.warning,
        name: 'sub-update',
      );
    }
  }
}

/// 下载订阅并替换旧 profile。校验失败时抛出异常。
Future<Profile> refreshProfile(Profile old) async {
  final dir = p.join(Constants.homeDir.path, Constants.profilesDir);
  final updated = await downloadSubscription(
    url: old.url!,
    profilesDir: dir,
    name: old.name,
    interval: old.interval,
  );
  final path = p.join(dir, updated.file);
  await validateConfigFile(path);

  final isActive = selectedFile.value == old.file;
  final idx = profiles.value.indexWhere((e) => e.file == old.file);
  if (idx < 0) return updated; // profile 已被删除，不追加
  profiles.value = [...profiles.value]..[idx] = updated;
  if (isActive) selectedFile.value = updated.file;

  final oldPath = p.join(dir, old.file);
  if (File(oldPath).existsSync()) {
    await File(oldPath).delete();
  }
  return updated;
}


String get profilesFullPath =>
    p.join(Constants.homeDir.path, Constants.profilesDir);

/// 立即落盘待保存的设置，取消 1s 防抖定时器。
///
/// 退出前必须调用：否则最近一次改动（切换订阅、主题、语言等）会随进程一起丢失。
void flushAppConfig() {
  _saveTimer?.cancel();
  _saveTimer = null;
  _save();
}
