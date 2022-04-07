import 'dart:async';
import 'dart:developer';

import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/plugin/pac_proxy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

class InitPage extends StatefulWidget {
  @override
  _InitPageState createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  GlobalConfig _config = Modular.get<GlobalConfig>();

  _InitPageState() {
    Modular.to.navigate("/loading");
  }

  @override
  void initState() {
    Future.wait([_config.init(), PACProxy.init()]).then((_) {
      Modular.to.navigate("/tab");
    }).catchError((err) {
      print(err);
      Modular.to.navigate("/error");
      log("初始化失败", error: err);
      asuka.showSnackBar(SnackBar(content: Text(err.toString())));
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return RouterOutlet();
  }
}
