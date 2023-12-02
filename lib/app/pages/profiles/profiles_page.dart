import 'package:asuka/asuka.dart' hide showDialog;
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_file_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/component/loading_component.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/pages/profiles/profile_item.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' hide context;

/// 配置文件页
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final _config = Modular.get<AppConfig>();
  final ProfileController _controller = Modular.get<ProfileController>();
  final ScrollController _scrollController = ScrollController();
  final List<String> _loadingList = [];
  bool _showFab = true;

  @override
  initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse && _showFab) {
      setState(() => _showFab = false);
    }
    if (_scrollController.position.userScrollDirection == ScrollDirection.forward && !_showFab) {
      setState(() => _showFab = true);
    }
  }

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
    _controller.addProfile(profile).then((_) => loading.remove()).catchError((e) {
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
        onOk: (v) => _controller.edit(profile..path = v),
      );
    } else if (profile is ProfileURL) {
      dialogInputValue(
        label: "URL",
        initialValue: profile.url,
        onOk: (v) => _controller.edit(profile..url = v),
      );
    }
  }

  changeName(ProfileBase profile) {
    dialogInputValue(
      label: "名称",
      initialValue: profile.name,
      onOk: (v) => _controller.edit(profile..name = v),
    );
  }

  upgradeProfile(String file) {
    setState(() => _loadingList.add(file));
    _controller.updateProfile(file).catchError((err) {
      Asuka.showSnackBar(SnackBar(content: Text(err.message ?? "未知异常")));
    }).then((value) => setState(() => _loadingList.remove(file)));
  }

  removeProfile(String file) {
    Asuka.showSnackBar(SnackBar(
      content: const Text("确定移除？"),
      action: SnackBarAction(
        label: "确定",
        onPressed: () => _controller.removeProfile(file),
      ),
    ));
  }

  Widget _buildPanel(int index) {
    var profile = _config.profiles[index];
    var show = ProfileShow(
      title: profile.name,
      type: profile.type,
      lastUpdate: profile.time,
    );
    if (profile is ProfileURL) {
      var userinfo = profile.userinfo;
      if (userinfo != null) {
        show
          ..expire = userinfo.expire == null ? null : DateTime.fromMillisecondsSinceEpoch((userinfo.expire!) * 1000)
          ..use = (userinfo.upload ?? 0) + (userinfo.download ?? 0)
          ..total = userinfo.total ?? 0;
      }
    }
    return Observer(
      builder: (_) => SelectableCard(
        profile: show,
        selected: profile.file == _config.selectedFile,
        isLoading: _loadingList.contains(profile.file),
        onTap: () => _controller.select(profile.file),
        onUpdate: () => upgradeProfile(profile.file),
        onEdit: () => edit(profile),
        onRemove: () => removeProfile(profile.file),
        onChangeName: () => changeName(profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('订阅'),
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final crossAxisCount = constraints.maxWidth < 460 ? 1 : 2;

          return Observer(
            builder: (_) => MasonryGridView.count(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              padding: const EdgeInsets.all(20),
              itemCount: _config.profiles.length,
              itemBuilder: (BuildContext context, int index) {
                return _buildPanel(index);
              },
            ),
          );
        },
      ),
      floatingActionButton: _showFab
          ? FloatingActionButton(
              tooltip: "新增",
              onPressed: showAddProfiles,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
