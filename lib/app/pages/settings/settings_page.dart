import 'dart:io';

import 'package:asuka/asuka.dart' hide showDialog;
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
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

        var allowLan = _config.clashConfig.allowLan ?? false;
        var ipv6 = _config.clashConfig.ipv6 ?? false;
        var mode = _config.clashConfig.mode ?? Mode.Rule;
        var logLevel = _config.clashConfig.logLevel ?? LogLevel.info;

        var mmdbUrl = _config.clashForMe.mmdbUrl;
        var delayTestUrl = _config.clashForMe.delayTestUrl;

        return SettingsList(
          platform: DevicePlatform.macOS,
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
                SettingsTile.switchTile(
                  title: const Text("允许局域网"),
                  initialValue: allowLan,
                  onToggle: (v) => _config.setState(allowLan: v),
                ),
                SettingsTile.switchTile(
                  title: const Text("IPv6"),
                  initialValue: ipv6,
                  onToggle: (v) => _config.setState(ipv6: v),
                ),
                SettingsTile.navigation(
                  title: const Text('代理模式'),
                  value: Text(mode.value),
                  onPressed: (_) => selectMode(),
                ),
                SettingsTile.navigation(
                  title: const Text('日志等级'),
                  value: Text(logLevel.value),
                  onPressed: (_) => selectLogLevel(),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('其他设置'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  title: Row(
                    children: const [
                      Text("MMDB Url"),
                      MmdbRefreshButton(),
                    ],
                  ),
                  value: Text(mmdbUrl),
                  onPressed: (_) {
                    setValue(
                      title: "MMDB Url",
                      decoration: DefaultConfigValue.mmdbUrl,
                      initialValue: mmdbUrl,
                      onOk: (v) => _config.setState(mmdbUrl: v),
                    );
                  },
                ),
                SettingsTile.navigation(
                  title: const Text("延迟测试Url"),
                  value: Text(delayTestUrl),
                  onPressed: (_) {
                    setValue(
                      title: "延迟测试Url",
                      decoration: DefaultConfigValue.delayTestUrl,
                      initialValue: delayTestUrl,
                      onOk: (v) => _config.setState(delayTestUrl: v),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

///MMDB 更新按钮
class MmdbRefreshButton extends StatefulWidget {
  const MmdbRefreshButton({Key? key}) : super(key: key);

  @override
  State<MmdbRefreshButton> createState() => _MmdbRefreshButtonState();
}

class _MmdbRefreshButtonState extends State<MmdbRefreshButton> {
  final _config = Modular.get<GlobalConfig>();
  final _request = Modular.get<Request>();

  double _value = 0;

  downloadMMDB() {
    if (_value > 0) {
      if (_value < 1) {
        Asuka.showSnackBar(const SnackBar(content: Text("下载中，请稍等")));
      } else {
        Asuka.showSnackBar(const SnackBar(content: Text("已下载完成，请重启应用以启用新的MMDB")));
      }
      return;
    }
    var mmdb = File("${_config.configDir.path}${Constants.mmdb_new}");
    _request
        .downFile(
      urlPath: _config.clashForMe.mmdbUrl,
      savePath: mmdb.path,
      receiveTimeout: 0,
      onReceiveProgress: (received, total) {
        setState(() => _value = received / total);
      },
    )
        .then((value) {
      setState(() => _value = 1);
      Asuka.showSnackBar(const SnackBar(content: Text("下载完成，请重启应用以启用新的MMDB")));
    }).catchError((e) {
      setState(() => _value = -1);
      Asuka.showSnackBar(SnackBar(content: Text(e.toString())));
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: "更新MMDB",
      icon: Builder(builder: (_) {
        if (_value == 0) {
          return const Icon(Icons.refresh_rounded);
        } else if (_value == 1) {
          return const Icon(Icons.done_outlined);
        } else if (_value == -1) {
          return const Icon(Icons.error_outlined);
        }
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: _value,
            backgroundColor: Colors.black12,
          ),
        );
      }),
      onPressed: () => downloadMMDB(),
    );
  }
}
