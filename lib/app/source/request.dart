import 'dart:async';

import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:dio/dio.dart';
import 'package:clash_for_flutter/app/bean/config_bean.dart';
import 'package:clash_for_flutter/app/bean/group_bean.dart';
import 'package:clash_for_flutter/app/bean/proxies_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_bean.dart';
import 'package:clash_for_flutter/app/bean/proxy_providers_bean.dart';

class Request {
  var _dio = Dio(BaseOptions(
    baseUrl: "http://localhost:9090",
    connectTimeout: 5000,
    receiveTimeout: 5000,
  ));

  Future<dynamic> downFile({String urlPath, String savePath}) {
    return Dio().download(urlPath, savePath);
  }

  /// 获取所有代理
  Future<Proxies> getProxies() async {
    var res = await _dio.get("/proxies");
    var proxies = JsonMapper.deserialize<Proxies>(res.data);
    return proxies;
  }

  /// 获取单个代理
  Future<dynamic> oneProxie(String name) async {
    var res = await _dio.get("/proxies/$name");
    var data = res.data;
    return data.containsKey("now")
        ? JsonMapper.deserialize<Group>(data)
        : JsonMapper.deserialize<Proxy>(data);
  }

  Future<ProxyProviders> getProxyProviders() async {
    var res = await _dio.get("/providers/proxies");
    var providers = JsonMapper.deserialize<ProxyProviders>(res.data);
    return providers;
  }

  /// 获取单个代理的延迟
  Future<int> getProxyDelay(String name) {
    return _dio.get("/proxies/$name/delay", queryParameters: {
      "timeout": 3000,
      "url": 'http://www.gstatic.com/generate_204'
    }).then((res) => res.data["delay"]);
  }

  /// 切换 Selector 中选中的代理
  Future<Response<void>> changeProxy({String name, String select}) {
    return _dio.put<void>("/proxies/$name", data: {"name": select});
  }

  /// 获得当前的基础设置
  Future<Config> getConfigs() async {
    var res = await _dio.get("/configs");
    return JsonMapper.deserialize<Config>(res.data);
  }

  /// 增量修改配置
  Future<Response<void>> updateConfig(Config config) {
    return _dio.patch<void>("/configs", data: JsonMapper.serialize(config));
  }
}
