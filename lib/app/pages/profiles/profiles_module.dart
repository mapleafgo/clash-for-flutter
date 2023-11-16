import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ProfilesModule extends Module {
  @override
  void binds(i) {
    i.add(ProfileController.new);
  }

  @override
  void routes(r) {
    r.child("/", child: (_) => const ProfilesPage());
  }
}
