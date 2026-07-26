import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/utils/constants.dart';

/// 检查是否有新版本可用。
///
/// 使用语义化版本比较（pub_semver），比字符串比较更精确：
/// - `1.2.0` < `1.2.1` ✓
/// - `1.2.0` < `1.10.0` ✓（字符串比较会误判）
/// - `1.2.3-beta.1` < `1.2.3` ✓（预发布版低于正式版）
///
/// 返回 `null` 表示已是最新版本。
/// 返回版本号字符串表示有新版本。
/// 网络错误或解析失败时抛出异常，调用者可据此显示错误状态。
Future<String?> checkForUpdate() async {
  final current = Defaults.appVersion;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(Constants.releaseUrl));
    final resp = await req.close();
    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode}');
    }
    final body = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(body) as Map<String, dynamic>;
    final tag = data['tag_name'] as String? ?? '';
    // 只去掉前缀 v：replaceFirst 会误删任意位置的首个 v（如 1.2.0-dev）
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (latest.isEmpty) return null;
    final latestVersion = Version.parse(latest);
    final currentVersion = Version.parse(current);
    return (latestVersion > currentVersion) ? latest : null;
  } finally {
    client.close();
  }
}

/// 是否已忽略指定版本。
bool isVersionIgnored(String version) {
  final config = AppSettingsStorage.load();
  return AppStoredConfig.fromJson(config).ignoredVersion == version;
}

/// 持久化忽略的版本号。
void ignoreVersion(String version) {
  final config = AppSettingsStorage.load();
  final stored = AppStoredConfig.fromJson(config);
  AppSettingsStorage.save(
    stored.copyWith(ignoredVersion: version).toJson(),
  );
}

/// 清除已忽略的版本号（发现新版本时调用）。
void clearIgnoredVersion() {
  final config = AppSettingsStorage.load();
  final stored = AppStoredConfig.fromJson(config);
  if (stored.ignoredVersion == null) return;
  AppSettingsStorage.save(
    stored.copyWith(ignoredVersion: null).toJson(),
  );
}
