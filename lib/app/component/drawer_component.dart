import 'package:clash_for_flutter/app/pages/index/index_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class AppDrawer extends StatefulWidget {
  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _controller = Modular.get<IndexController>();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          DrawerHeader(
            padding: EdgeInsets.zero,
            child: Image.asset(
              "assets/darwer_img.jpg",
              filterQuality: FilterQuality.high,
              fit: BoxFit.fitWidth,
            ),
          ),
          ListTile(
            selected: _controller.currentIndex == 0,
            leading: Icon(Icons.home),
            title: Text("主页"),
            onTap: () {
              _controller.changePage(0);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            selected: _controller.currentIndex == 1,
            leading: Icon(Icons.cloud),
            title: Text("代理"),
            onTap: () {
              _controller.changePage(1);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            selected: _controller.currentIndex == 2,
            leading: Icon(Icons.code),
            title: Text("订阅"),
            onTap: () {
              _controller.changePage(2);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
