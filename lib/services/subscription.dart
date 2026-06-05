import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/domain/subscription_info.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/services/app_config.dart';
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
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode}');
    }

    final bytes = await resp
        .timeout(const Duration(minutes: 3), onTimeout: (sink) => sink.close())
        .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
    final raw = utf8.decode(bytes);
    String content;
    try {
      content = isBase64Content(raw) ? decodeBase64Subscription(raw) : raw;
    } catch (_) {
      content = raw;
    }
    await File(savePath).writeAsString(content);

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

String decodeBase64Subscription(String raw) {
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
  if (proxies.isEmpty) return raw;
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
  return switch (scheme) {
    'ss' => parseShadowsocks(body, name),
    'ssr' => {'name': name, 'type': 'ssr', 'server': '', 'port': 0},
    'vmess' => parseVmess(body, name),
    'vless' => parseVless(body, name),
    'trojan' => parseTrojan(body, name),
    'hysteria' || 'hysteria2' || 'hy2' => {
        'name': name,
        'type': scheme == 'hysteria' ? 'hysteria' : 'hysteria2',
        'server': '',
        'port': 0,
      },
    _ => null,
  };
}

Map<String, dynamic>? parseShadowsocks(String body, String name) {
  try {
    String decoded;
    if (body.contains('@')) {
      final atIdx = body.indexOf('@');
      final encoded = body.substring(0, atIdx);
      decoded = utf8.decode(base64.decode(encoded));
      final serverPort = body.substring(atIdx + 1).split('?')[0].split(':');
      return {
        'name': name,
        'type': 'ss',
        'server': serverPort[0],
        'port': int.parse(serverPort[1]),
        'cipher': decoded.split(':').first,
        'password': decoded.split(':').last,
      };
    } else {
      decoded = utf8.decode(base64.decode(body.split('?')[0]));
      final parts = decoded.split('@');
      final methodPass = parts[0].split(':');
      final serverPort = parts[1].split(':');
      return {
        'name': name,
        'type': 'ss',
        'server': serverPort[0],
        'port': int.parse(serverPort[1]),
        'cipher': methodPass[0],
        'password': methodPass[1],
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
    throw Exception('配置校验失败: $validation');
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
Future<void> importSubscription(String url) async {
  final profile = await downloadSubscription(
    url: url,
    profilesDir: profilesPath,
  );
  await validateConfigFile(p.join(profilesPath, profile.file));
  final wasEmpty = profiles.value.isEmpty;
  profiles.value = [...profiles.value, profile];
  if (wasEmpty) selectedFile.value = profile.file;
}
