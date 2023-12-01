import 'dart:async';
import 'dart:io';

import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/tun_bean.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:clash_for_flutter/core_control.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:proxy_manager/proxy_manager.dart';

part 'global_config.g.dart';

class GlobalConfig = ConfigFileBase with _$GlobalConfig;

final proxyManager = ProxyManager();

abstract class ConfigFileBase with Store {
  final _request = Modular.get<Request>();
  static bool isStartClash = false;

  final String clashForMePath = "${Constants.homeDir.path}${Constants.clashForMe}";
  final String profilesPath = "${Constants.homeDir.path}${Constants.profilesPath}";

  @observable
  bool systemProxy = false;
  @observable
  ClashForMeConfig clashForMe = ClashForMeConfig.defaultConfig();

  Future<void> init() async {
    await _initConfig();
    await _initReaction();
  }

  @action
  _initConfig() async {
    ClashForMeConfig? tempCfm = ClashForMeConfig.formFile(clashForMePath);
    tempCfm = await _profilesInitCheck(tempCfm);
    if (tempCfm != null) {
      clashForMe = tempCfm;
    }
  }

  _initReaction() {
    reaction(
      (_) => clashForMe,
      (ClashForMeConfig config) => config.saveFile(clashForMePath),
      delay: 1000,
    );
    reaction(
      (_) => selectedFile,
      (String? file) {
        if (file == null) {
          return;
        }

        if (!File(file).isAbsolute) {
          file = "$profilesPath/$file";
        }
        _request.changeConfig(file);
      },
      fireImmediately: true,
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

  @action
  setState({
    String? selectedFile,
    List<ProfileBase>? profiles,
    String? mmdbUrl,
    String? delayTestUrl,
  }) {
    clashForMe = clashForMe.copyWith(
      selectedFile: selectedFile,
      profiles: profiles,
      mmdbUrl: mmdbUrl,
      delayTestUrl: delayTestUrl,
    );
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
