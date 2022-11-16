import 'dart:developer';

import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  final GlobalConfig _config = Modular.get<GlobalConfig>();

  _InitPageState() {
    Modular.to.navigate("/loading");
  }

  @override
  void initState() {
    _init();
    super.initState();
  }

  void _init() async {
    try {
      await _config.init();
      if (_config.start()) {
        Modular.to.navigate("/tab");
      } else {
        Asuka.showSnackBar(const SnackBar(content: Text("启动服务失败")));
      }
    } catch (e) {
      if (kDebugMode) {
        log("初始化失败", error: e);
      }
      Modular.to.navigate("/error");
      Asuka.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const RouterOutlet();
  }
}
