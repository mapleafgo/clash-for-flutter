import 'package:clash_for_flutter/app/pages/index/index_controller.dart';
import 'package:clash_for_flutter/app/pages/index/index_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexModule extends Module {
  @override
  final List<Bind> binds = [Bind.factory((_) => IndexController())];

  @override
  final List<ModularRoute> routes = [
    ChildRoute("/", child: (_, __) => IndexPage()),
  ];
}
