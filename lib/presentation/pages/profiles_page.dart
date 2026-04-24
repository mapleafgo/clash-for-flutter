import 'dart:io';

import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/domain/profile.dart';
import 'package:clash_for_flutter/domain/subscription_info.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/utils/format.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '订阅'),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showAddOptions(context),
      ),
      body: Watch((context) {
        final list = profiles.value;
        if (list.isEmpty) return const Center(child: Text('暂无订阅'));
        return LayoutBuilder(builder: (_, constraints) {
          final cols = constraints.maxWidth > 600 ? 2 : 1;
          return MasonryGridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) => _ProfileCard(
              profile: list[i],
              isSelected: list[i].file == selectedFile.value,
            ),
          );
        });
      }),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: const Text('文件'),
            onTap: () => _addFromFile(context),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('URL'),
            onTap: () => _addFromUrl(context),
          ),
        ],
      ),
    );
  }

  Future<void> _addFromFile(BuildContext context) async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml'],
    );
    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    final fileName = p.basename(sourcePath);
    final destPath = p.join(profilesPath, fileName);
    await File(sourcePath).copy(destPath);

    final profile = Profile(
      file: fileName,
      name: fileName,
      type: ProfileType.file,
      time: DateTime.now(),
    );
    profiles.value = [...profiles.value, profile];
    selectedFile.value = fileName;
  }

  Future<void> _addFromUrl(BuildContext context) async {
    Navigator.pop(context);
    final url = await _showInputDialog(context, '输入订阅 URL');
    if (url == null || url.isEmpty) return;

    try {
      final profile = await api.downloadSubscription(
        url: url,
        profilesDir: profilesPath,
      );
      profiles.value = [...profiles.value, profile];
      selectedFile.value = profile.file;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<String?> _showInputDialog(BuildContext context, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(hint),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isSelected;
  const _ProfileCard({required this.profile, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final info = profile.userinfo;
    final expire = info?.expire;
    return Card(
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () => selectedFile.value = profile.file,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text(profile.type.name.toUpperCase()),
            ]),
            Text(timeago.format(profile.time, locale: 'zh_cn')),
            if (info != null && (info.total ?? 0) > 0) ...[
              const SizedBox(height: 8),
              _TrafficBar(info: info),
            ],
            if (expire != null && expire > 0) ...[
              const SizedBox(height: 4),
              Text('过期: ${timeago.format(DateTime.fromMillisecondsSinceEpoch(expire * 1000), locale: 'zh_cn')}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(
                icon: const Icon(Icons.edit_note, size: 20),
                tooltip: '修改名称',
                onPressed: () => _editName(context),
              ),
              IconButton(
                icon: const Icon(Icons.code, size: 20),
                tooltip: '修改源',
                onPressed: () => _editSource(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: '移除',
                onPressed: () => _remove(context),
              ),
              if (profile.type == ProfileType.url)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '更新',
                  onPressed: () => _update(context),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context) async {
    final name = await _showInputDialog(context, '修改名称', profile.name);
    if (name == null || name.isEmpty) return;
    final list = profiles.value.map((p) =>
        p.file == profile.file ? Profile(
          file: p.file, name: name, type: p.type, time: p.time,
          url: p.url, interval: p.interval, userinfo: p.userinfo,
        ) : p).toList();
    profiles.value = list;
  }

  Future<String?> _showInputDialog(BuildContext context, String hint, [String? initial]) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(hint),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );
  }

  Future<void> _editSource(BuildContext context) async {
    if (profile.type == ProfileType.url) {
      final url = await _showInputDialog(context, '修改 URL', profile.url);
      if (url == null) return;
      final list = profiles.value.map((p) =>
          p.file == profile.file ? Profile(
            file: p.file, name: p.name, type: p.type, time: p.time,
            url: url, interval: p.interval, userinfo: p.userinfo,
          ) : p).toList();
      profiles.value = list;
    }
  }

  void _remove(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('确认删除？'),
      action: SnackBarAction(
        label: '删除',
        onPressed: () async {
          final file = profile.file;
          final list = profiles.value.where((p) => p.file != file).toList();
          profiles.value = list;
          if (selectedFile.value == file) {
            selectedFile.value = list.isEmpty ? null : list.first.file;
          }
          final path = p.join(profilesPath, file);
          if (File(path).existsSync()) await File(path).delete();
        },
      ),
    ));
  }

  Future<void> _update(BuildContext context) async {
    if (profile.url == null) return;
    try {
      final updated = await api.downloadSubscription(
        url: profile.url!,
        profilesDir: profilesPath,
        name: profile.name,
      );
      final oldPath = p.join(profilesPath, profile.file);
      if (File(oldPath).existsSync()) await File(oldPath).delete();
      final list = profiles.value.map((p) =>
          p.file == profile.file ? updated : p).toList();
      profiles.value = list;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    }
  }
}

class _TrafficBar extends StatelessWidget {
  final SubscriptionInfo info;
  const _TrafficBar({required this.info});

  @override
  Widget build(BuildContext context) {
    final total = info.total ?? 0;
    if (total == 0) return const SizedBox.shrink();
    final used = info.used;
    return Column(children: [
      LinearProgressIndicator(value: used / total),
      Text('${formatBytes(used)} / ${formatBytes(total)}'),
    ]);
  }
}
