import 'dart:math';

import 'package:asuka/asuka.dart' hide showDialog;
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_file_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:intl/intl.dart';
import 'package:mobx/mobx.dart';

enum MenuType { Update, Remove, Edit }

/// 配置文件页
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  ModularState<ProfilesPage, ProfileController> createState() =>
      _ProfilesPageState();
}

class _ProfilesPageState extends ModularState<ProfilesPage, ProfileController> {
  final _config = Modular.get<GlobalConfig>();
  bool _loading = false;
  late List<ReactionDisposer> disposerList;

  showAddProfiles() {
    Asuka.showModalBottomSheet(
      backgroundColor: Colors.transparent,
      builder: (cxt) => Material(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        elevation: 7,
        child: SizedBox(
          height: 100,
          child: ListView(children: [
            ListTile(
              title: const Text("文件"),
              onTap: () {
                Navigator.of(cxt).pop();
                profileFileDialog(onOk: addProfile);
              },
            ),
            ListTile(
              title: const Text("URL"),
              onTap: () {
                Navigator.of(cxt).pop();
                profileURLDialog(onOk: addProfile);
              },
            ),
          ]),
        ),
      ),
    );
  }

  addProfile(ProfileBase profile) async {
    var loading = Loading.builder();
    Asuka.addOverlay(loading);
    await controller.addProfile(profile);
    loading.remove();
  }

  selectProfile(String file) async {
    var loading = Loading.builder();
    Asuka.addOverlay(loading);
    await controller.select(file);
    loading.remove();
  }

  profileFileDialog({
    required void Function(ProfileFile) onOk,
    ProfileFile? profile,
  }) {
    showDialog(
      context: context,
      builder: (cxt) {
        var value = ProfileFile.emptyBean();
        var nameController = TextEditingController();
        var pathController = TextEditingController();
        if (profile != null) {
          value = JsonMapper.clone<ProfileFile>(profile)!;
          nameController.text = value.name;
          pathController.text = value.path ?? "";
        } else {
          nameController.text = Random().nextInt(11000).toString();
        }
        return AlertDialog(
          title: const Text("文件"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: "名称"),
                controller: nameController,
              ),
              TextField(
                readOnly: true,
                decoration: const InputDecoration(labelText: "文件"),
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
              child: const Text("取消"),
              onPressed: () => Navigator.of(cxt).pop(),
            ),
            TextButton(
              child: const Text("确认"),
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
    showDialog(
      context: context,
      builder: (cxt) {
        var nameController = TextEditingController();
        var urlController = TextEditingController();
        var value = ProfileURL.emptyBean();
        if (profile != null) {
          value = JsonMapper.clone<ProfileURL>(profile)!;
          nameController.text = value.name;
          urlController.text = value.url;
        } else {
          nameController.text = Random().nextInt(11000).toString();
        }
        return AlertDialog(
          title: const Text("URL"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: "名称"),
                controller: nameController,
              ),
              TextField(
                decoration: const InputDecoration(labelText: "URL"),
                controller: urlController,
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
        .then((_) => setState(() => _loading = false))
        .catchError((err) {
      setState(() => _loading = false);
      Asuka.showSnackBar(SnackBar(content: Text(err.message ?? "未知异常")));
    });
  }

  removeProfile(String file) {
    Asuka.showSnackBar(SnackBar(
      content: const Text("确定移除？"),
      action: SnackBarAction(
        label: "确定",
        onPressed: () => controller.removeProfile(file),
      ),
    ));
  }

  @override
  Widget build(_) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text("订阅"),
        actions: [
          IconButton(
            tooltip: "新增",
            icon: const Icon(Icons.add),
            onPressed: showAddProfiles,
          )
        ],
      ),
      body: Observer(
        builder: (_) {
          return ListView(
            children: _config.profiles
                .map((e) => ListTile(
                      title: Text(e.name),
                      subtitle: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.type.value),
                          Text(DateFormat("yyyy/MM/dd HH:mm").format(e.time)),
                        ],
                      ),
                      selected: e.file == _config.selectedFile,
                      onTap: () => selectProfile(e.file),
                      trailing: _loading
                          ? const CircularProgressIndicator(strokeWidth: 6)
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
                                  const PopupMenuItem(
                                    value: MenuType.Edit,
                                    child: Text("编辑"),
                                  ),
                                  const PopupMenuItem(
                                    value: MenuType.Remove,
                                    child: Text("移除"),
                                  ),
                                ];
                                if (e.type == ProfileType.URL) {
                                  list.insert(
                                    0,
                                    const PopupMenuItem(
                                      value: MenuType.Update,
                                      child: Text("更新"),
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
    );
  }
}
