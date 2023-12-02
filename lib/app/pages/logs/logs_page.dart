import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/core_config.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/logs_subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:intl/intl.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _controller = ScrollController();
  final _config = Modular.get<AppConfig>();
  final _core = Modular.get<CoreConfig>();
  final _logs = Modular.get<LogsSubscription>();
  bool _showFab = true;

  @override
  void initState() {
    super.initState();
    _logs.addListener(_logsListener);
    _controller.addListener(_scrollListener);
    // 初始时跳转到最底部，不带动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _logs.removeListener(_logsListener);
    _controller.dispose();
    super.dispose();
  }

  void _logsListener() {
    // 等待组件渲染完成再滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollListener() {
    if (_controller.position.userScrollDirection == ScrollDirection.reverse && _showFab) {
      setState(() => _showFab = false);
    }
    if (_controller.position.userScrollDirection == ScrollDirection.forward && !_showFab) {
      setState(() => _showFab = true);
    }
  }

  levelAction() {
    change(LogLevel? level, BuildContext context) {
      _core.setState(logLevel: level);
      Navigator.of(context).pop();
    }

    Asuka.showModalBottomSheet(
      backgroundColor: Colors.transparent,
      builder: (cxt) => Material(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        elevation: 7,
        child: SizedBox(
          height: LogLevel.values.length * 50,
          child: ListView.builder(
            itemCount: LogLevel.values.length,
            itemBuilder: (_, i) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                onTap: () => change(LogLevel.values[i], cxt),
                title: Text(LogLevel.values[i].value.toUpperCase()),
                trailing: Radio<LogLevel>(
                  value: LogLevel.values[i],
                  groupValue: _core.clash.logLevel ?? LogLevel.info,
                  onChanged: (v) => change(v, cxt),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logsSub = context.watch<LogsSubscription>();
    return Scaffold(
      appBar: SysAppBar(
        title: const Text("日志"),
        actions: [
          IconButton(
            tooltip: "日志等级",
            icon: const Icon(Icons.sort),
            onPressed: levelAction,
          ),
        ],
      ),
      body: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).primaryColor.withAlpha(20),
        ),
        child: ListView.builder(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: logsSub.logList.length,
          itemBuilder: (BuildContext context, int index) {
            var data = logsSub.logList[index];
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                "[${DateFormat("yyyy/MM/dd HH:mm:ss").format(data.time!)}] [${data.type.value.toUpperCase()}] ${data.payload}",
              ),
            );
          },
        ),
      ),
      floatingActionButton: _showFab
          ? FloatingActionButton(
              tooltip: "清理",
              child: const Icon(Icons.clear_all),
              onPressed: () => _logs.clearLogs(),
            )
          : null,
    );
  }
}
