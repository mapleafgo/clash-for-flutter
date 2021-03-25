import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_page.dart';

class ProfilesModule extends Module {
  @override
  final List<Bind> binds = [Bind.factory((_) => ProfileController())];

  @override
  final List<ModularRoute> routes = [
    ChildRoute("/", child: (_, __) => ProfilesPage()),
  ];
}
