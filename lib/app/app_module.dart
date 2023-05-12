import 'package:clash_for_flutter/app/pages/index/index_module.dart';
import 'package:clash_for_flutter/app/source/logs_subscription.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';

class AppModule extends Module {
  @override
  final List<Bind> binds = [
    Bind.singleton((_) => Request()),
    Bind.singleton((_) => LogsSubscription()),
    Bind.singleton((_) => GlobalConfig()),
  ];

  @override
  final List<ModularRoute> routes = [ModuleRoute("/", module: IndexModule())];
}
