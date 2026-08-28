import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/presentation/router.dart'
    show Routes, navigatorKey, router;
import 'package:singcast/services/subscription.dart';
import 'package:singcast/utils/log_file.dart';

const _deepLinkScheme = 'clash';
final _appLinks = AppLinks();

void initDeepLinks() {
  // 延迟订阅 uriLinkStream：冷启动时 getInitialLink 和 stream 可能同时投递同一链接，
  // 先处理完 initialLink 再订阅，从结构上保证只触发一次
  _appLinks
      .getInitialLink()
      .then((initial) {
        _log('[deeplink] initialLink: $initial');
        if (initial != null) {
          _processDeepLink(initial).catchError((e) {
            _log('[deeplink] initialLink processing failed: $e');
          });
        }
      })
      .catchError((e) {
        // getInitialLink 抛异常（如平台通道未就绪）不能吃掉后面的订阅，
        // 否则本次运行期间所有深链都会静默丢弃。
        _log('[deeplink] getInitialLink failed: $e');
      })
      .whenComplete(() {
        _appLinks.uriLinkStream.listen(
          _processDeepLink,
          onError: (e) => _log('[deeplink] stream error: $e'),
        );
      });
}

/// 正在处理深链：串行化，避免叠加对话框与重复导入。
bool _handling = false;

Future<void> _processDeepLink(Uri uri) async {
  _log('[deeplink] received: $uri');
  if (uri.scheme != _deepLinkScheme) return;
  // 连点两次订阅链接时，两个流程会在对方 importSubscription 完成前
  // 都通过去重检查，导致同一订阅被导入两份。
  if (_handling) {
    _log('[deeplink] another link is being handled, ignoring: $uri');
    return;
  }
  _handling = true;
  try {
    await _handleDeepLink(uri);
  } finally {
    _handling = false;
  }
}

Future<void> _handleDeepLink(Uri uri) async {
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
  final confirmed = await showDialog<bool>(
    context: navContext,
    builder: (ctx) => AlertDialog(
      title: Text(t.deepLink.importSubscription),
      content: Text(
        name != null
            ? t.deepLink.confirmImport(name: name)
            : t.deepLink.confirmImportNoName,
        softWrap: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(t.dialogs.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(t.dialogs.import),
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
      ScaffoldMessenger.of(
        navContext,
      ).showSnackBar(SnackBar(content: Text(t.deepLink.importSuccess)));
    }
  } catch (e) {
    _log('[deeplink] import failed: $e');
    if (navContext.mounted) {
      ScaffoldMessenger.of(navContext).clearSnackBars();
      ScaffoldMessenger.of(navContext).showSnackBar(
        SnackBar(content: Text(t.deepLink.importFailed(error: '$e'))),
      );
    }
  }
}

void _log(String msg) {
  LogFileWriter.instance?.log(msg, name: 'deeplink');
}
