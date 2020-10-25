import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_page.dart';

class ProfilesModule extends ChildModule {
  @override
  List<Bind> get binds => [
        Bind((_) => ProfileController(), singleton: false),
      ];

  @override
  List<ModularRouter> get routers => [
        ModularRouter("/", child: (_, __) => ProfilesPage()),
      ];
}
