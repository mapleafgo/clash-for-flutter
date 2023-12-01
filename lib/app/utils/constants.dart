import 'dart:io';

/// 常量类
class Constants {
  static final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// rust 控制服务地址
  static late final String rustAddr;

  /// 配置目录
  static late final Directory homeDir;

  /// 开源地址
  static const sourceUrl = "https://github.com/mapleafgo/clash-for-flutter";

  /// 官网
  static const homeUrl = "https://mapleafgo.github.io/clash-for-flutter";

  /// 检测最新版本
  static const releaseUrl = "https://api.github.com/repos/mapleafgo/clash-for-flutter/releases/latest";

  /// 下载的配置文件路径
  static const profilesPath = "/profiles";

  /// clash的配置
  static const clashConfig = "/config.yaml";

  /// 该程序的一些配置
  static const clashForMe = "/cfm.json";

  /// mmdb 保存路径
  static const mmdb = "/Country.mmdb";

  /// mmdb 更新保存路径
  static const mmdb_new = "/Country_new.mmdb";

  /// localhost
  static const localhost = "127.0.0.1";

  /// 日志最大容量
  static const logsCapacity = 1000;
}

/// 默认配置值
class DefaultConfigValue {
  static const mmdbUrl = "http://www.ideame.top/mmdb/Country.mmdb";

  static const delayTestUrl = "http://www.gstatic.com/generate_204";
}
