import 'package:flutter/material.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/presentation/router.dart' show navigatorKey;
import 'package:singcast/services/app_config.dart'
    show checkSubUpdates, autoCheckUpdate;
import 'package:singcast/utils/constants.dart';
import 'package:singcast/domain/enums.dart' show LogLevel;
import 'package:singcast/utils/log_file.dart';
import 'package:singcast/utils/update_checker.dart';
import 'package:url_launcher/url_launcher.dart';

/// 启动后串行执行所有一次性检查任务。
Future<void> runStartupChecks() async {
  // 1. 检查订阅更新
  try {
    await checkSubUpdates();
  } catch (e) {
    LogFileWriter.instance?.log(
      '启动检查订阅更新失败: $e',
      level: LogLevel.warning,
      name: 'startup-checks',
    );
  }

  // 2. 检查应用版本
  if (autoCheckUpdate.value) {
    try {
      final latest = await checkForUpdate();
      if (latest == null) return;
      if (isVersionIgnored(latest)) return;
      clearIgnoredVersion();
      _showUpdateDialog(latest);
    } catch (_) {
      // 启动检查静默失败，不打扰用户
    }
  }
}

void _showUpdateDialog(String latest) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.startup.newVersionFound),
      content: Text(
        t.startup.currentAndLatest(
          current: Defaults.appVersion,
          latest: latest,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ignoreVersion(latest);
            Navigator.pop(ctx);
          },
          child: Text(t.startup.ignoreThisVersion),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t.startup.remindLater),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse('${Constants.sourceUrl}/releases/latest'));
          },
          child: Text(t.startup.goDownload),
        ),
      ],
    ),
  );
}
