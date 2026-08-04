import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class Constants {
  static final isDesktop =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  static late Directory homeDir;

  static const sourceUrl = "https://github.com/mapleafgo/singcast";
  static const coreRepoUrl = "https://github.com/mapleafgo/singcast-cli";
  static const homeUrl = "https://mapleafgo.github.io/singcast";
  static const releaseUrl =
      "https://api.github.com/repos/mapleafgo/singcast/releases/latest";

  /// 与原生层(Android/iOS)通信的 MethodChannel 名，需与原生端注册名一致。
  static const methodChannelName = "cn.mapleafgo/singcast";

  static const profilesDir = "profiles";
  static const coreConfigFile = "config.json";
  static const appSettings = "settings.json";

  /// 磁贴专用缓存：只保存最近一次 TUN 启动配置，关闭 VPN 时不覆盖。
  static const tunConfigCache = "cache-tun.json";
  static const localhost = "127.0.0.1";
  static const defaultMixedPort = 7890;
  static const defaultApiAddr = "$localhost:9090";
  static const logsCapacity = 1000;
}

class Defaults {
  static const ruleSetProxy = "https://gh-proxy.org";
  static const delayTestUrl = "http://cp.cloudflare.com/generate_204";
  static String appVersion = '1.0.0';
  static String subUA = 'singcast/1.0.0 clash-meta';

  static const uaPresets = [
    'ClashforWindows/0.20.39',
    'clash-verge/v2.0.0',
    'clash-meta',
    'sing-box/1.13.14',
  ];

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
    subUA = 'singcast/$appVersion clash-meta';
  }
}
