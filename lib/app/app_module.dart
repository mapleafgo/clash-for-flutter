import 'package:clash_for_flutter/app/pages/index/index_module.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';

class AppModule extends Module {
  @override
  final List<Bind> binds = [
    Bind.singleton((_) => Request()),
    Bind.singleton<GlobalConfig>(
      (_) => GlobalConfig(),
      onDispose: (c) => c.dispose(),
    ),
  ];

  @override
  final List<ModularRoute> routes = [ModuleRoute("/", module: IndexModule())];
}
