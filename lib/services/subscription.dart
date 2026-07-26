import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/domain/subscription_info.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

int _lastFileMs = 0;

String _uniqueFileName() {
  var ms = DateTime.now().millisecondsSinceEpoch;
  if (ms == _lastFileMs) ms++;
  _lastFileMs = ms;
  return '$ms.yaml';
}

/// Download a subscription from a URL and save it as a profile file.
Future<Profile> downloadSubscription({
  required String url,
  required String profilesDir,
  String? name,
  int? interval,
}) async {
  final file = _uniqueFileName();
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
    final raw = utf8.decode(bytes);
    final String content;
    if (isBase64Content(raw)) {
      content = decodeBase64Subscription(raw) ??
          (throw FormatException('No valid proxies found in base64 subscription'));
    } else {
      content = raw;
    }
    await File(savePath).writeAsString(content);
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

String? decodeBase64Subscription(String raw) {
  final decoded = utf8.decode(base64.decode(raw.trim()));
  final lines = decoded
      .split(RegExp(r'\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty);
  final proxies = <Map<String, dynamic>>[];
  for (final line in lines) {
    final proxy = parseProxyUri(line);
    if (proxy != null) proxies.add(proxy);
  }
  if (proxies.isEmpty) return null;
  final editor = YamlEditor('proxies: []\n');
  editor.update(['proxies'], proxies);
  return editor.toString();
}

Map<String, dynamic>? parseProxyUri(String uri) {
  if (!uri.contains('://')) return null;
  final typeEnd = uri.indexOf('://');
  final scheme = uri.substring(0, typeEnd).toLowerCase();
  final rest = uri.substring(typeEnd + 3);
  final hashIdx = rest.indexOf('#');
  String name = 'proxy';
  String body = rest;
  if (hashIdx >= 0) {
    name = Uri.decodeComponent(rest.substring(hashIdx + 1));
    body = rest.substring(0, hashIdx);
  }
  // 不支持的协议(ssr/hysteria v1 等)直接跳过：生成空 server 占位节点
  // 会写进 YAML 并在内核校验时报出与真实原因无关的错误。
  final proxy = switch (scheme) {
    'ss' => parseShadowsocks(body, name),
    'vmess' => parseVmess(body, name),
    'vless' => parseVless(body, name),
    'trojan' => parseTrojan(body, name),
    'hysteria2' || 'hy2' => parseHysteria2(body, name),
    _ => null,
  };
  if (proxy == null) {
    LogFileWriter.instance?.log(
      'unsupported proxy scheme skipped: $scheme ($name)',
      level: LogLevel.warning,
      name: 'sub',
    );
  }
  return proxy;
}

Map<String, dynamic>? parseShadowsocks(String body, String name) {
  try {
    String decoded;
    if (body.contains('@')) {
      final atIdx = body.indexOf('@');
      final encoded = body.substring(0, atIdx);
      // SIP002 userinfo 是无填充 base64url，normalize 补齐 padding
      decoded = utf8.decode(base64.decode(base64.normalize(encoded)));
      final serverPort = body.substring(atIdx + 1).split('?')[0].split(':');
      // 只按第一个冒号切分：SS2022 等密码本身可能含冒号
      final colonIdx = decoded.indexOf(':');
      return {
        'name': name,
        'type': 'ss',
        'server': serverPort[0],
        'port': int.tryParse(serverPort[1]) ?? 0,
        'cipher': decoded.substring(0, colonIdx),
        'password': decoded.substring(colonIdx + 1),
      };
    } else {
      decoded = utf8.decode(base64.decode(base64.normalize(body.split('?')[0])));
      final atIdx = decoded.lastIndexOf('@');
      final methodPass = decoded.substring(0, atIdx);
      final serverPort = decoded.substring(atIdx + 1).split(':');
      final colonIdx = methodPass.indexOf(':');
      return {
        'name': name,
        'type': 'ss',
        'server': serverPort[0],
        'port': int.tryParse(serverPort[1]) ?? 0,
        'cipher': methodPass.substring(0, colonIdx),
        'password': methodPass.substring(colonIdx + 1),
      };
    }
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? parseVmess(String body, String name) {
  try {
    final decoded = utf8.decode(base64.decode(body));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    return {
      'name': name,
      'type': 'vmess',
      'server': json['add'],
      'port': json['port'],
      'uuid': json['id'],
      'alterId': json['aid'] ?? 0,
      'cipher': json['scy'] ?? 'auto',
    };
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? parseVless(String body, String name) {
  try {
    final uri = Uri.parse('vless://$body');
    final params = uri.queryParameters;
    return {
      'name': name,
      'type': 'vless',
      'server': uri.host,
      'port': uri.port,
      'uuid': uri.userInfo,
      'udp': true,
      'tls': params['security'] == 'tls' || params['security'] == 'reality',
      if (params['flow'] != null) 'flow': params['flow'],
      if (params['sni'] != null) 'servername': params['sni'],
      if (params['type'] != null) 'network': params['type'],
    };
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? parseHysteria2(String body, String name) {
  try {
    final uri = Uri.parse('hysteria2://$body');
    if (uri.host.isEmpty) return null;
    final params = uri.queryParameters;
    return {
      'name': name,
      'type': 'hysteria2',
      'server': uri.host,
      // URI 未写端口时 Uri.port 为 0，hysteria2 约定默认 443
      'port': uri.port == 0 ? 443 : uri.port,
      'password': uri.userInfo,
      if (params['sni'] != null) 'sni': params['sni'],
      if (params['insecure'] == '1') 'skip-cert-verify': true,
      if (params['obfs'] != null) 'obfs': params['obfs'],
      if (params['obfs-password'] != null)
        'obfs-password': params['obfs-password'],
    };
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? parseTrojan(String body, String name) {
  try {
    final uri = Uri.parse('trojan://$body');
    return {
      'name': name,
      'type': 'trojan',
      'server': uri.host,
      'port': uri.port,
      'password': uri.userInfo,
    };
  } catch (_) {
    return null;
  }
}

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

bool isBase64Content(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return false;
  try {
    final decoded = utf8.decode(base64.decode(trimmed));
    return decoded.contains('://');
  } catch (_) {
    return false;
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
