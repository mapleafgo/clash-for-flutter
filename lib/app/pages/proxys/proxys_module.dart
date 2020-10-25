import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/pages/proxys/model/proxys_model.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_controller.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_page.dart';

class ProxysModule extends ChildModule {
  @override
  List<Bind> get binds => [
        Bind((_) => ProxysController(), singleton: false),
        Bind((_) => ProxysModel()),
      ];

  @override
  List<ModularRouter> get routers => [
        ModularRouter("/", child: (_, __) => ProxysPage()),
      ];
}
