import 'package:clash_for_flutter/app/pages/index/index_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/app_widget.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';

class AppModule extends MainModule {
  @override
  List<Bind> get binds => [
        Bind((_) => GlobalConfig(), lazy: false),
        Bind((_) => Request(), lazy: false),
      ];

  @override
  Widget get bootstrap => AppWidget();

  @override
  List<ModularRouter> get routers => [
        ModularRouter("/", module: IndexModule()),
      ];
}
