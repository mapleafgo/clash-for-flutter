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

  Future<dynamic> downFile({
    required String urlPath,
    required String savePath,
  }) {
    return Dio().download(urlPath, savePath);
  }

  /// 获取所有代理
  Future<Proxies?> getProxies() async {
    var res = await _dio.get<Map<String, dynamic>>("/proxies");
    return JsonMapper.fromMap<Proxies>(res.data);
  }

  /// 获取单个代理
  Future<dynamic> oneProxie(String name) async {
    var res = await _dio.get<Map<String, dynamic>>("/proxies/$name");
    var data = res.data;
    if (data != null) {
      return data.containsKey("now")
          ? JsonMapper.fromMap<Group>(data)
          : JsonMapper.fromMap<Proxy>(data);
    }
    return null;
  }

  Future<ProxyProviders?> getProxyProviders() async {
    var res = await _dio.get<Map<String, dynamic>>("/providers/proxies");
    return JsonMapper.fromMap<ProxyProviders>(res.data);
  }

  /// 获取单个代理的延迟
  Future<int?> getProxyDelay(String name) {
    return _dio.get<Map>("/proxies/$name/delay", queryParameters: {
      "timeout": 3000,
      "url": 'http://www.gstatic.com/generate_204'
    }).then((res) => res.data?["delay"]);
  }

  /// 切换 Selector 中选中的代理
  Future<Response<void>> changeProxy({
    required String name,
    required String select,
  }) {
    return _dio.put<void>("/proxies/$name", data: {"name": select});
  }

  /// 获得当前的基础设置
  Future<Config?> getConfigs() async {
    var res = await _dio.get<Map<String, dynamic>>("/configs");
    return JsonMapper.fromMap<Config>(res.data);
  }

  /// 增量修改配置
  Future<Response<void>> updateConfig(Config config) {
    return _dio.patch<void>("/configs", data: JsonMapper.serialize(config));
  }
}
