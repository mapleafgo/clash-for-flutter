import 'dart:io';
import 'dart:math';

import 'package:clash_for_flutter/app/app_module.dart';
import 'package:clash_for_flutter/app/app_widget.dart';
import 'package:clash_for_flutter/app/utils/clash_custom_messages.dart';
import 'package:clash_for_flutter/core_control.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:dart_json_mapper_mobx/dart_json_mapper_mobx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:window_manager/window_manager.dart';
import 'package:clash_for_flutter/app/bean/config_bean.dart';

import 'app/utils/constants.dart';
import 'main.mapper.g.dart' show initializeJsonMapper;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  initializeJsonMapper(adapters: [mobXAdapter]);
  JsonMapper().useAdapter(JsonMapperAdapter(valueDecorators: {
    typeOf<Map<String, String>>(): (value) {
      return Map.castFrom<dynamic, dynamic, String, String>(value);
    },
  }));

  if (Constants.isDesktop) {
    await windowManager.ensureInitialized();
    if (!Platform.isLinux) {
      await protocolHandler.register('clash');
    }

    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(460, 600),
      size: Size(900, 650),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  timeago.setLocaleMessages('zh_cn', ClashCustomMessages());

  // 初始化 Clash
  CoreControl.init();
  await getApplicationSupportDirectory().then((dir) => Constants.homeDir = dir);
  // 设置主目录
  await CoreControl.setHomeDir(Constants.homeDir);
  // 创建默认配置文件
  if (!(Config.fileExist() ?? false)) {
    await Config.defaultConfig().saveFile();
  }
  // 启动 rust 控制服务，端口随机
  await CoreControl.startRust("${Constants.localhost}:${Random().nextInt(9999) + 10000}")
      .then((addr) => Constants.rustAddr = addr ?? "");
  // 启动内核
  await CoreControl.startService();

  runApp(ModularApp(
    module: AppModule(),
    child: const AppWidget(),
  ));
}
