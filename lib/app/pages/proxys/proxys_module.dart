import 'package:clash_for_flutter/app/pages/proxys/model/proxys_model.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_controller.dart';
import 'package:clash_for_flutter/app/pages/proxys/proxys_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ProxysModule extends Module {
  @override
  void binds(i) {
    i.addSingleton(ProxysModel.new);
    i.add(ProxysController.new);
  }

  @override
  void routes(r) {
    r.child("/", child: (_) => const ProxysPage());
  }
}
