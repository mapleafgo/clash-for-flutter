import 'package:clash_for_flutter/app/pages/logs/logs_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class LogsModule extends Module {
  @override
  final List<Bind> binds = [];

  @override
  final List<ModularRoute> routes = [
    ChildRoute("/", child: (_, __) => const LogsPage()),
  ];
}
