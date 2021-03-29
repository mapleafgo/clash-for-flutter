import 'dart:convert';
import 'dart:io';

import 'package:clash_for_flutter/app/exceptions/message_exception.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/plugin/pac-proxy.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_bean.dart';
import 'package:clash_for_flutter/app/utils/constant.dart';
import 'package:go_flutter_clash/go_flutter_clash.dart';
import 'package:go_flutter_clash/model/flutter_clash_config_model.dart';
import 'package:go_flutter_systray/go_flutter_systray.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

part 'global_config.g.dart';

class GlobalConfig = _ConfigFileBase with _$GlobalConfig;

abstract class _ConfigFileBase extends Disposable with Store {
  final _request = Modular.get<Request>();
  late Directory configDir;

  List<ReactionDisposer> _disposers = [];
  @observable
  bool systemProxy = false;
  @observable
  late FlutterClashConfig clashConfig;
  @observable
  late ClashForMeConfig clashForMe;

  @override
  dispose() async {
    await for (ReactionDisposer item in Stream.fromIterable(_disposers)) {
      item();
    }
  }

  Future<void> init() async {
    configDir = await getApplicationSupportDirectory();
    var clashConfigFile = File(configDir.path + Constant.clashConfig);
    var clashForMeFile = File(configDir.path + Constant.clashForMe);
    if (await clashConfigFile.exists()) {
      this.clashConfig = JsonMapper.deserialize<FlutterClashConfig>(
            await clashConfigFile.readAsString(),
          ) ??
          FlutterClashConfig.defaultConfig();
    }
    if (await clashForMeFile.exists()) {
      this.clashForMe = await _profilesInitCheck(
            JsonMapper.deserialize<ClashForMeConfig>(
              await clashForMeFile.readAsString(),
            ),
          ) ??
          ClashForMeConfig.defaultConfig();
    }

    await _initClash();

    _initDispose();
  }

  // 初始化clash
  Future<void> _initClash() async {
    var dbFile = File(configDir.path + Constant.db);
    if (!dbFile.existsSync()) {
      await _request.downFile(
        urlPath: Constant.dbUrl,
        savePath: dbFile.path,
      );
    }
    return GoFlutterClash.init(configDir.path);
  }

  _initDispose() {
    _disposers = [
      reaction(
        (_) => clashConfig,
        (FlutterClashConfig config) {
          File(configDir.path + Constant.clashConfig)
              .create(recursive: true)
              .then(
                (file) => file.writeAsString(JsonMapper.serialize(config)),
              );
        },
        delay: 2000,
      ),
      reaction(
        (_) => clashForMe,
        (ClashForMeConfig config) {
          File(configDir.path + Constant.clashForMe)
              .create(recursive: true)
              .then(
                (file) => file.writeAsString(JsonMapper.serialize(config)),
              );
        },
        delay: 2000,
      ),
    ];
  }

  /// 校验本地订阅文件与配置里对应
  Future<ClashForMeConfig?> _profilesInitCheck(ClashForMeConfig? config) async {
    if (config == null) return null;

    var profilesDir = Directory(configDir.path + Constant.profilesPath);
    var fileList = <String>[];
    if (await profilesDir.exists()) {
      fileList = await profilesDir.list().where((e) => e is File).map((file) {
        var lastIndex = file.path.replaceAll("\/", "\\").lastIndexOf("\\");
        return file.path.substring(lastIndex + 1);
      }).toList();
    }

    List<Profile> profiles =
        config.profiles.where((e) => fileList.contains(e.file)).toList();

    var selectElements = profiles.where((e) => e.file == config.selectedFile);
    if (selectElements.isNotEmpty) {
      return ClashForMeConfig(
        selectedFile: selectElements.first.file,
        profiles: profiles,
      );
    }
    return ClashForMeConfig(profiles: profiles);
  }

  /// 当前应用中的配置文件
  @computed
  Profile? get active {
    var selectedFile = clashForMe.selectedFile;
    var profiles = clashForMe.profiles;
    if (selectedFile != null) {
      return profiles.firstWhere((item) => item.file == selectedFile);
    }
    return null;
  }

  @action
  setState({ClashForMeConfig? clashForMe, FlutterClashConfig? clashConfig}) {
    if (clashForMe != null) this.clashForMe = clashForMe;
    if (clashConfig != null) this.clashConfig = clashConfig;
  }

  /// 启动clash
  Future<void> start() async {
    // 判断是否有订阅
    if (clashForMe.profiles.isEmpty) {
      throw new MessageException("暂无任何订阅可用，请先添加订阅");
    }
    // 判断是否已选择订阅
    if (clashForMe.selectedFile == "") {
      throw new MessageException("未指定订阅");
    }
    var file = File(
      "${configDir.path}${Constant.profilesPath}/${clashForMe.selectedFile}",
    );
    // 判断订阅的配置文件是否存在
    if (!file.existsSync()) {
      throw new MessageException("订阅文件已不存在，请更新订阅");
    }
    return GoFlutterClash.start(
      json.encode(loadYaml(await file.readAsString())),
      clashConfig,
    ).then((_) {
      active?.selected.forEach((key, value) {
        _request.changeProxy(name: key, select: value);
      });
    });
  }

  /// 打开代理
  @action
  Future<void> openProxy() async {
    await start();
    try {
      await PACProxy.open(this.clashConfig.mixedPort.toString());
    } on PlatformException catch (e) {
      throw new MessageException(e.message ?? "开启代理异常");
    }
    GoFlutterSystray.itemCheck(Constant.systrayProxyKey);
    systemProxy = true;
  }

  /// 关闭代理
  @action
  Future<void> closeProxy() async {
    await PACProxy.close();
    GoFlutterSystray.itemUncheck(Constant.systrayProxyKey);
    systemProxy = false;
  }

  /// 切换代理
  proxySelect({required String name, required String select}) {
    if (active == null) return;

    var index = clashForMe.profiles.indexOf(active!);
    var profile = JsonMapper.deserialize<Profile>(JsonMapper.serialize(active));
    profile!.selected[name] = select;

    var config = JsonMapper.deserialize<ClashForMeConfig>(
      JsonMapper.serialize(clashForMe),
    );
    config!.profiles[index] = profile;
    setState(clashForMe: config);
  }
}
