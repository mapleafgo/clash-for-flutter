import 'package:flutter/material.dart';

class IndexController extends ChangeNotifier {
  int _status = 0;

  set status(int status) {
    _status = status;
    notifyListeners();
  }

  int get status => _status;
}
