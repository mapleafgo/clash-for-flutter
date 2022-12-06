import 'dart:io';

import 'package:clash_for_flutter/app/app_module.dart';
import 'package:clash_for_flutter/app/app_widget.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:dart_json_mapper_mobx/dart_json_mapper_mobx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:window_manager/window_manager.dart';

import 'main.mapper.g.dart' show initializeJsonMapper;

void main() async {
  initializeJsonMapper(adapters: [mobXAdapter]);
  JsonMapper().useAdapter(JsonMapperAdapter(valueDecorators: {
    typeOf<Map<String, String>>(): (value) {
      return Map.castFrom<dynamic, dynamic, String, String>(value);
    },
  }));

  WidgetsFlutterBinding.ensureInitialized();
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

  runApp(ModularApp(
    module: AppModule(),
    child: const AppWidget(),
  ));
}
