import 'package:clash_for_flutter/app/pages/home/home_page.dart';
import 'package:clash_for_flutter/app/pages/index/index_controller.dart';
import 'package:clash_for_flutter/app/pages/index/index_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexModule extends ChildModule {
  @override
  List<Bind> get binds => [Bind((_) => IndexController())];

  @override
  List<ModularRouter> get routers => [
        ModularRouter("/", child: (_, __) => IndexPage()),
      ];
}
