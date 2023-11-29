import 'dart:async';
import 'dart:collection';

import 'package:clash_for_flutter/app/bean/log_bean.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';

/// 日志订阅
class LogsSubscription extends ChangeNotifier implements Disposable {
  final _request = Modular.get<Request>();
  final _config = Modular.get<GlobalConfig>();
  final Queue<LogData> _logQueue = Queue<LogData>();
  StreamSubscription? _subscription;

  List<LogData> get logList => _logQueue.toList();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void startSubLogs() {
    reaction((_) => _config.clashConfig.logLevel, (level) {
      _subscription?.cancel();
      _subscription = _request.logs(level).listen((event) {
        if (event == null) {
          return;
        }

        if (_logQueue.length >= Constants.logsCapacity) {
          _logQueue.removeFirst();
        }
        _logQueue.add(event);
        notifyListeners();
      });
    }, fireImmediately: true);
  }

  void clearLogs() {
    _logQueue.clear();
    notifyListeners();
  }
}
