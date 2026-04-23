import 'dart:convert';
import 'dart:io';

import 'package:clash_for_flutter/domain/config.dart';
import 'package:clash_for_flutter/domain/connection.dart';
import 'package:clash_for_flutter/domain/log.dart';
import 'package:clash_for_flutter/domain/net_speed.dart';
import 'package:clash_for_flutter/domain/profile.dart';
import 'package:clash_for_flutter/domain/proxy.dart';
import 'package:clash_for_flutter/domain/proxy_group.dart';
import 'package:clash_for_flutter/domain/subscription_info.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

class ClashApi {
  final _clash = Dio(BaseOptions(
    baseUrl: 'http://${Constants.rustAddr}',
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 5),
  ));

  final _download = Dio(BaseOptions(
    headers: {'User-Agent': 'Clash for Flutter'},
    connectTimeout: const Duration(seconds: 3),
  ));

  Future<void> hello() => _clash.get('/');

  Future<Map<String, dynamic>> getProxies() async {
    final res = await _clash.get<Map<String, dynamic>>('/proxies');
    return res.data?['proxies'] as Map<String, dynamic>? ?? {};
  }

  Future<int?> getProxyDelay(String name, String url) async {
    final res = await _clash.get<Map>('/proxies/$name/delay',
        queryParameters: {'timeout': 2900, 'url': url});
    return res.data?['delay'] as int?;
  }

  Future<bool> changeProxy({required String name, required String select}) async {
    final res = await _clash.put('/proxies/$name', data: {'name': select});
    return res.statusCode == HttpStatus.noContent;
  }

  Future<ClashConfig?> getConfigs() async {
    final res = await _clash.get<Map<String, dynamic>>('/configs');
    if (res.data == null) return null;
    return ClashConfig.fromJson(res.data!);
  }

  Future<bool> changeConfig(String path) async {
    final res = await _clash.put('/configs',
        queryParameters: {'force': false}, data: {'path': path});
    return res.statusCode == HttpStatus.noContent;
  }

  Future<bool> patchConfigs(ClashConfig config) async {
    final res = await _clash.patch('/configs', data: config.toJson());
    return res.statusCode == HttpStatus.noContent;
  }

  Future<bool> closeAllConnections() async {
    final res = await _clash.delete('/connections');
    return res.statusCode == HttpStatus.noContent;
  }

  Future<bool> closeConnection(String id) async {
    final res = await _clash.delete('/connections/$id');
    return res.statusCode == HttpStatus.noContent;
  }

  Future<String?> getVersion() async {
    final res = await _clash.get<Map<String, dynamic>>('/version');
    return res.data?['version'] as String?;
  }

  Future<Profile> downloadSubscription({
    required String url,
    required String profilesDir,
    String? name,
  }) async {
    final time = DateTime.now();
    final file = '${time.millisecondsSinceEpoch}.yaml';
    final savePath = p.join(profilesDir, file);

    final resp = await _download.download(url, savePath);

    String fileName = name ?? '';
    if (fileName.isEmpty) {
      final headerDis = resp.headers.value('content-disposition');
      if (headerDis != null) {
        final disposition = HeaderValue.parse(headerDis);
        for (final entry in disposition.parameters.entries) {
          if (entry.key.startsWith('filename')) {
            fileName = entry.key == 'filename*'
                ? Uri.decodeComponent(entry.value.split("'").last)
                : entry.value;
          }
        }
      }
      if (fileName.isEmpty) fileName = file;
    }

    SubscriptionInfo? info;
    final headerInfo = resp.headers.value('subscription-userinfo');
    if (headerInfo != null) info = SubscriptionInfo.fromHeader(headerInfo);

    int interval = 0;
    final intervalStr = resp.headers.value('profile-update-interval');
    if (intervalStr != null) interval = int.tryParse(intervalStr) ?? 0;

    return Profile(
      file: file,
      name: fileName,
      type: ProfileType.url,
      time: time,
      url: url,
      interval: interval,
      userinfo: info,
    );
  }

  Future<String> downloadFile(String url, String savePath,
      {void Function(int, int)? onProgress}) {
    return _download
        .download(url, savePath, onReceiveProgress: onProgress)
        .then((_) => savePath);
  }

  Future<String?> checkLatestVersion() async {
    final res = await Dio().get<Map<String, dynamic>>(Constants.releaseUrl);
    return res.data?['tag_name'] as String?;
  }
}