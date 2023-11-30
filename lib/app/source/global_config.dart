import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/tun_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:clash_for_flutter/core_control.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxy_manager/proxy_manager.dart';

part 'global_config.g.dart';

class GlobalConfig = ConfigFileBase with _$GlobalConfig;

final proxyManager = ProxyManager();

abstract class ConfigFileBase with Store {
  final _request = Modular.get<Request>();
  static bool isStartClash = false;

  late Directory configDir;
  late final String clashConfigPath;
  late final String clashForMePath;
  late final String profilesPath;

  @observable
  bool systemProxy = false;
  @observable
  Config clashConfig = Config.defaultConfig();
  @observable
  ClashForMeConfig clashForMe = ClashForMeConfig.defaultConfig();

  Future<void> init() async {
    await getApplicationSupportDirectory().then((dir) => configDir = dir);

    profilesPath = "${configDir.path}${Constants.profilesPath}";
    clashForMePath = "${configDir.path}${Constants.clashForMe}";
    clashConfigPath = "${configDir.path}${Constants.clashConfig}";

    await CoreControl.init();
    await _initConfig();
    await _initAction();
  }

  @action
  _initConfig() async {
    ClashForMeConfig? tempCfm = ClashForMeConfig.formFile(clashForMePath);
    tempCfm = await _profilesInitCheck(tempCfm);
    if (tempCfm != null) {
      clashForMe = tempCfm;
    }

    // 读取 clash 基础配置
    if (File(clashConfigPath).existsSync()) {
      clashConfig = Config.formYamlFile(clashConfigPath);
    } else {
      clashConfig.saveFile(clashConfigPath);
    }

    // 设置目录与配置文件
    await CoreControl.setHomeDir(configDir);
    await CoreControl.setConfig(File(clashConfigPath));

    // 启动 rust 控制服务，端口随机
    var addr = await CoreControl.startRust("${Constants.localhost}:${Random().nextInt(1000) + 10000}");
    Constants.rustAddr = addr ?? "";
  }

  _initAction() {
    reaction(
      (_) => clashConfig,
      (Config config) {
        config.saveFile(clashConfigPath);
        if (isStartClash) {
          _request.patchConfigs(config);
        }
        if (systemProxy) {
          openProxy();
        }
      },
      delay: 1000,
    );
    reaction(
      (_) => clashForMe,
      (ClashForMeConfig config) => config.saveFile(clashForMePath),
      delay: 1000,
    );
    reaction(
      (_) => selectedFile ?? clashConfigPath,
      (String file) {
        if (!File(file).isAbsolute) {
          file = "$profilesPath/$file";
        }
        if (isStartClash) {
          _changeProfile(file);
        }
      },
    );
  }

  /// 校验本地订阅文件与配置里对应
  Future<ClashForMeConfig?> _profilesInitCheck(ClashForMeConfig? config) async {
    if (config == null) return null;

    var profilesDir = Directory(profilesPath);
    var fileList = <String>[];
    if (await profilesDir.exists()) {
      fileList = await profilesDir.list().where((e) => e is File).map((file) {
        var lastIndex = file.path.replaceAll("/", "\\").lastIndexOf("\\");
        return file.path.substring(lastIndex + 1);
      }).toList();
    }

    List<ProfileBase> profiles = config.profiles.where((e) => fileList.contains(e.file)).toList();
    return config.copyWith(profiles: profiles);
  }

  /// 当前应用中的配置文件
  @computed
  ProfileBase? get active {
    if (selectedFile == null) {
      return null;
    }
    return clashForMe.profiles.firstWhere((e) => e.file == selectedFile);
  }

  @computed
  String? get selectedFile => clashForMe.selectedFile;

  @computed
  List<ProfileBase> get profiles => clashForMe.profiles;

  Future<void> _changeProfile(String file) {
    return _request.changeConfig(file);
  }

  @action
  setState({
    String? selectedFile,
    List<ProfileBase>? profiles,
    String? mmdbUrl,
    String? delayTestUrl,
    int? port,
    int? socksPort,
    int? redirPort,
    int? tproxyPort,
    int? mixedPort,
    bool? allowLan,
    Mode? mode,
    LogLevel? logLevel,
    bool? ipv6,
  }) {
    clashForMe = clashForMe.copyWith(
      selectedFile: selectedFile,
      profiles: profiles,
      mmdbUrl: mmdbUrl,
      delayTestUrl: delayTestUrl,
    );
    clashConfig = clashConfig.copyWith(
      port: port,
      socksPort: socksPort,
      redirPort: redirPort,
      tproxyPort: tproxyPort,
      mixedPort: mixedPort,
      allowLan: allowLan,
      mode: mode,
      logLevel: logLevel,
      ipv6: ipv6,
    );
  }

  /// 启动clash
  Future<bool> start() async {
    if (await CoreControl.startService() ?? false) {
      if (active != null) {
        await _changeProfile("$profilesPath/${active?.file}");
      }
      var c = await _request.getConfigs();
      clashConfig = c ?? clashConfig;
      isStartClash = true;
      return true;
    }
    return false;
  }

  Future<bool?> verifyMMDB(String path) {
    return CoreControl.verifyMMDB(path);
  }

  /// 打开代理
  @action
  Future<void> openProxy() async {
    if (Constants.isDesktop) {
      if (await _request.patchConfigs(Config(tun: Tun(enable: true)))) {
        systemProxy = true;
      }
    } else if (Platform.isAndroid) {
      await CoreControl.startVpn();
      systemProxy = true;
    }
/*
    int port = clashConfig.mixedPort ?? 7890;
    if (Constants.isDesktop) {
      if (port != 0) {
        if (!Platform.isWindows) {
          await proxyManager.setAsSystemProxy(
            ProxyTypes.socks,
            Constants.localhost,
            port,
          );
        } else {
          await proxyManager.setAsSystemProxy(
            ProxyTypes.http,
            Constants.localhost,
            port,
          );
          await proxyManager.setAsSystemProxy(
            ProxyTypes.https,
            Constants.localhost,
            port,
          );
        }
        systemProxy = true;
      }
    } else if (Platform.isAndroid) {
      SocksVpnPlugin.startVpn(port);
      systemProxy = true;
    }
*/
  }

  /// 关闭代理
  @action
  Future<void> closeProxy() async {
    if (Constants.isDesktop) {
      if (await _request.patchConfigs(Config(tun: Tun(enable: false)))) {
        systemProxy = false;
      }
    } else if (Platform.isAndroid) {
      await CoreControl.stopVpn();
      systemProxy = false;
    }
/*
    if (Constants.isDesktop) {
      proxyManager.cleanSystemProxy();
    } else {
      SocksVpnPlugin.stopVpn();
    }
    systemProxy = false;
*/
  }
}
