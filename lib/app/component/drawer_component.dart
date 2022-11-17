import 'dart:convert';

import 'package:clash_for_flutter/app/bean/net_speed.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:easy_sidemenu/easy_sidemenu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class AppDrawer extends StatefulWidget {
  final PageController page;

  const AppDrawer({Key? key, required this.page}) : super(key: key);

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _request = Modular.get<Request>();
  NetSpeed _speed = NetSpeed();

  @override
  void initState() {
    super.initState();
    _request.traffic().then((value) {
      value?.listen((event) => setState(() => _speed =
          JsonMapper.deserialize<NetSpeed>(utf8.decode(event)) ?? NetSpeed()));
    });
  }

  String format(int value) {
    double num = value.toDouble();
    var level = 0;
    for (; num.compareTo(1024) > 0; level++) {
      num /= 1024;
    }
    return "${num.toStringAsFixed(1)} ${DataUnit.values[level].value}/s";
  }

  @override
  Widget build(BuildContext context) {
    return SideMenu(
        controller: widget.page,
        style: SideMenuStyle(
          openSideMenuWidth: 200,
          unselectedTitleTextStyle: Theme.of(context).textTheme.button,
          selectedTitleTextStyle: Theme.of(context).primaryTextTheme.button,
          selectedIconColor: Theme.of(context).primaryTextTheme.button!.color,
          selectedColor: Theme.of(context).primaryColor,
          hoverColor: Theme.of(context).hoverColor,
        ),
        title: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 200,
                maxWidth: 200,
              ),
              child: const Image(image: AssetImage("assets/darwer_img.jpg")),
            ),
            const Divider(indent: 8.0, endIndent: 8.0),
          ],
        ),
        footer: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            "↑ ${format(_speed.up)}\n↓ ${format(_speed.down)}",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        items: [
          SideMenuItem(
            priority: 0,
            title: "主页",
            icon: const Icon(Icons.home),
            onTap: () => widget.page.jumpToPage(0),
          ),
          SideMenuItem(
            priority: 1,
            title: "代理",
            icon: const Icon(Icons.cloud),
            onTap: () => widget.page.jumpToPage(1),
          ),
          SideMenuItem(
            priority: 2,
            title: "订阅",
            icon: const Icon(Icons.code),
            onTap: () => widget.page.jumpToPage(2),
          ),
          SideMenuItem(
            priority: 3,
            title: "设置",
            icon: const Icon(Icons.settings),
            onTap: () => widget.page.jumpToPage(3),
          ),
        ]);
  }
}
