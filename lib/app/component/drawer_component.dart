import 'package:clash_for_flutter/app/bean/net_speed.dart';
import 'package:clash_for_flutter/app/pages/index/index_controller.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:go_flutter_clash/go_flutter_clash.dart';

class AppDrawer extends StatefulWidget {
  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _controller = Modular.get<IndexController>();

  NetSpeed _speed = NetSpeed();

  @override
  void initState() {
    super.initState();
    GoFlutterClash.trafficHandler((ret) {
      setState(() => _speed = JsonMapper.deserialize<NetSpeed>(ret));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        DrawerHeader(
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            image: DecorationImage(
                fit: BoxFit.fitWidth,
                image: AssetImage("assets/darwer_img.jpg")),
          ),
          child: Text("${_speed.up} / ${_speed.down}"),
        ),
        ListTile(
          selected: _controller.currentIndex == 0,
          leading: Icon(Icons.home),
          title: Text("主页"),
          onTap: () {
            _controller.changePage(0);
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        ListTile(
          selected: _controller.currentIndex == 1,
          leading: Icon(Icons.cloud),
          title: Text("代理"),
          onTap: () {
            _controller.changePage(1);
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        ListTile(
          selected: _controller.currentIndex == 2,
          leading: Icon(Icons.code),
          title: Text("订阅"),
          onTap: () {
            _controller.changePage(2);
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
      ],
    );
  }
}
