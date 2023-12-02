import 'package:asuka/asuka.dart' hide showDialog;
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/core_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 配置文件页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _config = Modular.get<AppConfig>();
  final _core = Modular.get<CoreConfig>();
  final _request = Modular.get<Request>();
  String _version = "1.2.0";

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = info.version);
      }
    });
  }

  void checkUpdate() async {
    _request.latest().then((value) {
      if (_version == value) {
        Asuka.showSnackBar(
          const SnackBar(content: Text('当前已经是最新版本！')),
        );
      } else {
        Asuka.showSnackBar(SnackBar(
          content: Text("最新版本号为: $value"),
          action: SnackBarAction(
            label: "前往下载最新版",
            onPressed: () => launchUrl(Uri.parse("${Constants.sourceUrl}/releases/latest")),
          ),
        ));
      }
    }).catchError((err) {});
  }

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
      _core.setState(mode: mode);
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
                  groupValue: _core.clash.mode ?? Mode.Rule,
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
      _core.setState(logLevel: logLevel);
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
  Widget build(context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text("设置")),
      body: Observer(builder: (_) {
        var redirPort = _core.clash.redirPort ?? 0;
        var tproxyPort = _core.clash.tproxyPort ?? 0;
        var mixedPort = _core.clash.mixedPort ?? 0;

        var allowLan = _core.clash.allowLan ?? false;
        var ipv6 = _core.clash.ipv6 ?? false;
        var mode = _core.clash.mode ?? Mode.Rule;
        var logLevel = _core.clash.logLevel ?? LogLevel.info;

        var mmdbUrl = _config.clashForMe.mmdbUrl;
        var delayTestUrl = _config.clashForMe.delayTestUrl;

        return SettingsList(
          platform: DevicePlatform.macOS,
          sections: [
            SettingsSection(
              title: const Text('Clash 代理端口'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  title: const Text('Http & Socks'),
                  value: Text(mixedPort.toString()),
                  onPressed: (_) {
                    setValue(
                      title: "Mixed",
                      initialValue: mixedPort.toString(),
                      onOk: (v) => _core.setState(mixedPort: int.parse(v)),
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
                      onOk: (v) => _core.setState(redirPort: int.parse(v)),
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
                      onOk: (v) => _core.setState(tproxyPort: int.parse(v)),
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
                  onToggle: (v) => _core.setState(allowLan: v),
                ),
                SettingsTile.switchTile(
                  title: const Text("IPv6"),
                  initialValue: ipv6,
                  onToggle: (v) => _core.setState(ipv6: v),
                ),
                SettingsTile.navigation(
                  title: const Text('代理模式'),
                  value: Text(mode.value),
                  onPressed: (_) => selectMode(),
                ),
                SettingsTile.navigation(
                  title: const Text('日志等级'),
                  value: Text(logLevel.value.toUpperCase()),
                  onPressed: (_) => selectLogLevel(),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('其他设置'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  title: const Row(
                    children: [
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
            SettingsSection(
              title: const Text("关于"),
              tiles: [
                SettingsTile.navigation(
                  title: const Text("官网"),
                  value: const Text(Constants.homeUrl, overflow: TextOverflow.ellipsis),
                  onPressed: (_) => launchUrl(Uri.parse(Constants.homeUrl)),
                ),
                SettingsTile.navigation(
                  title: const Text("开源地址"),
                  value: const Text(Constants.sourceUrl, overflow: TextOverflow.ellipsis),
                  onPressed: (_) => launchUrl(Uri.parse(Constants.sourceUrl)),
                ),
                SettingsTile.navigation(
                  title: const Text("版本号"),
                  value: Text(_version),
                  onPressed: (_) => checkUpdate(),
                ),
              ],
            )
          ],
        );
      }),
    );
  }
}

///MMDB 更新按钮
class MmdbRefreshButton extends StatefulWidget {
  const MmdbRefreshButton({super.key});

  @override
  State<MmdbRefreshButton> createState() => _MmdbRefreshButtonState();
}

class _MmdbRefreshButtonState extends State<MmdbRefreshButton> {
  final _config = Modular.get<AppConfig>();
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
    _request
        .downFile(
      urlPath: _config.clashForMe.mmdbUrl,
      savePath: "${Constants.homeDir.path}${Constants.mmdb}",
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
