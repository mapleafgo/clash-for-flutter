import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexController extends ChangeNotifier {
  var router = RouterOutletListController();
  int currentIndex = 0;

  IndexController() {
    router.listen((value) {
      currentIndex = value;
      notifyListeners();
    });
  }

  changePage(int page) => router.changeModule(page);
}
