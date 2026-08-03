import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/domain/subscription_info.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:path/path.dart' as p;

int _lastFileMs = 0;

/// 生成唯一 profile 文件名（基于毫秒时间戳，含同毫秒碰撞保护）。
/// 供下载订阅与迁移转换共用。
String uniqueProfileFileName() {
  var ms = DateTime.now().millisecondsSinceEpoch;
  if (ms == _lastFileMs) ms++;
  _lastFileMs = ms;
  return '$ms.json';
}

/// Download a subscription from a URL and save it as a profile file.
Future<Profile> downloadSubscription({
  required String url,
  required String profilesDir,
  String? name,
  int? interval,
}) async {
  final file = uniqueProfileFileName();
  final savePath = p.join(profilesDir, file);

  // 确保 profiles 目录存在
  final dir = Directory(profilesDir);
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }

  final client = HttpClient()
    ..userAgent = subUA.value
    ..connectionTimeout = const Duration(seconds: 15);
  final sw = Stopwatch()..start();
  LogFileWriter.instance?.log('downloading subscription: $url', name: 'sub');
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode}');
    }

    // timeout 挂在 fold 的 Future 上限制总时长；挂在 Stream 上只限制
    // 相邻 chunk 间隔，慢速滴流的服务器可以无限拖住下载。
    final bytes = await resp
        .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk))
        .timeout(const Duration(minutes: 3));
    // base64 解码、格式识别、URI 列表转换全部由内核处理
    final raw = utf8.decode(bytes);
    final jsonContent = await LibCore.instance.convert(raw);
    await File(savePath).writeAsString(jsonContent);
    LogFileWriter.instance?.log(
      'subscription saved: ${bytes.length} bytes in ${sw.elapsedMilliseconds}ms',
      name: 'sub',
    );

    return Profile(
      file: file,
      name: name ?? extractFilename(resp.headers.value('content-disposition')) ?? file,
      type: ProfileType.url,
      time: DateTime.now(),
      url: url,
      interval: interval ?? int.tryParse(resp.headers.value('profile-update-interval') ?? '') ?? 24,
      userinfo: parseSubInfo(resp.headers.value('subscription-userinfo')),
    );
  } finally {
    client.close();
  }
}

String? extractFilename(String? contentDisposition) {
  if (contentDisposition == null) return null;
  final params = HeaderValue.parse(contentDisposition).parameters;
  if (params.containsKey('filename*')) {
    final parts = params['filename*']!.split("'");
    if (parts.isNotEmpty) return Uri.decodeComponent(parts.last);
  }
  return params['filename'];
}

SubscriptionInfo? parseSubInfo(String? raw) =>
    raw != null ? SubscriptionInfo.fromHeader(raw) : null;

/// 校验配置文件内容，不通过时删除文件并抛出异常。
Future<void> validateConfigFile(String filePath) async {
  final validation = await LibCore.instance.checkConfig(
    await File(filePath).readAsString(),
  );
  if (validation.isNotEmpty) {
    await File(filePath).delete();
    throw Exception(t.profiles.configValidationFailed(validation: validation));
  }
}

/// 下载订阅、校验并添加到配置列表。
/// 供 deep link 和 UI 共用。
///
/// 当 [url] 已存在于现有订阅中时抛出 [StateError]。
Future<void> importSubscription(String url, {String? name}) async {
  if (profiles.value.any((e) => e.url == url)) {
    throw StateError(t.profiles.subscriptionExists);
  }

  final dir = profilesFullPath;
  final profile = await downloadSubscription(
    url: url,
    profilesDir: dir,
    name: name,
  );
  await validateConfigFile(p.join(dir, profile.file));
  final wasEmpty = profiles.value.isEmpty;
  profiles.value = [...profiles.value, profile];
  if (wasEmpty) selectedFile.value = profile.file;
}
