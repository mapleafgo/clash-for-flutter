import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:singcast/presentation/widgets/empty_state.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/subscription.dart';
import 'package:singcast/utils/dialog.dart';
import 'package:singcast/utils/format.dart';
import 'package:timeago/timeago.dart' as timeago;

final _updatingFile = signal<String?>(null);

class ProfilesPage extends SignalStatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final _scrollController = ScrollController();
  final _fabVisible = ValueNotifier<bool>(true);
  double _lastOffset = 0;
  late final _timeagoTick = signal(0);
  Timer? _timeagoTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _timeagoTick.value++;
    _timeagoTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted) _timeagoTick.value++;
    });
  }

  @override
  void dispose() {
    _timeagoTimer?.cancel();
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
    localeVersion.value; // rebuild on locale change
    return Scaffold(
      appBar: SysAppBar(title: t.profiles.title),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _fabVisible,
        builder: (_, visible, _) => AnimatedFab(
          visible: visible,
          child: FloatingActionButton(
            onPressed: () => _showAddOptions(context),
            tooltip: t.profiles.add,
            child: const Icon(Icons.add),
          ),
        ),
      ),
      body: l10nBuilder((context) {
        final list = profiles.value;
        final sel = selectedFile.value;
        _timeagoTick.value;
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.cloud_outlined,
            title: t.profiles.empty,
            hint: t.profiles.emptyHint,
          );
        }
        return LayoutBuilder(
          builder: (_, constraints) {
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
          },
        );
      }),
    );
  }

  void _showAddOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t.profiles.addSubscription),
        children: [
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: Text(t.profiles.fromFile),
              onTap: () {
                Navigator.pop(ctx);
                _addFromFile(context);
              },
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: const Icon(Icons.link),
              title: Text(t.profiles.fromUrl),
              onTap: () {
                Navigator.pop(ctx);
                _addFromUrl(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _uniqueFileName(String original) {
    final base = p.withoutExtension(original);
    final ext = p.extension(original);
    return '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
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
    if (profiles.value.any((p) => p.name == fileName)) {
      if (context.mounted) showErrorDialog(context, t.profiles.configExists(name: fileName));
      return;
    }

    var destPath = p.join(profilesPath, fileName);
    if (File(destPath).existsSync()) {
      destPath = p.join(profilesPath, _uniqueFileName(fileName));
    }
    try {
      await File(sourcePath).copy(destPath);
    } catch (e) {
      if (context.mounted) showErrorDialog(context, t.profiles.fileCopyFailed(error: '$e'));
      return;
    }

    try {
      await validateConfigFile(destPath);
    } catch (e) {
      File(destPath).delete().catchError((_) => File(destPath));
      if (context.mounted) showErrorDialog(context, '$e');
      return;
    }

    final savedName = p.basename(destPath);
    final profile = Profile(
      file: savedName,
      name: fileName,
      type: ProfileType.file,
      time: DateTime.now(),
    );
    final wasEmpty = profiles.value.isEmpty;
    profiles.value = [...profiles.value, profile];
    if (!context.mounted) return;
    if (wasEmpty) selectedFile.value = savedName;
  }

  Future<void> _addFromUrl(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => const _AddFromUrlDialog(),
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
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.5)
          : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          selectedFile.value = profile.file;
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? cs.primary : null,
                      ),
                    ),
                  ),
                  Text(
                    profile.type.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (hasTraffic) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: info.used / info.total!,
                  minHeight: 6,
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    timeago.format(profile.time, locale: LocaleSettings.currentLocale == AppLocale.en ? 'en' : 'zh_cn'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (hasTraffic)
                    Text(
                      '${formatBytes(info.used)} / ${formatBytes(info.total!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: expireStr != null
                        ? Row(
                            children: [
                              Icon(
                                Icons.event,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                expireStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_note, size: 18),
                    tooltip: t.profiles.edit,
                    onPressed: () => _edit(context),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: t.profiles.remove,
                    onPressed: () => _remove(context),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (profile.type == ProfileType.url)
                    l10nBuilder((_) {
                      final busy = _updatingFile.value == profile.file;
                      return IconButton(
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        tooltip: busy ? t.profiles.updating : t.profiles.update,
                        onPressed: busy ? null : () => _update(context),
                        visualDensity: VisualDensity.compact,
                      );
                    }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditProfileDialog(profile: profile),
    );
    if (result == null) return;

    if (profile.type == ProfileType.url && result.urlChanged) {
      try {
        await refreshProfile(
          Profile(
            file: profile.file,
            name: result.name,
            type: profile.type,
            time: profile.time,
            url: result.url,
            interval: result.interval,
            userinfo: profile.userinfo,
          ),
        );
      } catch (e) {
        if (context.mounted) showErrorDialog(context, t.profiles.urlValidationFailed(error: '$e'));
      }
      return;
    }

    // URL 未变更，仅更新名称/间隔/URL 微调（refreshProfile 已处理 URL 变更）
    final list = profiles.value
        .map(
          (p) => p.file == profile.file
              ? Profile(
                  file: p.file,
                  name: result.name,
                  type: p.type,
                  time: p.time,
                  url: result.url,
                  interval: result.interval,
                  userinfo: p.userinfo,
                )
              : p,
        )
        .toList();
    profiles.value = list;
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.profiles.confirmDelete),
        content: Text(t.profiles.confirmDeleteMessage(name: profile.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.dialogs.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(t.dialogs.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final file = profile.file;
    final list = profiles.value.where((p) => p.file != file).toList();
    profiles.value = list;
    if (selectedFile.value == file) {
      selectedFile.value = list.isEmpty ? null : list.first.file;
    }
    final path = p.join(profilesPath, file);
    if (File(path).existsSync()) await File(path).delete();
  }

  Future<void> _update(BuildContext context) async {
    if (profile.url == null) return;
    _updatingFile.value = profile.file;
    try {
      await refreshProfile(profile);
    } catch (e) {
      if (context.mounted) {
        showErrorDialog(context, t.profiles.updateFailed(error: '$e'));
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
      await importSubscription(url);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorDialog(context, t.profiles.importFailed(error: '$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.profiles.inputUrl),
      content: TextField(
        controller: _controller,
        maxLines: null,
        keyboardType: TextInputType.url,
        enabled: !_loading,
        decoration: InputDecoration(
          hintText: t.profiles.pleaseInput,
          border: OutlineInputBorder(),
        ),
        onSubmitted: _loading ? null : (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(t.dialogs.cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.dialogs.confirm),
        ),
      ],
    );
  }
}

class _EditResult {
  final String name;
  final String? url;
  final int interval;
  final bool urlChanged;
  _EditResult({
    required this.name,
    required this.url,
    required this.interval,
    required this.urlChanged,
  });
}

class _EditProfileDialog extends StatefulWidget {
  final Profile profile;
  const _EditProfileDialog({required this.profile});

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final _nameCtl = TextEditingController(text: widget.profile.name);
  late final _urlCtl = TextEditingController(text: widget.profile.url);
  late final _intervalCtl = TextEditingController(
    text: widget.profile.interval > 0 ? widget.profile.interval.toString() : '',
  );

  @override
  void dispose() {
    _nameCtl.dispose();
    _urlCtl.dispose();
    _intervalCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.profiles.edit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtl,
            decoration: InputDecoration(
              labelText: t.profiles.name,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.profile.type == ProfileType.url) ...[
            TextField(
              controller: _urlCtl,
              maxLines: null,
              decoration: InputDecoration(
                labelText: 'URL',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: t.profiles.copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _urlCtl.text));
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _intervalCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.profiles.updateIntervalHours,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.dialogs.cancel),
        ),
        FilledButton(
          onPressed: () {
            final p = widget.profile;
            final newName = _nameCtl.text.isEmpty ? p.name : _nameCtl.text;
            final newUrl = p.type == ProfileType.url
                ? _urlCtl.text.trim()
                : p.url;
            if (p.type == ProfileType.url &&
                (newUrl == null || newUrl.isEmpty)) {
              return;
            }
            Navigator.pop(
              context,
              _EditResult(
                name: newName,
                url: newUrl,
                interval: int.tryParse(_intervalCtl.text) ?? 0,
                urlChanged: newUrl != p.url,
              ),
            );
          },
          child: Text(t.dialogs.confirm),
        ),
      ],
    );
  }
}
