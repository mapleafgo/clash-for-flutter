import 'dart:io';

import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/exceptions/message_exception.dart';
import 'package:clash_for_flutter/app/source/core_config.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/logs_subscription.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:clash_for_flutter/core_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  final _config = Modular.get<AppConfig>();
  final _core = Modular.get<CoreConfig>();
  final _request = Modular.get<Request>();
  final _logs = Modular.get<LogsSubscription>();
  double _loadingProgress = 0;
  bool _isLoading = false;
  bool _isSuccess = false;

  @override
  void initState() {
    _init();
    super.initState();
  }

  void _init() async {
    try {
      if (!await _request.hello().then((res) => res.statusCode == HttpStatus.ok)) {
        throw MessageException("无法连接到内核，请重启尝试");
      }

      _core.init();
      await _config.init();

      var m = File("${Constants.homeDir.path}${Constants.mmdb}");
      if (!(await CoreControl.verifyMMDB(m.path) ?? false)) {
        setState(() => _isLoading = true);
        await _request
            .downFile(
              urlPath: _config.clashForMe.mmdbUrl,
              savePath: m.path,
              onReceiveProgress: (received, total) {
                setState(() => _loadingProgress = received / total);
              },
            )
            .then((value) => setState(() => _isLoading = false));
      }

      await _core.asyncConfig();
      // 已经开启tun直接跳转
      if (_config.tunIf && _core.tunEnable) {
        _isSuccess = true;
        return;
      }

      // 启动服务
      if (await _config.start()) {
        _isSuccess = true;
        return;
      }

      throw Exception("启动服务失败");
    } catch (e) {
      Modular.to.navigate("/error");
      Asuka.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (_isSuccess) {
        await _core.asyncConfig();
        _logs.startSubLogs(); // 启动日志订阅
        Modular.to.navigate("/tab");
      }
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
