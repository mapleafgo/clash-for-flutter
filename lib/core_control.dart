import 'dart:ffi';
import 'dart:io';

import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:clash_for_flutter/clash_generated_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

class CoreControl {
  static const MethodChannel _channel = MethodChannel('cn.mapleafgo/socks_vpn_plugin');
  static late final Clash _clash;

  // 初始化clash
  static void init() {
    if (!Constants.isDesktop) {
      return;
    }

    String fullPath = "";
    if (Platform.isWindows) {
      fullPath = "libclash.dll";
    } else if (Platform.isMacOS) {
      fullPath = "libclash.dylib";
    } else {
      fullPath = "libclash.so";
    }
    final lib = DynamicLibrary.open(fullPath);
    _clash = Clash(lib);
  }

  static Future<void> startVpn() {
    return _channel.invokeMethod('startVpn');
  }

  static Future<void> stopVpn() {
    return _channel.invokeMethod('stopVpn');
  }

  static Future<bool?> startService() {
    if (Constants.isDesktop) {
      return Future<bool>.sync(() => _clash.StartService() == 1);
    }
    return _channel.invokeMethod<bool>('startService');
  }

  static Future<bool?> setConfig(File config) {
    if (Constants.isDesktop) {
      return Future<bool>.sync(() => _clash.SetConfig(config.path.toNativeUtf8().cast()) == 1);
    }
    return _channel.invokeMethod<bool>('setConfig', {"config": config.path});
  }

  static Future<bool?> setHomeDir(Directory dir) {
    if (Constants.isDesktop) {
      return Future<bool>.sync(() => _clash.SetHomeDir(dir.path.toNativeUtf8().cast()) == 1);
    }
    return _channel.invokeMethod<bool>('setHomeDir', {"dir": dir.path});
  }

  static Future<String?> startRust(String addr) {
    if (Constants.isDesktop) {
      return Future<String>.sync(() => _clash.StartRust(addr.toNativeUtf8().cast()).cast<Utf8>().toDartString());
    }
    return _channel.invokeMethod<String>('startRust', {"addr": addr});
  }

  static Future<bool?> verifyMMDB(String path) {
    if (Constants.isDesktop) {
      return Future<bool>.sync(() => _clash.VerifyMMDB(path.toNativeUtf8().cast()) == 1);
    }
    return _channel.invokeMethod<bool>('verifyMMDB', {"path": path});
  }
}
