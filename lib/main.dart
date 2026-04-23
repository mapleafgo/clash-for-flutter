import 'dart:io';
import 'dart:math';

import 'package:clash_for_flutter/presentation/app.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:clash_for_flutter/core_control.dart' as core;
import 'package:clash_for_flutter/data/local/core_config_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Constants.isDesktop) {
    await windowManager.ensureInitialized();
    if (!Platform.isLinux) await protocolHandler.register('clash');
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        minimumSize: Size(460, 600),
        size: Size(900, 650),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  timeago.setLocaleMessages('zh_cn', TimeagoZhCnMessages());

  core.CoreControl.init();
  Constants.homeDir = await getApplicationSupportDirectory();
  await core.CoreControl.setHomeDir(Constants.homeDir);

  CoreConfigStorage.createDefault();

  final addr = '${Constants.localhost}:${Random().nextInt(9999) + 10000}';
  Constants.rustAddr =
      await core.CoreControl.startRust(addr) ?? '';
  await core.CoreControl.startService();

  runApp(const App());
}

class TimeagoZhCnMessages extends timeago.LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => '';
  @override
  String suffixAgo() => '前';
  @override
  String suffixFromNow() => '后';
  @override
  String lessThanOneMinute(int seconds) => '刚刚';
  @override
  String aboutAMinute(int minutes) => '1 分钟';
  @override
  String minutes(int minutes) => '$minutes 分钟';
  @override
  String aboutAnHour(int minutes) => '1 小时';
  @override
  String hours(int hours) => '$hours 小时';
  @override
  String aDay(int hours) => '1 天';
  @override
  String days(int days) => '$days 天';
  @override
  String aboutAMonth(int days) => '1 个月';
  @override
  String months(int months) => '$months 个月';
  @override
  String aboutAYear(int year) => '1 年';
  @override
  String years(int years) => '$years 年';
  @override
  String wordSeparator() => '';
}
