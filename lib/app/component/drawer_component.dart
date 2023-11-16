import 'dart:async';

import 'package:clash_for_flutter/app/bean/net_speed.dart';
import 'package:clash_for_flutter/app/pages/router.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/utils.dart';
import 'package:easy_sidemenu/easy_sidemenu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class AppDrawer extends StatefulWidget {
  final PageController page;

  const AppDrawer({super.key, required this.page});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _request = Modular.get<Request>();
  final SideMenuController _smc = SideMenuController();
  NetSpeed _speed = NetSpeed();
  String _clashVersion = "-";
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _smc.addListener((p0) => widget.page.jumpToPage(p0));
    _subscription = _request.traffic().listen((event) {
      setState(() => _speed = event ?? NetSpeed());
    });
    _request.getClashVersion().then((value) => setState(() => _clashVersion = value ?? _clashVersion));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _smc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var themeData = Theme.of(context);
    return SideMenu(
      controller: _smc,
      style: SideMenuStyle(
        openSideMenuWidth: 200,
        unselectedTitleTextStyle: themeData.textTheme.labelLarge,
        selectedTitleTextStyle: themeData.primaryTextTheme.labelLarge,
        selectedIconColor: themeData.primaryTextTheme.labelLarge!.color,
        selectedColor: themeData.primaryColor,
        hoverColor: themeData.hoverColor,
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
      footer: SizedBox(
        height: 75,
        child: Column(
          children: [
            Text(
              "↑ ${dataformat(_speed.up)}/s\n↓ ${dataformat(_speed.down)}/s",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              child: Text(
                "Clash: $_clashVersion",
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
      items: menu.sideMenuList,
    );
  }
}
