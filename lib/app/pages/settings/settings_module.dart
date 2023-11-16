import 'package:clash_for_flutter/app/pages/settings/settings_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class SettingsModule extends Module {
  @override
  void routes(r) {
    r.child("/", child: (_) => const SettingsPage());
  }
}
