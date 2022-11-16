import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/exceptions/message_exception.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalConfig _config = Modular.get<GlobalConfig>();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
  }

  click() async {
    setState(() => _loading = true);
    try {
      if (_config.systemProxy) {
        await _config.closeProxy();
      } else {
        await _config.openProxy();
      }
    } on MessageException catch (e) {
      Asuka.showSnackBar(SnackBar(content: Text(e.getMessage())));
    } catch (e) {
      Asuka.showSnackBar(const SnackBar(content: Text("发生未知错误")));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
        title: Text("Clash For Flutter"),
      ),
      body: Center(
        child: Card(
          elevation: 1,
          child: _loading
              ? const SizedBox(
                  width: 200,
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 5),
                  ),
                )
              : InkWell(
                  onTap: click,
                  child: SizedBox(
                    width: 200,
                    height: 60,
                    child: Observer(
                      builder: (_) => Center(
                        child: _config.systemProxy
                            ? const Text(
                                "关闭",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              )
                            : const Text(
                                "开启",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
