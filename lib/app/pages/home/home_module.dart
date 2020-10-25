import 'package:clash_for_flutter/app/pages/home/home_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class HomeModule extends ChildModule {
  @override
  List<Bind> get binds => [];

  @override
  List<ModularRouter> get routers => [
        ModularRouter("/", child: (_, __) => HomePage()),
      ];
}
