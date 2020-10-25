import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexController {
  var router = RouterOutletListController();
  List<ValueChanged<int>> changeNotifier = [];
  int currentIndex = 0;

  IndexController() {
    router.listen((value) {
      currentIndex = value;
      changeNotifier.forEach((element) => element(value));
    });
  }

  changePage(int page) => router.changeModule(page);

  addNotifiler(ValueChanged<int> notifiler) {
    changeNotifier.add(notifiler);
  }

  removeNotifiler(ValueChanged<int> notifiler) {
    changeNotifier.remove(notifiler);
  }
}
