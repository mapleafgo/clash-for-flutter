import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clash_for_flutter/app/bean/config_bean.dart';
import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/bean/proxies_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_providers_bean.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:dio/dio.dart';

class Request {
  final _clashDio = Dio(
    BaseOptions(
      baseUrl: "http://${Constants.localhost}:9090",
      connectTimeout: 3000,
      receiveTimeout: 3000,
    ),
  );

  Future<Response> downFile({
    required String urlPath,
    required String savePath,
  }) {
    return Dio(BaseOptions(
      headers: {'User-Agent': 'Clash For Flutter'},
      connectTimeout: 20000,
      receiveTimeout: 20000,
    )).download(urlPath, savePath);
  }

  /// 下载订阅
  Future<ProfileURL> getSubscribe({
    required ProfileURL profile,
    required String profilesDir,
  }) {
    var time = DateTime.now();
    var file = "${time.millisecondsSinceEpoch}.yaml";
    var savePath = "$profilesDir/$file";
    return downFile(urlPath: profile.url, savePath: savePath).then((_) {
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
    return data == true
        ? JsonMapper.fromMap<Group>(res.data)
        : JsonMapper.fromMap<Proxy>(res.data);
  }

  /// 获取单个代理的延迟
  Future<int?> getProxyDelay(String name) {
    return _clashDio.get<Map>("/proxies/$name/delay", queryParameters: {
      "timeout": 3000,
      "url": 'http://www.gstatic.com/generate_204'
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
    var res = await _clashDio.get<Map<String, String>>("/version");
    return res.data?["version"];
  }

  Future<Stream<Uint8List>?> traffic() {
    var resp = _clashDio.get<ResponseBody>(
      "/traffic",
      options: Options(responseType: ResponseType.stream, receiveTimeout: 0),
    );
    return resp.then((res) => res.data?.stream);
  }

  Future<Stream<Uint8List>?> logs() {
    var resp = _clashDio.get<ResponseBody>(
      "/logs",
      options: Options(responseType: ResponseType.stream, receiveTimeout: 0),
    );
    return resp.then((res) => res.data?.stream);
  }
}
