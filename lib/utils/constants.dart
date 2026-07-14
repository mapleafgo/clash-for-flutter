import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class Constants {
  static final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  static late final Directory homeDir;

  static const sourceUrl = "https://github.com/mapleafgo/singcast";
  static const homeUrl = "https://mapleafgo.github.io/singcast";
  static const releaseUrl = "https://api.github.com/repos/mapleafgo/singcast/releases/latest";

  static const profilesDir = "profiles";
  static const clashConfig = "config.yaml";
  static const appSettings = "settings.json";
  static const mergedConfigCache = "cache-merged.yaml";
  static const localhost = "127.0.0.1";
  static const defaultMixedPort = 7890;
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
  ];

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
    subUA = 'singcast/$appVersion clash-meta';
  }
}
