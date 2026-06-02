import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/presentation/widgets/empty_state.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/subscription.dart';
import 'package:singcast/utils/format.dart';
import 'package:singcast/utils/dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:timeago/timeago.dart' as timeago;

final _updatingFile = signal<String?>(null);

class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final _scrollController = ScrollController();
  final _fabVisible = ValueNotifier<bool>(true);
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _fabVisible.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final delta = offset - _lastOffset;
    if (delta > 5 && _fabVisible.value) {
      _fabVisible.value = false;
    } else if (delta < -5 && !_fabVisible.value) {
      _fabVisible.value = true;
    }
    _lastOffset = offset;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '订阅'),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _fabVisible,
        builder: (_, visible, _) => AnimatedFab(
          visible: visible,
          child: FloatingActionButton(
            onPressed: () => _showAddOptions(context),
            tooltip: '添加',
            child: const Icon(Icons.add),
          ),
        ),
      ),
      body: Watch((context) {
        final list = profiles.value;
        final sel = selectedFile.value;
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.cloud_outlined,
            title: '暂无订阅',
            hint: '点击右下角按钮添加订阅配置',
          );
        }
        return LayoutBuilder(builder: (_, constraints) {
          final cols = constraints.maxWidth > 400 ? 2 : 1;
          return MasonryGridView.count(
            controller: _scrollController,
            crossAxisCount: cols,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) => _ProfileCard(
              profile: list[i],
              isSelected: list[i].file == sel,
            ),
          );
        });
      }),
    );
  }

  void _showAddOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('添加订阅'),
        children: [
          ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: const Text('从文件'),
            onTap: () {
              Navigator.pop(ctx);
              _addFromFile(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('从 URL'),
            onTap: () {
              Navigator.pop(ctx);
              _addFromUrl(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addFromFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml'],
    );
    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    final fileName = p.basename(sourcePath);
    final destPath = p.join(profilesPath, fileName);
    await File(sourcePath).copy(destPath);

    try {
      final validation = await LibCore.instance.checkConfig(
        await File(destPath).readAsString(),
      );
      if (validation.isNotEmpty) {
        await File(destPath).delete();
        if (context.mounted) {
          showErrorDialog(context, '配置校验失败: $validation');
        }
        return;
      }
    } catch (e) {
      await File(destPath).delete();
      if (context.mounted) {
        showErrorDialog(context, '配置校验失败: $e');
      }
      return;
    }

    final profile = Profile(
      file: fileName,
      name: fileName,
      type: ProfileType.file,
      time: DateTime.now(),
    );
    final wasEmpty = profiles.value.isEmpty;
    profiles.value = [...profiles.value, profile];
    if (!context.mounted) return;
    if (wasEmpty) selectedFile.value = fileName;
  }

  Future<void> _addFromUrl(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => const _AddFromUrlDialog(),
    );
  }

  // _showInputDialog with initial value is in _ProfileCard below
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isSelected;
  const _ProfileCard({required this.profile, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final info = profile.userinfo;
    final expire = info?.expire;
    final cs = Theme.of(context).colorScheme;
    final hasTraffic = info != null && (info.total ?? 0) > 0;
    final expireDate = expire != null && expire > 0
        ? DateTime.fromMillisecondsSinceEpoch(expire * 1000)
        : null;
    final expireStr = expireDate != null
        ? '${expireDate.year % 100}.${expireDate.month.toString().padLeft(2, '0')}.${expireDate.day.toString().padLeft(2, '0')}'
        : null;
    return Card(
      elevation: 0,
      color: isSelected ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          selectedFile.value = profile.file;
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? cs.primary : null,
                    )),
              ),
              Text(profile.type.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  )),
            ]),
            if (hasTraffic) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: info.used / info.total!, minHeight: 6),
            ],
            const SizedBox(height: 4),
            Row(children: [
              Text(timeago.format(profile.time, locale: 'zh_cn'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              if (hasTraffic)
                Text('${formatBytes(info.used)} / ${formatBytes(info.total!)}',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
            Row(children: [
              Expanded(
                child: expireStr != null
                    ? Row(children: [
                        Icon(Icons.event, size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(expireStr,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ])
                    : const SizedBox.shrink(),
              ),
              IconButton(
                icon: const Icon(Icons.edit_note, size: 18),
                tooltip: '修改',
                onPressed: () => _edit(context),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '移除',
                onPressed: () => _remove(context),
                visualDensity: VisualDensity.compact,
              ),
              if (profile.type == ProfileType.url)
                Watch((_) {
                  final busy = _updatingFile.value == profile.file;
                  return IconButton(
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    tooltip: busy ? '更新中...' : '更新',
                    onPressed: busy ? null : () => _update(context),
                    visualDensity: VisualDensity.compact,
                  );
                }),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final nameCtl = TextEditingController(text: profile.name);
    final urlCtl = TextEditingController(text: profile.url);
    final intervalCtl = TextEditingController(
      text: profile.interval > 0 ? profile.interval.toString() : '',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (profile.type == ProfileType.url) ...[
              TextField(
                controller: urlCtl,
                maxLines: null,
                decoration: InputDecoration(
                  labelText: 'URL',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '复制',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: urlCtl.text));
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: intervalCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '更新间隔（小时）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final newUrl = profile.type == ProfileType.url ? urlCtl.text.trim() : profile.url;
    if (profile.type == ProfileType.url && (newUrl == null || newUrl.isEmpty)) return;
    final interval = int.tryParse(intervalCtl.text) ?? 0;
    final newName = nameCtl.text.isEmpty ? profile.name : nameCtl.text;

    // URL 变更时校验新订阅
    if (profile.type == ProfileType.url && newUrl != profile.url) {
      try {
        final checked = Profile(
          file: profile.file, name: newName, type: profile.type,
          time: profile.time, url: newUrl, interval: interval,
          userinfo: profile.userinfo,
        );
        await refreshProfile(checked);
      } catch (e) {
        if (context.mounted) showErrorDialog(context, 'URL 校验失败: $e');
      }
      return;
    }

    final list = profiles.value.map((p) =>
        p.file == profile.file ? Profile(
          file: p.file, name: newName, type: p.type, time: p.time,
          url: newUrl, interval: interval, userinfo: p.userinfo,
        ) : p).toList();
    profiles.value = list;
  }

  void _remove(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${profile.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      final file = profile.file;
      final list = profiles.value.where((p) => p.file != file).toList();
      profiles.value = list;
      if (selectedFile.value == file) {
        selectedFile.value = list.isEmpty ? null : list.first.file;
      }
      final path = p.join(profilesPath, file);
      if (File(path).existsSync()) await File(path).delete();
    });
  }

  Future<void> _update(BuildContext context) async {
    if (profile.url == null) return;
    _updatingFile.value = profile.file;
    try {
      await refreshProfile(profile);
    } catch (e) {
      if (context.mounted) {
        showErrorDialog(context, '更新失败: $e');
      }
    } finally {
      _updatingFile.value = null;
    }
  }
}

class _AddFromUrlDialog extends StatefulWidget {
  const _AddFromUrlDialog();

  @override
  State<_AddFromUrlDialog> createState() => _AddFromUrlDialogState();
}

class _AddFromUrlDialogState extends State<_AddFromUrlDialog> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    setState(() => _loading = true);
    try {
      final profile = await downloadSubscription(
        url: url,
        profilesDir: profilesPath,
      );

      try {
        final validation = await LibCore.instance.checkConfig(
          await File(p.join(profilesPath, profile.file)).readAsString(),
        );
        if (validation.isNotEmpty) {
          await File(p.join(profilesPath, profile.file)).delete();
          if (mounted) {
            setState(() => _loading = false);
            showErrorDialog(context, '配置校验失败: $validation');
          }
          return;
        }
      } catch (e) {
        await File(p.join(profilesPath, profile.file)).delete();
        if (mounted) {
          setState(() => _loading = false);
          showErrorDialog(context, '配置校验失败: $e');
        }
        return;
      }

      final wasEmpty = profiles.value.isEmpty;
      profiles.value = [...profiles.value, profile];
      if (wasEmpty) selectedFile.value = profile.file;

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showErrorDialog(context, '导入失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入订阅 URL'),
      content: TextField(
        controller: _controller,
        maxLines: null,
        keyboardType: TextInputType.url,
        enabled: !_loading,
        decoration: const InputDecoration(
          hintText: '请输入',
          border: OutlineInputBorder(),
        ),
        onSubmitted: _loading ? null : (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确定'),
        ),
      ],
    );
  }
}
