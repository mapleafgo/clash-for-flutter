import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../exceptions/message_exception.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GlobalConfig _config = Modular.get<GlobalConfig>();
  bool _loading = false;

  click() async {
    setState(() => _loading = true);
    try {
      if (_config.systemProxy) {
        await _config.closeProxy();
      } else {
        await _config.openProxy();
      }
    } on MessageException catch (e) {
      asuka.showSnackBar(SnackBar(
        content: Text(
          e.getMessage(),
          style: TextStyle(fontFamily: "NotoSansCJK"),
        ),
      ));
    } catch (e) {
      asuka.showSnackBar(SnackBar(
        content: Text(
          "发生未知错误",
          style: TextStyle(fontFamily: "NotoSansCJK"),
        ),
      ));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Clash For Flutter"),
      ),
      drawer: Drawer(child: AppDrawer()),
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
