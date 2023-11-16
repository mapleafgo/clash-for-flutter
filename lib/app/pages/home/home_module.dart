import 'package:clash_for_flutter/app/pages/home/home_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class HomeModule extends Module {
  @override
  void routes(r) {
    r.child("/", child: (_) => const HomePage());
  }
}
