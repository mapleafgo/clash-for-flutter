import 'package:clash_for_flutter/app/pages/connections/connections_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ConnectionsModule extends Module {
  @override
  void routes(r) {
    r.child("/", child: (_) => const ConnectionsPage());
  }
}
