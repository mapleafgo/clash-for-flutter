import 'package:clash_for_flutter/app/pages/index/index_module.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/core_config.dart';
import 'package:clash_for_flutter/app/source/logs_subscription.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:flutter_modular/flutter_modular.dart';

class AppModule extends Module {
  @override
  void binds(i) {
    i.addSingleton(Request.new);
    i.addSingleton(LogsSubscription.new);
    i.addSingleton(AppConfig.new);
    i.addSingleton(CoreConfig.new);
  }

  @override
  void routes(r) {
    r.module("/", module: IndexModule());
  }
}
