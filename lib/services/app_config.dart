import 'dart:async';
import 'dart:io';

import 'package:clash_for_flutter/data/local/app_config_storage.dart';
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/domain/profile.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:path/path.dart' as p;
import 'package:proxy_manager/proxy_manager.dart';
import 'package:signals_flutter/signals_flutter.dart';

final _proxyManager = ProxyManager();

final systemProxy = signal(false);
final selectedFile = signal<String?>(null);
final profiles = signal<List<Profile>>([]);
final mmdbUrl = signal(Defaults.mmdbUrl);
final delayTestUrl = signal(Defaults.delayTestUrl);
final tunIf = signal<bool?>(null);

Timer? _saveTimer;

void initAppConfig() {
  final config = AppConfigStorage.load();
  final validProfiles = _filterExistingProfiles(config.profiles);
  profiles.value = validProfiles;
  selectedFile.value = _resolveSelected(config.selectedFile, validProfiles);
  mmdbUrl.value = config.mmdbUrl;
  delayTestUrl.value = config.delayTestUrl;
  tunIf.value = config.tunIf ?? !Constants.isDesktop;
  _startAutoSave();
  _watchSelectedFile();
}

List<Profile> _filterExistingProfiles(List<Profile> list) {
  final dir = Directory('${Constants.homeDir.path}${Constants.profilesPath}');
  if (!dir.existsSync()) return [];
  final files = dir.listSync().map((e) => p.basename(e.path)).toSet();
  return list.where((e) => files.contains(e.file)).toList();
}

String? _resolveSelected(String? file, List<Profile> list) {
  if (file != null && list.any((e) => e.file == file)) return file;
  return list.isEmpty ? null : list.first.file;
}

void _startAutoSave() {
  effect(() {
    systemProxy.value;
    selectedFile.value;
    profiles.value;
    mmdbUrl.value;
    delayTestUrl.value;
    tunIf.value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  });
}

void _save() {
  AppConfigStorage.save(AppStoredConfig(
    selectedFile: selectedFile.value,
    profiles: profiles.value,
    mmdbUrl: mmdbUrl.value,
    delayTestUrl: delayTestUrl.value,
    tunIf: tunIf.value,
  ));
}

void _watchSelectedFile() {
  effect(() {
    final file = selectedFile.value;
    if (file == null) return;
    final path = p.isAbsolute(file)
        ? file
        : '${Constants.homeDir.path}${Constants.profilesPath}/$file';
    api.changeConfig(path);
  });
}

Profile? get activeProfile {
  final file = selectedFile.value;
  if (file == null) return null;
  try {
    return profiles.value.firstWhere((e) => e.file == file);
  } catch (_) {
    return null;
  }
}

Future<void> openProxy() async {
  if (!Constants.isDesktop) return;
  final port = clashConfig.value.port;
  if (port == 0) throw Exception('未设置代理端口');
  if (!Platform.isWindows) {
    await _proxyManager.setAsSystemProxy(ProxyTypes.socks, Constants.localhost, port);
  } else {
    await _proxyManager.setAsSystemProxy(ProxyTypes.http, Constants.localhost, port);
    await _proxyManager.setAsSystemProxy(ProxyTypes.https, Constants.localhost, port);
  }
  systemProxy.value = true;
}

Future<void> closeProxy() async {
  if (!Constants.isDesktop) return;
  _proxyManager.cleanSystemProxy();
  systemProxy.value = false;
}

String get profilesPath =>
    '${Constants.homeDir.path}${Constants.profilesPath}';
