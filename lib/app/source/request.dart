import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clash_for_flutter/app/bean/config_bean.dart';
import 'package:clash_for_flutter/app/bean/connection_bean.dart';
import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/log_bean.dart';
import 'package:clash_for_flutter/app/bean/net_speed.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/bean/proxies_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_providers_bean.dart';
import 'package:clash_for_flutter/app/bean/sub_userinfo_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Request {
  final _clashDio = Dio(
    BaseOptions(
      baseUrl: "http://${Constants.localhost}:${Constants.port}",
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  Future<Response> downFile({
    required String urlPath,
    required String savePath,
    void Function(int, int)? onReceiveProgress,
  }) {
    return Dio(BaseOptions(
      headers: {'User-Agent': 'Clash For Flutter'},
      connectTimeout: const Duration(seconds: 3),
    )).download(urlPath, savePath, onReceiveProgress: onReceiveProgress);
  }

  /// 下载订阅
  Future<ProfileURL> getSubscribe({
    required ProfileURL profile,
    required String profilesDir,
  }) {
    var time = DateTime.now();
    var file = "${time.millisecondsSinceEpoch}.yaml";
    var savePath = "$profilesDir/$file";
    return downFile(urlPath: profile.url, savePath: savePath).then((resp) {
      if (profile.name.isEmpty) {
        resp.headers["content-disposition"]?.forEach((v) {
          var filename = HeaderValue.parse(v).parameters["filename"];
          if (filename != null) {
            profile.name = filename;
          } else {
            profile.name = file;
          }
        });
      }
      resp.headers["subscription-userinfo"]?.forEach((v) {
        profile.userinfo = SubUserinfo.formHString(v);
      });
      var value = resp.headers.value("profile-update-interval");
      if (value != null && profile.interval == 0) {
        profile.interval = int.parse(value);
      }
      return profile
        ..time = time
        ..file = file;
    });
  }

  /// 获取所有代理
  Future<Proxies?> getProxies() async {
    var res = await _clashDio.get<Map<String, dynamic>>("/proxies");
    return JsonMapper.fromMap<Proxies>(res.data);
  }

  /// 获取单个代理
  Future<dynamic> oneProxies(String name) async {
    var res = await _clashDio.get<Map<String, dynamic>>("/proxies/$name");
    var data = res.data?.containsKey("now");
    return data == true ? JsonMapper.fromMap<Group>(res.data) : JsonMapper.fromMap<Proxy>(res.data);
  }

  /// 获取单个代理的延迟
  Future<int?> getProxyDelay(String name, String url) {
    return _clashDio.get<Map>("/proxies/$name/delay", queryParameters: {
      "timeout": 2900,
      "url": url,
    }).then((res) => res.data?["delay"]);
  }

  /// 切换 Selector 中选中的代理
  Future<bool> changeProxy({
    required String name,
    required String select,
  }) async {
    var resp = await _clashDio.put<void>(
      "/proxies/$name",
      data: {"name": select},
    );
    return resp.statusCode == HttpStatus.noContent;
  }

  /// 获得当前的基础设置
  Future<Config?> getConfigs() async {
    var res = await _clashDio.get<Map<String, dynamic>>("/configs");
    return JsonMapper.fromMap<Config>(res.data);
  }

  /// 切换配置文件 [path] 必须为绝对路径
  Future<bool> changeConfig(String path) async {
    var resp = await _clashDio.put(
      "/configs",
      queryParameters: {"force": false},
      data: {"path": path},
    );
    return resp.statusCode == HttpStatus.noContent;
  }

  /// 增量修改配置
  Future<bool> patchConfigs(Config config) async {
    var resp = await _clashDio.patch<void>(
      "/configs",
      data: JsonMapper.serialize(config),
    );
    return resp.statusCode == HttpStatus.noContent;
  }

  Future<ProxyProviders?> getProxyProviders() async {
    var res = await _clashDio.get<Map<String, dynamic>>("/providers/proxies");
    return JsonMapper.fromMap<ProxyProviders>(res.data);
  }

  /// 获取内核版本
  Future<String?> getClashVersion() async {
    var res = await _clashDio.get<Map<String, dynamic>>("/version");
    return res.data?["version"];
  }

  Stream<NetSpeed?> traffic() {
    var channel = WebSocketChannel.connect(Uri.parse("ws://${Constants.localhost}:${Constants.port}/traffic"));
    return channel.stream.map((event) => JsonMapper.deserialize<NetSpeed>(event));
  }

  Stream<LogData?> logs(LogLevel level) {
    var uri = Uri.parse("ws://${Constants.localhost}:${Constants.port}/logs?level=${level.value}}");
    var channel = WebSocketChannel.connect(uri);
    return channel.stream.map((event) => JsonMapper.deserialize<LogData>(event)?..time = DateTime.now());
  }

  Stream<Snapshot?> connections() {
    var channel = WebSocketChannel.connect(Uri.parse("ws://${Constants.localhost}:${Constants.port}/connections"));
    return channel.stream.map((event) => JsonMapper.deserialize<Snapshot>(event));
  }

  Future<bool> closeAllConnections() async {
    var resp = await _clashDio.delete<ResponseBody>("/connections");
    return resp.statusCode == HttpStatus.noContent;
  }

  Future<bool> closeConnections(String id) async {
    var resp = await _clashDio.delete<ResponseBody>("/connections/$id");
    return resp.statusCode == HttpStatus.noContent;
  }
}
