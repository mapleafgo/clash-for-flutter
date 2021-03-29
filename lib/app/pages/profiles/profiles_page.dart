import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:intl/intl.dart';
import 'package:mobx/mobx.dart';
import 'package:responsive_scaffold/templates/layout/scaffold.dart';

enum MenuType { Update, Remove, Rename }

/// 配置文件页
class ProfilesPage extends StatefulWidget {
  @override
  _ProfilesPageState createState() => _ProfilesPageState();
}

class _ProfilesPageState extends ModularState<ProfilesPage, ProfileController> {
  late List<ReactionDisposer> disposerList;

  download(String url) async {
    var loading = Loading.builder();
    asuka.addOverlay(loading);
    await controller.getNewProfile(url);
    loading.remove();
  }

  renameDialog(String file) => asuka.showDialog(builder: (dialogContext) {
        var textController = TextEditingController();
        return AlertDialog(
          title: Text("重命名"),
          content: TextField(
            controller: textController,
            onSubmitted: (value) {
              if (value.length == 0) return;
              Navigator.of(dialogContext).pop();
              controller.rename(file, value);
            },
          ),
          actions: [
            TextButton(
              child: Text("取消"),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              child: Text("确认"),
              onPressed: () {
                var value = textController.text;
                if (value.length == 0) return;
                Navigator.of(dialogContext).pop();
                controller.rename(file, value);
              },
            ),
          ],
        );
      });

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      kDesktopBreakpoint: 860,
      title: Text("订阅"),
      drawer: AppDrawer(),
      body: Container(
        child: Observer(
          builder: (_) {
            var profiles = controller.profiles;
            var selectedFile = controller.selectedFile;
            return ListView(
              children: profiles
                  .map((e) => ListTile(
                        title: Text(e.name),
                        subtitle: Text(
                          DateFormat("yyyy/MM/dd HH:mm").format(e.time),
                        ),
                        selected: e.file == selectedFile,
                        onTap: () => controller.select(e.file),
                        trailing: PopupMenuButton(
                          onSelected: (type) {
                            switch (type) {
                              case MenuType.Rename:
                                renameDialog(e.file);
                                break;
                              case MenuType.Update:
                                controller.updateProfile(e.file);
                                break;
                              case MenuType.Remove:
                                controller.removeProfile(e.file);
                                break;
                            }
                          },
                          itemBuilder: (_) => <PopupMenuEntry<MenuType>>[
                            PopupMenuItem(
                              child: Text("重命名"),
                              value: MenuType.Rename,
                            ),
                            PopupMenuItem(
                              child: Text("更新"),
                              value: MenuType.Update,
                            ),
                            PopupMenuItem(
                              child: Text("移除"),
                              value: MenuType.Remove,
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
          tooltip: "新增订阅",
          child: Icon(Icons.add),
          onPressed: () {
            asuka.showDialog(builder: (dialogContext) {
              var textController = TextEditingController();
              return StatefulBuilder(builder: (_, setDialogState) {
                return AlertDialog(
                  title: Text("订阅链接"),
                  content: TextField(
                    controller: textController,
                    onSubmitted: (value) {
                      if (value.length == 0) return;
                      Navigator.of(dialogContext).pop();
                      download(value);
                    },
                  ),
                  actions: [
                    FlatButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text("取消"),
                    ),
                    RaisedButton(
                      child: Text("确认"),
                      onPressed: () {
                        var value = textController.text;
                        if (value.length == 0) return;
                        Navigator.of(dialogContext).pop();
                        download(value);
                      },
                    ),
                  ],
                );
              });
            });
          }),
    );
  }
}
