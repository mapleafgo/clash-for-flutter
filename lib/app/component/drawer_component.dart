import 'package:clash_for_flutter/app/bean/net_speed.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:go_flutter_clash/go_flutter_clash.dart';

class AppDrawer extends StatefulWidget {
  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  NetSpeed _speed = NetSpeed();

  @override
  void initState() {
    super.initState();
    GoFlutterClash.trafficHandler((ret) {
      setState(
        () => _speed = JsonMapper.deserialize<NetSpeed>(ret) ?? NetSpeed(),
      );
    });
  }

  String format(int value) {
    double num = value.toDouble();
    var leval = 0;
    for (; num.compareTo(1024) > 0; leval++) {
      num /= 1024;
    }
    return "${num.toStringAsFixed(1)} ${DataUnit.values[leval].value}/s";
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
              image: AssetImage("assets/darwer_img.jpg"),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 6),
                decoration:
                    BoxDecoration(color: Color.fromARGB(180, 255, 255, 255)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "↑ ${format(_speed.up)} ┃ ↓ ${format(_speed.down)}",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
        ListTile(
          selected: Modular.to.modulePath.endsWith("/home"),
          leading: Icon(Icons.home),
          title: Text("主页"),
          onTap: () {
            Modular.to.navigate("/home");
            if (Modular.to.canPop()) {
              Modular.to.pop();
            }
          },
        ),
        ListTile(
          selected: Modular.to.modulePath.endsWith("/proxys"),
          leading: Icon(Icons.cloud),
          title: Text("代理"),
          onTap: () {
            Modular.to.navigate("/proxys");
            if (Modular.to.canPop()) {
              Modular.to.pop();
            }
          },
        ),
        ListTile(
          selected: Modular.to.modulePath.endsWith("/profiles"),
          leading: Icon(Icons.code),
          title: Text("订阅"),
          onTap: () {
            Modular.to.navigate("/profiles");
            if (Modular.to.canPop()) {
              Modular.to.pop();
            }
          },
        ),
      ],
    );
  }
}
