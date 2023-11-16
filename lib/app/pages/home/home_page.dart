import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/exceptions/message_exception.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

const btnSize = Size(200, 70);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalConfig _config = Modular.get<GlobalConfig>();
  bool _loading = false;

  click() {
    setState(() => _loading = true);
    Future(() {
      if (_config.systemProxy) {
        return _config.closeProxy();
      } else {
        return _config.openProxy();
      }
    }).catchError((e) {
      if (e is MessageException) {
        Asuka.showSnackBar(SnackBar(content: Text(e.getMessage())));
      } else {
        Asuka.showSnackBar(const SnackBar(content: Text("发生未知错误")));
      }
    }).then((_) => setState(() => _loading = false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text("Clash For Flutter")),
      body: Center(
        child: _loading
            ? const LoadingButton()
            : Observer(
                builder: (_) {
                  if (_config.systemProxy) {
                    return OffButton(onTap: click);
                  } else {
                    return OnButton(onTap: click);
                  }
                },
              ),
      ),
    );
  }
}

class OnButton extends StatelessWidget {
  final Function() onTap;

  const OnButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    var themeData = Theme.of(context);
    return Card(
      color: Colors.white54,
      child: SizedBox.fromSize(
        size: btnSize,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.flight_takeoff_rounded,
                size: 36,
                color: themeData.primaryTextTheme.headlineMedium?.color,
              ),
              Container(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  "开启",
                  style: themeData.primaryTextTheme.headlineMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OffButton extends StatelessWidget {
  final Function() onTap;

  const OffButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    var themeData = Theme.of(context);
    return Card(
      color: themeData.primaryColor,
      child: SizedBox.fromSize(
        size: btnSize,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.flight_land_rounded,
                size: 36,
                color: themeData.primaryTextTheme.headlineMedium?.color,
              ),
              Container(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  "关闭",
                  style: themeData.primaryTextTheme.headlineMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingButton extends StatelessWidget {
  const LoadingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white54,
      child: SizedBox.fromSize(
        size: btnSize,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 5),
        ),
      ),
    );
  }
}
