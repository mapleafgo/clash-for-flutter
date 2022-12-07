import 'package:asuka/asuka.dart' hide showDialog;
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_file_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/utils/utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' hide context;

enum MenuType { Update, Remove, Edit, Name }

final dateFormat = DateFormat("yyyy/MM/dd HH:mm");

/// 配置文件页
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  ModularState<ProfilesPage, ProfileController> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends ModularState<ProfilesPage, ProfileController> {
  final _config = Modular.get<GlobalConfig>();
  String? _loadingFile;

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
    controller.addProfile(profile).then((_) => loading.remove()).catchError((e) {
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
    controller.updateProfile(file).then((_) => setState(() => _loadingFile = null)).catchError((err) {
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

  getResidual(ProfileBase? profile) {
    if (profile is ProfileURL) {
      var userinfo = profile.userinfo;
      if (userinfo != null) {
        var download = userinfo.download ?? 0;
        var total = userinfo.total ?? 0;
        var progress = download / total;
        var color = Theme.of(context).primaryColor.withOpacity(0.7);
        var textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
        var expire = DateTime.fromMillisecondsSinceEpoch((userinfo.expire ?? 0) * 1000);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Text(
                    "${dataformat(download)}/${dataformat(total)}",
                    style: textStyle,
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.black12,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Text("Expire: ${dateFormat.format(expire)}", style: textStyle),
          ],
        );
      }
    }
    return Container();
  }

  @override
  Widget build(_) {
    return Scaffold(
      appBar: const SysAppBar(title: Text("订阅")),
      body: Observer(
        builder: (_) {
          return ListView.builder(
            itemCount: _config.profiles.length,
            itemBuilder: (_, i) {
              var profile = _config.profiles[i];
              return Observer(
                builder: (_) => ListTile(
                  selected: profile.file == _config.selectedFile,
                  onTap: () => controller.select(profile.file),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(profile.name), getResidual(profile)],
                  ),
                  subtitle: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(profile.type.value),
                      Text(dateFormat.format(profile.time)),
                    ],
                  ),
                  trailing: _loadingFile != null && _loadingFile == profile.file
                      ? const SizedBox(
                          width: 25,
                          height: 25,
                          child: CircularProgressIndicator(),
                        )
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
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "新增",
        onPressed: showAddProfiles,
        child: const Icon(Icons.add),
      ),
    );
  }
}
