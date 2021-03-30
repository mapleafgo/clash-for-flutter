import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:intl/intl.dart';
import 'package:mobx/mobx.dart';

enum MenuType { Update, Remove, Rename }

/// 配置文件页
class ProfilesPage extends StatefulWidget {
  @override
  _ProfilesPageState createState() => _ProfilesPageState();
}

class _ProfilesPageState extends ModularState<ProfilesPage, ProfileController> {
  bool _loading = false;
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

  upgradeProfile(String file) {
    setState(() => _loading = true);
    controller.updateProfile(file).then(
          (_) => setState(
            () => _loading = false,
          ),
        );
  }

  removeProfile(String file) {
    asuka.showSnackBar(SnackBar(
      content: Text("确定移除？"),
      action: SnackBarAction(
        label: "确定",
        onPressed: () => controller.removeProfile(file),
      ),
    ));
  }

  @override
  Widget build(_) {
    return Scaffold(
      appBar: AppBar(
        title: Text("订阅"),
      ),
      drawer: Drawer(child: AppDrawer()),
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
                        trailing: _loading
                            ? CircularProgressIndicator(
                                strokeWidth: 6,
                              )
                            : PopupMenuButton(
                                onSelected: (type) {
                                  switch (type) {
                                    case MenuType.Rename:
                                      renameDialog(e.file);
                                      break;
                                    case MenuType.Update:
                                      upgradeProfile(e.file);
                                      break;
                                    case MenuType.Remove:
                                      removeProfile(e.file);
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
            asuka.showDialog(builder: (cxt) {
              var textController = TextEditingController();
              return StatefulBuilder(builder: (_, setDialogState) {
                return AlertDialog(
                  title: Text("订阅链接"),
                  content: TextField(
                    controller: textController,
                    onSubmitted: (value) {
                      if (value.length == 0) return;
                      Navigator.of(cxt).pop();
                      download(value);
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(cxt).pop(),
                      child: Text("取消"),
                    ),
                    ElevatedButton(
                      child: Text("确认"),
                      onPressed: () {
                        var value = textController.text;
                        if (value.length == 0) return;
                        Navigator.of(cxt).pop();
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
