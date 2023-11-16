import 'package:clash_for_flutter/app/pages/logs/logs_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class LogsModule extends Module {
  @override
  void routes(r) {
    r.child("/", child: (_) => const LogsPage());
  }
}
