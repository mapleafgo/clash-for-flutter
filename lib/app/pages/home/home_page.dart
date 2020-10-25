import 'package:clash_for_flutter/plugin/pac-proxy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GlobalConfig _config = Modular.get<GlobalConfig>();
  bool _isOpen = false;

  Future<void> changeStatus() async {
    bool isOpen;
    if (_isOpen) {
      await PACProxy.close();
      isOpen = false;
    } else {
      await _config.start();
      await PACProxy.open("7890");
      isOpen = true;
    }
    setState(() => _isOpen = isOpen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Clash For Flutter"),
      ),
      drawer: AppDrawer(),
      body: Center(
        child: Card(
          elevation: 1,
          child: InkWell(
            onTap: changeStatus,
            child: Container(
              child: _isOpen
                  ? Text(
                      "关闭",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    )
                  : Text(
                      "开启",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
              padding: EdgeInsets.fromLTRB(100, 20, 100, 20),
            ),
          ),
        ),
      ),
    );
  }
}
