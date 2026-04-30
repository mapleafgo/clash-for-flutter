import 'dart:async';
import 'dart:io';

import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
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
  bool _showingLoading = false;

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
        final err = profileError.value;
        if (err != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              showErrorDialog(context, '切换配置失败: $err');
            }
            profileError.value = null;
          });
        }
        if (list.isEmpty) return const Center(child: Text('暂无订阅'));
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

    final profile = Profile(
      file: fileName,
      name: fileName,
      type: ProfileType.file,
      time: DateTime.now(),
    );
    profiles.value = [...profiles.value, profile];
    if (!context.mounted) return;
    _showLoadingDialog(context);
    selectedFile.value = fileName;
  }

  Future<void> _addFromUrl(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => const _AddFromUrlDialog(),
    );
  }

  void _showLoadingDialog(BuildContext context) {
    if (_showingLoading) return;
    _showingLoading = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Watch((_) {
        if (!coreActivating.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_showingLoading) {
              _showingLoading = false;
              Navigator.of(context, rootNavigator: true).pop();
            }
          });
        }
        return const PopScope(
          canPop: false,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }),
    );
  }

  // _showInputDialog with initial value is in _ProfileCard below
}

Future<void> _waitForCore() async {
  if (!coreActivating.value) return;
  final completer = Completer<void>();
  final dispose = effect(() {
    if (!coreActivating.value && !completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future;
  dispose();
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
      color: isSelected ? cs.primaryContainer : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          final state = context.findAncestorStateOfType<_ProfilesPageState>();
          if (state != null && !state._showingLoading) {
            state._showLoadingDialog(context);
          }
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
                tooltip: '修改名称',
                onPressed: () => _editName(context),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.code, size: 18),
                tooltip: '修改源',
                onPressed: () => _editSource(context),
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
      builder: (ctx) => AlertDialog(
        title: Text(hint),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('确定')),
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
      final updated = await downloadSubscription(
        url: profile.url!,
        profilesDir: profilesPath,
        name: profile.name,
      );
      final oldPath = p.join(profilesPath, profile.file);
      if (File(oldPath).existsSync()) await File(oldPath).delete();
      final list = profiles.value.map((p) =>
          p.file == profile.file ? updated : p).toList();
      profiles.value = list;
      final isActive = selectedFile.value == profile.file;
      if (isActive) {
        selectedFile.value = updated.file;
        await _waitForCore();
      }
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
      profiles.value = [...profiles.value, profile];
      selectedFile.value = profile.file;

      // 等待内核启动完成
      if (!mounted) return;
      await _waitForCore();

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
