import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:singcast/presentation/router.dart' show Routes, navigatorKey, router;
import 'package:singcast/services/subscription.dart';
import 'package:singcast/utils/log_file.dart';

final _appLinks = AppLinks();

void initDeepLinks() {
  // 冷启动时处理初始链接
  _appLinks.getInitialLink().then((initial) {
    _log('[deeplink] initialLink: $initial');
    if (initial != null) _processDeepLink(initial);
  });

  // 热启动时监听后续链接
  _appLinks.uriLinkStream.listen(
    _processDeepLink,
    onError: (e) => _log('[deeplink] stream error: $e'),
  );
}

Future<void> _processDeepLink(Uri uri) async {
  _log('[deeplink] received: $uri');
  if (uri.scheme != 'clash') return;

  final url = uri.queryParameters['url'];
  _log('[deeplink] host=${uri.host}, url=$url');
  if (!const {'install-sub', 'install-config'}.contains(uri.host)) return;
  if (url == null || url.isEmpty) return;

  // 等待路由就绪后再弹窗
  await WidgetsBinding.instance.endOfFrame;
  final navContext = navigatorKey.currentContext;
  if (navContext == null || !navContext.mounted) {
    _log('[deeplink] no navigator context for dialog');
    return;
  }

  final name = uri.queryParameters['name'];
  final label = name != null ? '「$name」' : '';
  final confirmed = await showDialog<bool>(
    context: navContext,
    builder: (ctx) => AlertDialog(
      title: const Text('导入订阅'),
      content: Text('是否导入订阅$label？', softWrap: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('导入'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await importSubscription(url, name: name);
    _log('[deeplink] imported subscription from: $url');
    router.go(Routes.profiles);
    if (navContext.mounted) {
      ScaffoldMessenger.of(navContext).clearSnackBars();
      ScaffoldMessenger.of(navContext).showSnackBar(
        const SnackBar(content: Text('订阅导入成功')),
      );
    }
  } catch (e) {
    _log('[deeplink] import failed: $e');
    if (navContext.mounted) {
      ScaffoldMessenger.of(navContext).clearSnackBars();
      ScaffoldMessenger.of(navContext).showSnackBar(
        SnackBar(content: Text('订阅导入失败: $e')),
      );
    }
  }
}

void _log(String msg) {
  LogFileWriter.instance?.log(msg, name: 'deeplink');
}
