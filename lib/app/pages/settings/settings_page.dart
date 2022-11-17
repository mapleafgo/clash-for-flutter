import 'package:asuka/asuka.dart' hide showDialog;
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:settings_ui/settings_ui.dart';

/// 配置文件页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _config = Modular.get<GlobalConfig>();

  setValue({
    required String title,
    String? initialValue,
    String? decoration,
    required void Function(String) onOk,
  }) {
    showDialog(
      context: context,
      builder: (cxt) {
        var vController = TextEditingController();
        vController.text = initialValue ?? "";
        return AlertDialog(
          elevation: 7,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(labelText: decoration),
                controller: vController,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text("取消"),
              onPressed: () => Navigator.of(cxt).pop(),
            ),
            TextButton(
              child: const Text("确认"),
              onPressed: () {
                var value = vController.text;
                if (value.isEmpty) return;
                Navigator.of(cxt).pop();
                onOk(value);
              },
            ),
          ],
        );
      },
    );
  }

  selectMode() {
    change(Mode? mode, BuildContext context) {
      _config.setState(mode: mode);
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
          height: Mode.values.length * 50,
          child: ListView.builder(
            itemCount: Mode.values.length,
            itemBuilder: (_, i) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                onTap: () => change(Mode.values[i], cxt),
                title: Text(Mode.values[i].value),
                trailing: Radio<Mode>(
                  value: Mode.values[i],
                  groupValue: _config.clashConfig.mode ?? Mode.Rule,
                  onChanged: (v) => change(v, cxt),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  selectLogLevel() {
    change(LogLevel? logLevel, BuildContext context) {
      _config.setState(logLevel: logLevel);
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
                title: Text(LogLevel.values[i].value),
                trailing: Radio<LogLevel>(
                  value: LogLevel.values[i],
                  groupValue: _config.clashConfig.logLevel ?? LogLevel.info,
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
  Widget build(context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text("设置")),
      body: Observer(builder: (_) {
        var port = _config.clashConfig.port ?? 0;
        var socksPort = _config.clashConfig.socksPort ?? 0;
        var redirPort = _config.clashConfig.redirPort ?? 0;
        var tproxyPort = _config.clashConfig.tproxyPort ?? 0;
        var mixedPort = _config.clashConfig.mixedPort ?? 0;
        return SettingsList(
          sections: [
            SettingsSection(
              title: const Text('Clash 代理端口'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  title: const Text('Http & Https'),
                  value: Text(port.toString()),
                  onPressed: (_) {
                    setValue(
                      title: "Http & Https",
                      initialValue: port.toString(),
                      onOk: (v) => _config.setState(port: int.parse(v)),
                    );
                  },
                ),
                SettingsTile.navigation(
                  title: const Text('Socks'),
                  value: Text(socksPort.toString()),
                  onPressed: (_) {
                    setValue(
                      title: "Socks",
                      initialValue: socksPort.toString(),
                      onOk: (v) => _config.setState(socksPort: int.parse(v)),
                    );
                  },
                ),
                SettingsTile.navigation(
                  title: const Text('Redir'),
                  value: Text(redirPort.toString()),
                  onPressed: (_) {
                    setValue(
                      title: "Redir",
                      initialValue: redirPort.toString(),
                      onOk: (v) => _config.setState(redirPort: int.parse(v)),
                    );
                  },
                ),
                SettingsTile.navigation(
                  title: const Text('Tproxy'),
                  value: Text(tproxyPort.toString()),
                  onPressed: (_) {
                    setValue(
                      title: "Tproxy",
                      initialValue: tproxyPort.toString(),
                      onOk: (v) => _config.setState(tproxyPort: int.parse(v)),
                    );
                  },
                ),
                SettingsTile.navigation(
                  title: const Text('Mixed'),
                  value: Text(mixedPort.toString()),
                  onPressed: (_) {
                    setValue(
                      title: "Mixed",
                      initialValue: mixedPort.toString(),
                      onOk: (v) => _config.setState(mixedPort: int.parse(v)),
                    );
                  },
                ),
              ],
            ),
            SettingsSection(
              title: const Text('Clash 设置'),
              tiles: <SettingsTile>[
                SettingsTile(
                  title: const Text("允许局域网"),
                  trailing: Switch(
                    value: _config.clashConfig.allowLan ?? false,
                    onChanged: (v) => _config.setState(allowLan: v),
                  ),
                ),
                SettingsTile(
                  title: const Text("IPv6"),
                  trailing: Switch(
                    value: _config.clashConfig.ipv6 ?? false,
                    onChanged: (v) => _config.setState(ipv6: v),
                  ),
                ),
                SettingsTile.navigation(
                  title: const Text('代理模式'),
                  value: Text((_config.clashConfig.mode ?? Mode.Rule).value),
                  onPressed: (_) => selectMode(),
                ),
                SettingsTile.navigation(
                  title: const Text('日志等级'),
                  value: Text(
                      (_config.clashConfig.logLevel ?? LogLevel.info).value),
                  onPressed: (_) => selectLogLevel(),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
