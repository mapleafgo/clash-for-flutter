import 'dart:io';

import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/logs_subscription.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  final _config = Modular.get<GlobalConfig>();
  final _request = Modular.get<Request>();
  final _logs = Modular.get<LogsSubscription>();
  double _loadingProgress = 0;
  bool _isLoading = false;

  @override
  void initState() {
    _init();
    super.initState();
  }

  void _init() async {
    try {
      await _config.init();
      _request.init(Constants.rustAddr);
      var mmdb = File("${_config.configDir.path}${Constants.mmdb}");
      // 对新mmdb操作
      var mmdbNew = File("${_config.configDir.path}${Constants.mmdb_new}");
      if (mmdbNew.existsSync()) {
        mmdbNew.renameSync(mmdb.path);
      }

      if (!(await _config.verifyMMDB(mmdb.path) ?? false)) {
        setState(() => _isLoading = true);
        await _request
            .downFile(
              urlPath: _config.clashForMe.mmdbUrl,
              savePath: mmdb.path,
              onReceiveProgress: (received, total) {
                setState(() => _loadingProgress = received / total);
              },
            )
            .then((value) => setState(() => _isLoading = false));
      }

      // 启动服务
      if (await _config.start()) {
        _logs.startSubLogs(); // 启动日志订阅
        Modular.to.navigate("/tab");
      } else {
        Asuka.showSnackBar(const SnackBar(content: Text("启动服务失败")));
      }
    } catch (e) {
      Modular.to.navigate("/error");
      Asuka.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading ? LoadingWidget(value: _loadingProgress) : const RouterOutlet();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: const SysAppBar(title: Text("Clash for Flutter")),
      body: Center(
        child: SizedBox(
          height: 200,
          child: Flex(
            direction: Axis.vertical,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: size.width * 0.6,
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.black12,
                  minHeight: 10,
                ),
              ),
              const Text("正在初始下载 Country.mmdb 文件"),
            ],
          ),
        ),
      ),
    );
  }
}
