import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
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
  bool _loading = false;

  click() {
    setState(() => _loading = true);
    Future(() async {
      if (_config.systemProxy) {
        await _config.closeProxy();
        return;
      }
      await _config.openProxy();
    }).catchError(
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
                    child: Observer(
                      builder: (_) => Center(
                        child: _config.systemProxy
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
