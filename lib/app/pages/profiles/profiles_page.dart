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
import 'package:path/path.dart' hide context;

enum MenuType { Update, Remove, Edit, Name }

/// 配置文件页
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  ModularState<ProfilesPage, ProfileController> createState() =>
      _ProfilesPageState();
}

class _ProfilesPageState extends ModularState<ProfilesPage, ProfileController> {
  final _config = Modular.get<GlobalConfig>();
  String? _loadingFile;
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
                dialogPickerFile(
                  label: "文件",
                  onOk: (v) {
                    var profile = ProfileFile.emptyBean()
                      ..path = v
                      ..name = basename(v);
                    addProfile(profile);
                  },
                );
              },
            ),
            ListTile(
              title: const Text("URL"),
              onTap: () {
                Navigator.of(cxt).pop();
                dialogInputValue(
                  label: "URL",
                  onOk: (v) {
                    addProfile(ProfileURL.emptyBean()..url = v);
                  },
                );
              },
            ),
          ]),
        ),
      ),
    );
  }

  addProfile(ProfileBase profile) {
    var loading = Loading.builder();
    Asuka.addOverlay(loading);
    controller
        .addProfile(profile)
        .then((_) => loading.remove())
        .catchError((e) {
      loading.remove();
      Asuka.showSnackBar(SnackBar(content: Text("导入异常: $e")));
    });
  }

  dialogPickerFile({
    required String label,
    required void Function(String) onOk,
    String? initialValue,
  }) {
    showDialog(
      context: context,
      builder: (cxt) {
        var pathController = TextEditingController(text: initialValue);
        return AlertDialog(
          title: Text(label),
          content: TextField(
            readOnly: true,
            decoration: InputDecoration(labelText: label),
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
          actions: [
            TextButton(
              child: const Text("取消"),
              onPressed: () => Navigator.of(cxt).pop(),
            ),
            TextButton(
              child: const Text("确认"),
              onPressed: () {
                if (pathController.text.isEmpty) return;
                Navigator.of(cxt).pop();
                onOk(pathController.text);
              },
            ),
          ],
        );
      },
    );
  }

  dialogInputValue({
    required String label,
    required void Function(String) onOk,
    String? initialValue,
  }) {
    showDialog(
      context: context,
      builder: (cxt) {
        var textController = TextEditingController(text: initialValue);
        return AlertDialog(
          title: Text(label),
          content: TextField(
            decoration: InputDecoration(labelText: label),
            controller: textController,
          ),
          actions: [
            TextButton(
              child: const Text("取消"),
              onPressed: () => Navigator.of(cxt).pop(),
            ),
            TextButton(
              child: const Text("确认"),
              onPressed: () {
                if (textController.text.isEmpty) return;
                Navigator.of(cxt).pop();
                onOk(textController.text);
              },
            ),
          ],
        );
      },
    );
  }

  edit(ProfileBase profile) {
    if (profile is ProfileFile) {
      dialogPickerFile(
        label: "文件",
        initialValue: profile.path,
        onOk: (v) => controller.edit(profile..path = v),
      );
    } else if (profile is ProfileURL) {
      dialogInputValue(
        label: "URL",
        initialValue: profile.url,
        onOk: (v) => controller.edit(profile..url = v),
      );
    }
  }

  changeName(ProfileBase profile) {
    dialogInputValue(
      label: "名称",
      initialValue: profile.name,
      onOk: (v) => controller.edit(profile..name = v),
    );
  }

  upgradeProfile(String file) {
    setState(() => _loadingFile = file);
    controller
        .updateProfile(file)
        .then((_) => setState(() => _loadingFile = null))
        .catchError((err) {
      setState(() => _loadingFile = null);
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
                .map(
                  (profile) => ListTile(
                    title: Text(profile.name),
                    subtitle: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(profile.type.value),
                        Text(DateFormat("yyyy/MM/dd HH:mm")
                            .format(profile.time)),
                      ],
                    ),
                    selected: profile.file == _config.selectedFile,
                    onTap: () => controller.select(profile.file),
                    trailing:
                        _loadingFile != null && _loadingFile == profile.file
                            ? const CircularProgressIndicator(strokeWidth: 6)
                            : PopupMenuButton(
                                onSelected: (type) {
                                  switch (type) {
                                    case MenuType.Edit:
                                      edit(profile);
                                      break;
                                    case MenuType.Update:
                                      upgradeProfile(profile.file);
                                      break;
                                    case MenuType.Remove:
                                      removeProfile(profile.file);
                                      break;
                                    case MenuType.Name:
                                      changeName(profile);
                                      break;
                                  }
                                },
                                itemBuilder: (_) {
                                  var list = <PopupMenuEntry<MenuType>>[
                                    const PopupMenuItem(
                                      value: MenuType.Name,
                                      child: Text("修改名称"),
                                    ),
                                    const PopupMenuItem(
                                      value: MenuType.Edit,
                                      child: Text("修改源"),
                                    ),
                                    const PopupMenuItem(
                                      value: MenuType.Remove,
                                      child: Text("移除"),
                                    ),
                                  ];
                                  if (profile.type == ProfileType.URL) {
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
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}
