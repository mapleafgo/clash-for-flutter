import 'package:clash_for_flutter/plugin/pac-proxy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:asuka/asuka.dart' as asuka;

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GlobalConfig _config = Modular.get<GlobalConfig>();
  bool _isOpen = false;
  bool _loading = false;

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

  click() {
    setState(() => _loading = true);
    changeStatus().catchError(
      (err) {
        print(err);
        asuka.showSnackBar(SnackBar(content: Text("初始化尚未完成，请稍后再试")));
      },
    ).then((_) => setState(() => _loading = false));
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
          child: _loading
              ? Container(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 5),
                  ),
                  width: 200,
                  height: 60,
                )
              : InkWell(
                  onTap: click,
                  child: Container(
                    child: Center(
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
                    ),
                    width: 200,
                    height: 60,
                  ),
                ),
        ),
      ),
    );
  }
}
