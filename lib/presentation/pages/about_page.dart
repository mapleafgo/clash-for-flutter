import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/i18n/strings.g.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/presentation/widgets/animated_fab.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/update_checker.dart';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/utils/log_file.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return l10nBuilder((context) {
    return Scaffold(
      appBar: SysAppBar(title: t.about.title),
      body: ListView(children: [
        const _AboutHeader(),
        const _CheckUpdateTile(),
        ListTile(
          title: Text(t.about.officialWebsite),
          subtitle: const Text(Constants.homeUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse(Constants.homeUrl)),
        ),
        ListTile(
          title: Text(t.about.sourceRepo),
          subtitle: const Text(Constants.sourceUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse(Constants.sourceUrl)),
        ),
        const _KernelVersionTile(),
        const _ExportLogTile(),
        if (Platform.isWindows || Platform.isMacOS) const _UninstallServiceTile(),
      ]),
    );
    });
  }
}

class _KernelVersionTile extends StatefulWidget {
  const _KernelVersionTile();

  @override
  State<_KernelVersionTile> createState() => _KernelVersionTileState();
}

class _KernelVersionTileState extends State<_KernelVersionTile> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await LibCore.instance.getVersion();
      if (mounted) setState(() => _version = v);
    } catch (_) {
      if (mounted) setState(() => _version = '-');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(t.about.kernelVersion),
      subtitle: Text(_version.isEmpty ? t.about.loading : _version),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => launchUrl(Uri.parse('https://github.com/mapleafgo/singcast-cli')),
    );
  }
}

class _CheckUpdateTile extends StatefulWidget {
  const _CheckUpdateTile();

  @override
  State<_CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends State<_CheckUpdateTile> {
  int _state = 0;
  final String _currentVersion = Defaults.appVersion;
  String _latestVersion = '';

  @override
  void initState() {
    super.initState();
    _state = 0;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(t.about.version),
      subtitle: Text(_currentVersion),
      trailing: _trailing(),
      onTap: _state == 1 ? null : _check,
    );
  }

  Widget _trailing() {
    return switch (_state) {
      1 => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      2 => const Icon(Icons.check_circle_outline, color: Colors.green),
      3 => const Icon(Icons.system_update, color: Colors.blue),
      -1 => const Icon(Icons.error_outline, color: Colors.red),
      _ => const Icon(Icons.refresh),
    };
  }

  Future<void> _check() async {
    setState(() => _state = 1);
    try {
      final latest = await checkForUpdate();
      if (!mounted) return;
      if (latest == null) {
        setState(() => _state = 2);
      } else {
        _latestVersion = latest;
        setState(() => _state = 3);
        _showUpdateDialog();
      }
    } catch (_) {
      if (mounted) setState(() => _state = -1);
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.about.newVersionFound),
        content: Text(t.about.versionInfo(current: _currentVersion, latest: _latestVersion)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.about.ignore),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('${Constants.sourceUrl}/releases/latest'));
            },
            child: Text(t.about.goDownload),
          ),
        ],
      ),
    );
  }
}

class _UninstallServiceTile extends StatefulWidget {
  const _UninstallServiceTile();

  @override
  State<_UninstallServiceTile> createState() => _UninstallServiceTileState();
}

class _UninstallServiceTileState extends State<_UninstallServiceTile> {
  bool _loading = false;

  Future<void> _uninstall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.about.removeElevationConfirm),
        content: Text(t.about.removeElevationDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.dialogs.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.dialogs.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await LibCore.instance.uninstallServiceAndRestart();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.about.elevationRemoved)),
        );
      }
    } catch (e) {
      LogFileWriter.instance?.log(
        'uninstallServiceAndRestart failed: $e',
        level: LogLevel.error,
        name: 'service',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.about.operationFailed)),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(t.about.removeElevation),
      subtitle: Text(Platform.isWindows
          ? t.about.removeElevationWinDesc
          : t.about.removeElevationMacDesc),
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline),
      onTap: _loading ? null : _uninstall,
    );
  }
}

class _AboutHeader extends StatefulWidget {
  const _AboutHeader();

  @override
  State<_AboutHeader> createState() => _AboutHeaderState();
}

class _AboutHeaderState extends State<_AboutHeader>
    with SingleTickerProviderStateMixin {
  int _tapCount = 0;
  Timer? _resetTimer;
  late final _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _resetTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _onLogoTap() {
    _tapCount++;

    if (_tapCount == 1) {
      _resetTimer = Timer(const Duration(seconds: 6), () {
        _tapCount = 0;
        _resetTimer = null;
      });
    }

    if (_tapCount >= 18) {
      _tapCount = 0;
      _resetTimer?.cancel();
      _resetTimer = null;
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.heavyImpact();
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.about.easterEgg),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (_tapCount >= 3) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: GestureDetector(
        onTap: _onLogoTap,
        child: ShakeBuilder(
          controller: _shakeController,
          child: Column(children: [
            SvgPicture.asset('assets/logo.svg', width: 64, height: 64),
            const SizedBox(height: 8),
            Text(
              'Singcast',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ]),
        ),
      ),
    );
  }
}

class _ExportLogTile extends StatefulWidget {
  const _ExportLogTile();

  @override
  State<_ExportLogTile> createState() => _ExportLogTileState();
}

class _ExportLogTileState extends State<_ExportLogTile> {
  bool _loading = false;

  Future<void> _export() async {
    setState(() => _loading = true);
    try {
      await LogFileWriter.instance?.flush();
      final path = LogFileWriter.logFilePath;
      if (path == null) {
        _showMessage(t.about.logNotInitialized);
        return;
      }
      final logFile = File(path);
      if (!await logFile.exists()) {
        _showMessage(t.about.logFileNotExist);
        return;
      }

      final name = _exportFileName();
      if (Platform.isAndroid || Platform.isIOS) {
        final bytes = await logFile.readAsBytes();
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes)],
            fileNameOverrides: [name],
            text: 'Singcast log',
          ),
        );
      } else {
        final bytes = await logFile.readAsBytes();
        final savePath = await FilePicker.saveFile(
          dialogTitle: t.about.exportLog,
          fileName: name,
          bytes: bytes,
        );
        if (savePath == null) return;
        _showMessage(t.about.logExported);
      }
    } catch (e) {
      LogFileWriter.instance?.log(
        'export log failed: $e',
        level: LogLevel.error,
        name: 'export',
      );
      _showMessage(t.about.exportFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _exportFileName() {
    final t = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return 'singcast-${t.year}${p(t.month)}${p(t.day)}-${p(t.hour)}${p(t.minute)}${p(t.second)}.log';
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(t.about.exportLog),
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.file_download_outlined),
      onTap: _loading ? null : _export,
    );
  }
}
