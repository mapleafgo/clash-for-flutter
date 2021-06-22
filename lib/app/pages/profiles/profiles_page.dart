import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/bean/profile_bean.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:intl/intl.dart';
import 'package:mobx/mobx.dart';

enum MenuType { Update, Remove, Edit }

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

  edit(Profile profile) => asuka.showDialog(builder: (dialogContext) {
        var nameController = TextEditingController();
        var urlController = TextEditingController();
        nameController.text = profile.name;
        urlController.text = profile.url;
        return AlertDialog(
          title: Text("编辑"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(labelText: "名称"),
                controller: nameController,
              ),
              TextField(
                decoration: InputDecoration(labelText: "链接"),
                controller: urlController,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text("取消"),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              child: Text("确认"),
              onPressed: () {
                profile.url = urlController.text;
                profile.name = nameController.text;
                if (profile.name.length == 0 || profile.url.length == 0) return;
                Navigator.of(dialogContext).pop();
                controller.edit(profile);
              },
            ),
          ],
        );
      });

  upgradeProfile(String file) {
    setState(() => _loading = true);
    controller
        .updateProfile(file)
        .then(
          (_) => setState(() => _loading = false),
        )
        .catchError((err) {
      setState(() => _loading = false);
      asuka.showSnackBar(SnackBar(content: Text(err.message ?? "未知异常")));
    });
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
                                    case MenuType.Edit:
                                      edit(e);
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
                                    child: Text("编辑"),
                                    value: MenuType.Edit,
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
