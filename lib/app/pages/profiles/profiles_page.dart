import 'dart:math';

import 'package:asuka/asuka.dart' as asuka;
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_file_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:intl/intl.dart';
import 'package:mobx/mobx.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

enum MenuType { Update, Remove, Edit }

/// 配置文件页
class ProfilesPage extends StatefulWidget {
  @override
  _ProfilesPageState createState() => _ProfilesPageState();
}

class _ProfilesPageState extends ModularState<ProfilesPage, ProfileController> {
  bool _loading = false;
  late List<ReactionDisposer> disposerList;

  addProfiles(BuildContext context) {
    showMaterialModalBottomSheet(
      context: context,
      builder: (_) => Container(
        height: 100,
        child: ListView(children: [
          ListTile(
            title: Text("文件"),
            onTap: () {
              Navigator.of(context).pop();
              profileFileDialog(onOk: addProfile);
            },
          ),
          ListTile(
            title: Text("URL"),
            onTap: () {
              Navigator.of(context).pop();
              profileURLDialog(onOk: addProfile);
            },
          ),
        ]),
      ),
    );
  }

  addProfile(ProfileBase profile) async {
    var loading = Loading.builder();
    asuka.addOverlay(loading);
    await controller.getNewProfile(profile);
    loading.remove();
  }

  profileFileDialog({
    required void Function(ProfileFile) onOk,
    ProfileFile? profile,
  }) {
    asuka.showDialog(
      builder: (cxt) {
        var value = ProfileFile.emptyBean();
        var nameController = TextEditingController();
        var pathController = TextEditingController();
        if (profile != null) {
          value = profile.clone();
          nameController.text = value.name;
          pathController.text = value.path ?? "";
        } else {
          nameController.text = Random().nextInt(100).toString();
        }
        return AlertDialog(
          title: Text("文件"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(labelText: "名称"),
                controller: nameController,
              ),
              TextField(
                readOnly: true,
                decoration: InputDecoration(labelText: "文件"),
                controller: pathController,
                onTap: () {
                  FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ["yml", "yaml"],
                  ).then((value) {
                    pathController.text = value?.files.single.path ?? "";
                  }).catchError((_) {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text("取消"),
              onPressed: () => Navigator.of(cxt).pop(),
            ),
            ElevatedButton(
              child: Text("确认"),
              onPressed: () {
                if (nameController.text.isEmpty) {
                  return;
                }
                value.name = nameController.text;
                value.path = pathController.text;
                if (pathController.text.isNotEmpty) {}
                Navigator.of(cxt).pop();
                onOk(value);
              },
            ),
          ],
        );
      },
    );
  }

  profileURLDialog({
    required void Function(ProfileURL) onOk,
    ProfileURL? profile,
  }) {
    asuka.showDialog(
      builder: (cxt) {
        var nameController = TextEditingController();
        var urlController = TextEditingController();
        var value = ProfileURL.emptyBean();
        if (profile != null) {
          value = profile.clone();
          nameController.text = value.name;
          urlController.text = value.url;
        } else {
          nameController.text = Random().nextInt(100).toString();
        }
        return AlertDialog(
          title: Text("URL"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(labelText: "名称"),
                controller: nameController,
              ),
              TextField(
                decoration: InputDecoration(labelText: "URL"),
                controller: urlController,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text("取消"),
              onPressed: () => Navigator.of(cxt).pop(),
            ),
            ElevatedButton(
              child: Text("确认"),
              onPressed: () {
                value.url = urlController.text;
                value.name = nameController.text;
                if (value.name.isEmpty || value.url.isEmpty) return;
                Navigator.of(cxt).pop();
                onOk(value);
              },
            ),
          ],
        );
      },
    );
  }

  edit(ProfileBase profile) {
    if (profile is ProfileFile) {
      profileFileDialog(
        onOk: controller.edit,
        profile: profile,
      );
    } else if (profile is ProfileURL) {
      profileURLDialog(
        onOk: controller.edit,
        profile: profile,
      );
    }
  }

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
        actions: [
          IconButton(
            tooltip: "新增",
            icon: Icon(Icons.add),
            onPressed: () => addProfiles(context),
          )
        ],
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
                        subtitle: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e.type.value),
                            Text(
                              DateFormat("yyyy/MM/dd HH:mm").format(e.time),
                            ),
                          ],
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
                                itemBuilder: (_) {
                                  var list = <PopupMenuEntry<MenuType>>[
                                    PopupMenuItem(
                                      child: Text("编辑"),
                                      value: MenuType.Edit,
                                    ),
                                    PopupMenuItem(
                                      child: Text("移除"),
                                      value: MenuType.Remove,
                                    ),
                                  ];
                                  if (e.type == ProfileType.URL) {
                                    list.insert(
                                      0,
                                      PopupMenuItem(
                                        child: Text("更新"),
                                        value: MenuType.Update,
                                      ),
                                    );
                                  }
                                  return list;
                                },
                              ),
                      ))
                  .toList(),
            );
          },
        ),
      ),
    );
  }
}
