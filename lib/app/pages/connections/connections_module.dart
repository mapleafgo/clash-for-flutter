import 'package:clash_for_flutter/app/pages/connections/connections_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ConnectionsModule extends Module {
  @override
  final List<Bind> binds = [];

  @override
  final List<ModularRoute> routes = [
    ChildRoute("/", child: (_, __) => const ConnectionsPage()),
  ];
}
