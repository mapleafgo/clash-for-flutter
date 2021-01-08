import 'dart:typed_data';

import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/utils/constant.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:go_flutter_systray/go_flutter_systray.dart';
import 'package:go_flutter_systray/model/menu_item.dart';
import 'package:asuka/asuka.dart' as asuka;

class AppWidget extends StatefulWidget {
  @override
  _AppWidgetState createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> {
  final _config = Modular.get<GlobalConfig>();

  @override
  void initState() {
    GoFlutterSystray.initSystray();
    rootBundle
        .load("assets/icon.ico")
        .then((file) => Uint8List.view(file.buffer))
        .then((icon) async {
      var menu = MenuItem.main(
        icon: icon,
        title: "ClashForFlutter",
        tooltip: "ClashForFlutter",
        child: [
          MenuItem(key: Constant.systrayWinKey, title: "显示窗口", tooltip: "显示窗口"),
          MenuItem.separator(),
          MenuItem(
            key: Constant.systrayProxyKey,
            title: "代理",
            tooltip: "代理",
            isCheckbox: true,
          ),
          MenuItem.separator(),
          MenuItem(
            key: GoFlutterSystray.quitCallMethod,
            title: "退出",
            tooltip: "退出",
          ),
        ],
      );
      await GoFlutterSystray.runSystray(menu);
      GoFlutterSystray.registerCallBack(
        GoFlutterSystray.quitCallMethod,
        GoFlutterSystray.exitWindow,
      );
      GoFlutterSystray.registerCallBack(
        Constant.systrayWinKey,
        GoFlutterSystray.showWindow,
      );
      GoFlutterSystray.registerCallBack(
        Constant.systrayProxyKey,
        () => Future(() {
          if (_config.systemProxy) {
            _config.closeProxy();
            return;
          }
          _config.openProxy();
        }).catchError((err) => print(err)),
      );
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(fontFamily: "NotoSansCJK"),
        locale: DevicePreview.locale(context),
        initialRoute: "/",
        builder: (ctx, w) {
          // return DevicePreview.appBuilder(ctx, w);
          return asuka.builder(ctx, w);
        },
        navigatorKey: Modular.navigatorKey,
        onGenerateRoute: Modular.generateRoute,
      );
}
