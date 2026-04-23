import 'dart:io';

class Constants {
  static final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  static late final String rustAddr;
  static late final Directory homeDir;

  static const sourceUrl = "https://github.com/mapleafgo/clash-for-flutter";
  static const homeUrl = "https://mapleafgo.github.io/clash-for-flutter";
  static const releaseUrl = "https://api.github.com/repos/mapleafgo/clash-for-flutter/releases/latest";

  static const profilesPath = "/profiles";
  static const clashConfig = "/config.yaml";
  static const clashForMe = "/cfm.json";
  static const mmdb = "/Country.mmdb";
  static const mmdbNew = "/Country_new.mmdb";
  static const localhost = "127.0.0.1";
  static const logsCapacity = 1000;
}

class Defaults {
  static const mmdbUrl = "http://www.ideame.top/mmdb/Country.mmdb";
  static const delayTestUrl = "http://www.gstatic.com/generate_204";
}