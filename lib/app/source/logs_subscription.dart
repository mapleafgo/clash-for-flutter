import 'dart:async';

import 'package:clash_for_flutter/app/bean/log_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class LogsSubscription extends ChangeNotifier implements Disposable {
  final _request = Modular.get<Request>();
  final _config = Modular.get<GlobalConfig>();
  final List<LogData> _logList = [];
  StreamSubscription? _subscription;

  List<LogData> get logList => _logList;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void startSubLogs() {
    _subscription?.cancel();
    _subscription = _request.logs(_config.clashConfig.logLevel ?? LogLevel.info).listen((event) {
      if (event == null) {
        return;
      }

      if (_logList.length >= 1000) {
        _logList.removeAt(0);
      }
      _logList.add(event);
      notifyListeners();
    });
  }

  void clearLogs() => _logList.clear();
}
