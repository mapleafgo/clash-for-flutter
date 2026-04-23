# Clash for Flutter 现代化重写实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Signals + GoRouter + json_serializable 全面重写 clash-for-flutter 应用

**Architecture:** presentation/domain/data 三层架构。Signals 管理状态和 DI，GoRouter 管理路由，json_serializable 处理序列化。保留 core_control.dart 和 FFI 绑定不动。

**Tech Stack:** Flutter 3.41+, Dart 3.11+, signals_flutter, go_router, json_serializable, dio, tray_manager, window_manager

---

## File Structure

```
lib/
├── main.dart                              # 入口（重写）
├── core_control.dart                      # 保留不动
├── clash_generated_bindings.dart          # 保留不动
│
├── domain/
│   ├── config.dart                        # Clash 配置模型
│   ├── proxy.dart                         # 代理项模型
│   ├── proxy_group.dart                   # 代理分组模型
│   ├── connection.dart                    # 连接模型
│   ├── profile.dart                       # 订阅配置模型（URL/FILE 联合类型）
│   ├── log.dart                           # 日志模型
│   ├── net_speed.dart                     # 网速模型
│   ├── subscription_info.dart             # 订阅流量信息模型
│   └── enums.dart                         # 所有枚举
│
├── data/
│   ├── api/
│   │   ├── clash_api.dart                 # Clash REST API
│   │   └── ws_streams.dart                # WebSocket 流
│   └── local/
│       ├── app_config_storage.dart         # 应用配置持久化
│       └── core_config_storage.dart        # 内核配置持久化
│
├── services/
│   ├── app_config.dart                     # 应用配置（Signals）
│   ├── core_config.dart                    # 内核配置（Signals）
│   └── tray_service.dart                   # 托盘服务
│
├── presentation/
│   ├── app.dart                           # MaterialApp.router
│   ├── router.dart                        # GoRouter 路由定义
│   ├── pages/
│   │   ├── init_page.dart                 # 初始化页
│   │   ├── home_page.dart                 # 首页
│   │   ├── proxies_page.dart              # 代理页
│   │   ├── logs_page.dart                 # 日志页
│   │   ├── connections_page.dart          # 连接页
│   │   ├── profiles_page.dart             # 订阅页
│   │   ├── settings_page.dart             # 设置页
│   │   ├── desktop_shell.dart             # 桌面端布局壳
│   │   └── mobile_shell.dart              # 移动端布局壳
│   └── widgets/
│       ├── loading.dart                   # Loading 遮罩
│       └── sys_app_bar.dart               # 通用 AppBar
│
└── utils/
    ├── constants.dart                     # 常量
    └── format.dart                        # 格式化工具（dataformat 等）
```

---

### Task 1: 清理旧代码 + 更新 pubspec.yaml

**Files:**
- Modify: `pubspec.yaml`
- Delete: `lib/app/` (整个目录)
- Delete: `lib/main.dart`
- Delete: `lib/main.mapper.g.dart`
- Delete: `lib/main.reflectable.dart`
- Delete: `test/widget_test.reflectable.dart`
- Keep: `lib/core_control.dart`, `lib/clash_generated_bindings.dart`, `assets/`, 平台代码

- [ ] **Step 1: 删除旧业务代码**

```bash
rm -rf lib/app/ lib/main.dart lib/main.mapper.g.dart lib/main.reflectable.dart
rm -f test/widget_test.reflectable.dart lib/app/pages/index/tray_controller.dart.bak
```

- [ ] **Step 2: 更新 pubspec.yaml**

替换整个 pubspec.yaml 的 dependencies 和 dev_dependencies 部分：

```yaml
name: clash_for_flutter
description: A multi-platform Clash client.
publish_to: 'none'
version: 1.2.7

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # 状态管理
  signals_flutter: ^6.0.0

  # 路由
  go_router: ^14.8.0

  # 网络
  dio: ^5.9.0
  web_socket_channel: ^3.0.3

  # JSON
  json_annotation: ^4.11.0

  # 桌面端
  window_manager: ^0.5.1
  tray_manager: ^0.5.0
  launch_at_startup: ^0.3.1
  desktop_lifecycle: ^0.1.1
  proxy_manager: ^0.0.3
  local_notifier: ^0.1.6
  protocol_handler: ^0.2.0

  # 工具
  ffi: ^2.2.0
  file_picker: ^10.3.7
  package_info_plus: ^9.0.1
  url_launcher: ^6.3.2
  path_provider: ^2.1.5
  path: ^1.9.0
  settings_yaml: ^8.3.1
  intl: ^0.20.2
  timeago: ^3.7.1

  # UI
  cupertino_icons: ^1.0.9
  data_table_2: ^2.7.2
  flutter_staggered_grid_view: ^0.7.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.4.15
  json_serializable: ^6.9.0

flutter:
  uses-material-design: true
  assets:
    - assets/

ffigen:
  name: "Clash"
  output: 'lib/clash_generated_bindings.dart'
  headers:
    entry-points:
      - 'core/libclash.h'
  llvm-path:
    - 'D:\Scoop\apps\llvm\current'
```

- [ ] **Step 3: 运行 flutter pub get**

```bash
flutter pub get
```

Expected: 成功解析所有依赖

- [ ] **Step 4: 创建目录结构**

```bash
mkdir -p lib/domain lib/data/api lib/data/local lib/services lib/presentation/pages lib/presentation/widgets lib/utils
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: 清理旧代码，更新依赖，创建新目录结构"
```

---

### Task 2: Domain 层 — 枚举和模型

**Files:**
- Create: `lib/utils/constants.dart`
- Create: `lib/utils/format.dart`
- Create: `lib/domain/enums.dart`
- Create: `lib/domain/config.dart`
- Create: `lib/domain/proxy.dart`
- Create: `lib/domain/proxy_group.dart`
- Create: `lib/domain/connection.dart`
- Create: `lib/domain/profile.dart`
- Create: `lib/domain/log.dart`
- Create: `lib/domain/net_speed.dart`
- Create: `lib/domain/subscription_info.dart`

- [ ] **Step 1: 创建 utils/constants.dart**

从原 `lib/app/utils/constants.dart` 迁移，去掉对旧代码的依赖：

```dart
import 'dart:io';

class Constants {
  static final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  static late final String rustAddr;
  static late final Directory homeDir;

  static const sourceUrl = "https://github.com/mapleafgo/clash-for-flutter";
  static const homeUrl = "https://mapleafgo.github.io/clash-for-flutter";
  static const releaseUrl = "https://api.github.com/repos/mapleafgo/clash-for-flutter/releases/latest";

  static const profilesPath = "/profiles";
  static const clashConfig = "/config.yaml";
  static const clashForMe = "/cfm.json";
  static const mmdb = "/Country.mmdb";
  static const mmdbNew = "/Country_new.mmdb";
  static const localhost = "127.0.0.1";
  static const logsCapacity = 1000;
}

class Defaults {
  static const mmdbUrl = "http://www.ideame.top/mmdb/Country.mmdb";
  static const delayTestUrl = "http://www.gstatic.com/generate_204";
}
```

- [ ] **Step 2: 创建 utils/format.dart**

```dart
String formatBytes(int value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  double num = value.toDouble();
  var level = 0;
  while (num > 1024 && level < units.length - 1) {
    num /= 1024;
    level++;
  }
  return "${num.toStringAsFixed(1)} ${units[level]}";
}
```

- [ ] **Step 3: 创建 domain/enums.dart**

```dart
enum GroupType { selector, urlTest, fallback, loadBalance }

enum Mode { rule, global, direct }

enum LogLevel { debug, info, warning, error, silent }

enum ProfileType { url, file }

enum SortType { defaults, name, delay }

const _usedProxyNames = {'DIRECT', 'REJECT', 'GLOBAL'};
bool isUsedProxy(String name) => _usedProxyNames.contains(name);

const _groupTypeNames = {'Selector', 'URLTest', 'Fallback', 'LoadBalance'};
bool isGroupType(String type) => _groupTypeNames.contains(type);
```

- [ ] **Step 4: 创建 domain/config.dart**

```dart
import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'config.g.dart';

@JsonSerializable()
class ClashConfig {
  @JsonKey(name: 'mixed-port')
  final int? mixedPort;
  @JsonKey(name: 'redir-port')
  final int? redirPort;
  @JsonKey(name: 'tproxy-port')
  final int? tproxyPort;
  @JsonKey(name: 'allow-lan')
  final bool? allowLan;
  final Mode? mode;
  @JsonKey(name: 'log-level')
  final LogLevel? logLevel;
  final bool? ipv6;
  final TunConfig? tun;

  ClashConfig({
    this.mixedPort,
    this.redirPort,
    this.tproxyPort,
    this.allowLan,
    this.mode,
    this.logLevel,
    this.ipv6,
    this.tun,
  });

  factory ClashConfig.fromJson(Map<String, dynamic> json) =>
      _$ClashConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ClashConfigToJson(this);

  factory ClashConfig.defaults() => ClashConfig(mixedPort: 7890);

  bool get tunEnabled => tun?.enable ?? false;
  int get port => mixedPort ?? 0;
}

@JsonSerializable()
class TunConfig {
  final bool? enable;
  TunConfig({this.enable});
  factory TunConfig.fromJson(Map<String, dynamic> json) =>
      _$TunConfigFromJson(json);
  Map<String, dynamic> toJson() => _$TunConfigToJson(this);
}
```

- [ ] **Step 5: 创建 domain/proxy.dart**

```dart
import 'package:json_annotation/json_annotation.dart';

part 'proxy.g.dart';

@JsonSerializable()
class Proxy {
  final String name;
  final String? type;
  final List<ProxyHistory>? history;

  Proxy({required this.name, this.type, this.history});

  factory Proxy.fromJson(Map<String, dynamic> json) => _$ProxyFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyToJson(this);
}

@JsonSerializable()
class ProxyHistory {
  final String time;
  final int delay;
  ProxyHistory({required this.time, required this.delay});
  factory ProxyHistory.fromJson(Map<String, dynamic> json) =>
      _$ProxyHistoryFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyHistoryToJson(this);
}
```

- [ ] **Step 6: 创建 domain/proxy_group.dart**

```dart
import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'proxy_group.g.dart';

@JsonSerializable()
class ProxyGroup {
  final String name;
  final String type;
  final List<String> all;
  final String now;

  ProxyGroup({
    required this.name,
    required this.type,
    required this.all,
    required this.now,
  });

  factory ProxyGroup.fromJson(Map<String, dynamic> json) =>
      _$ProxyGroupFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyGroupToJson(this);
}
```

- [ ] **Step 7: 创建 domain/connection.dart**

```dart
import 'package:json_annotation/json_annotation.dart';

part 'connection.g.dart';

@JsonSerializable()
class Connection {
  final String id;
  final int upload;
  final int download;
  final String start;
  final List<String> chains;
  final String rule;
  @JsonKey(name: 'rulePayload')
  final String rulePayload;
  final ConnectionMetadata metadata;

  Connection({
    required this.id,
    required this.upload,
    required this.download,
    required this.start,
    required this.chains,
    required this.rule,
    required this.rulePayload,
    required this.metadata,
  });

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionToJson(this);
}

@JsonSerializable()
class ConnectionMetadata {
  final String network;
  final String type;
  final String host;
  @JsonKey(name: 'processPath')
  final String processPath;
  final String sourceIP;
  final String sourcePort;
  final String destinationIP;
  final String destinationPort;
  final String process;
  final String dnsMode;

  ConnectionMetadata({
    required this.network,
    required this.type,
    required this.host,
    required this.processPath,
    required this.sourceIP,
    required this.sourcePort,
    required this.destinationIP,
    required this.destinationPort,
    required this.process,
    required this.dnsMode,
  });

  factory ConnectionMetadata.fromJson(Map<String, dynamic> json) =>
      _$ConnectionMetadataFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionMetadataToJson(this);
}

@JsonSerializable()
class ConnectionsSnapshot {
  final int uploadTotal;
  final int downloadTotal;
  final List<Connection> connections;

  ConnectionsSnapshot({
    required this.uploadTotal,
    required this.downloadTotal,
    required this.connections,
  });

  factory ConnectionsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$ConnectionsSnapshotFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionsSnapshotToJson(this);
}
```

- [ ] **Step 8: 创建 domain/profile.dart**

使用联合类型（sealed class）替代原来的继承体系：

```dart
import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'profile.g.dart';

@JsonSerializable()
class Profile {
  final String file;
  final String name;
  final ProfileType type;
  final DateTime time;
  final String? url;
  final int interval;
  final SubscriptionInfo? userinfo;

  Profile({
    required this.file,
    required this.name,
    required this.type,
    required this.time,
    this.url,
    this.interval = 0,
    this.userinfo,
  });

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
  Map<String, dynamic> toJson() => _$ProfileToJson(this);
}
```

- [ ] **Step 9: 创建 domain/log.dart**

```dart
import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'log.g.dart';

@JsonSerializable()
class LogEntry {
  final LogLevel type;
  final String payload;

  LogEntry({required this.type, required this.payload});

  factory LogEntry.fromJson(Map<String, dynamic> json) =>
      _$LogEntryFromJson(json);
  Map<String, dynamic> toJson() => _$LogEntryToJson(this);
}
```

- [ ] **Step 10: 创建 domain/net_speed.dart**

```dart
import 'package:json_annotation/json_annotation.dart';

part 'net_speed.g.dart';

@JsonSerializable()
class NetSpeed {
  final int up;
  final int down;
  NetSpeed({this.up = 0, this.down = 0});
  factory NetSpeed.fromJson(Map<String, dynamic> json) =>
      _$NetSpeedFromJson(json);
  Map<String, dynamic> toJson() => _$NetSpeedToJson(this);
}
```

- [ ] **Step 11: 创建 domain/subscription_info.dart**

```dart
import 'package:json_annotation/json_annotation.dart';

part 'subscription_info.g.dart';

@JsonSerializable()
class SubscriptionInfo {
  final int? upload;
  final int? download;
  final int? total;
  final int? expire;

  SubscriptionInfo({this.upload, this.download, this.total, this.expire});

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionInfoFromJson(json);
  Map<String, dynamic> toJson() => _$SubscriptionInfoToJson(this);

  factory SubscriptionInfo.fromHeader(String info) {
    final map = <String, int?>{};
    for (final part in info.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2) map[kv[0]] = int.tryParse(kv[1]);
    }
    return SubscriptionInfo(
      upload: map['upload'],
      download: map['download'],
      total: map['total'],
      expire: map['expire'],
    );
  }

  int get used => (upload ?? 0) + (download ?? 0);
}
```

- [ ] **Step 12: 运行 build_runner 生成 .g.dart 文件**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: 生成所有 `.g.dart` 文件，无错误

- [ ] **Step 13: Commit**

```bash
git add lib/domain/ lib/utils/
git commit -m "feat: domain 层 — 枚举和数据模型"
```

---

### Task 3: Data 层 — API 和 WebSocket

**Files:**
- Create: `lib/data/api/clash_api.dart`
- Create: `lib/data/api/ws_streams.dart`
- Create: `lib/data/local/app_config_storage.dart`
- Create: `lib/data/local/core_config_storage.dart`

- [ ] **Step 1: 创建 data/api/clash_api.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:clash_for_flutter/domain/config.dart';
import 'package:clash_for_flutter/domain/connection.dart';
import 'package:clash_for_flutter/domain/log.dart';
import 'package:clash_for_flutter/domain/net_speed.dart';
import 'package:clash_for_flutter/domain/profile.dart';
import 'package:clash_for_flutter/domain/proxy.dart';
import 'package:clash_for_flutter/domain/proxy_group.dart';
import 'package:clash_for_flutter/domain/subscription_info.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

class ClashApi {
  final _clash = Dio(BaseOptions(
    baseUrl: 'http://${Constants.rustAddr}',
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 5),
  ));

  final _download = Dio(BaseOptions(
    headers: {'User-Agent': 'Clash for Flutter'},
    connectTimeout: const Duration(seconds: 3),
  ));

  Future<void> hello() => _clash.get('/');

  Future<Map<String, dynamic>> getProxies() async {
    final res = await _clash.get<Map<String, dynamic>>('/proxies');
    return res.data?['proxies'] as Map<String, dynamic>? ?? {};
  }

  Future<int?> getProxyDelay(String name, String url) async {
    final res = await _clash.get<Map>('/proxies/$name/delay',
        queryParameters: {'timeout': 2900, 'url': url});
    return res.data?['delay'] as int?;
  }

  Future<bool> changeProxy({required String name, required String select}) async {
    final res = await _clash.put('/proxies/$name', data: {'name': select});
    return res.statusCode == HttpStatus.noContent;
  }

  Future<ClashConfig?> getConfigs() async {
    final res = await _clash.get<Map<String, dynamic>>('/configs');
    if (res.data == null) return null;
    return ClashConfig.fromJson(res.data!);
  }

  Future<bool> changeConfig(String path) async {
    final res = await _clash.put('/configs',
        queryParameters: {'force': false}, data: {'path': path});
    return res.statusCode == HttpStatus.noContent;
  }

  Future<bool> patchConfigs(ClashConfig config) async {
    final res = await _clash.patch('/configs', data: config.toJson());
    return res.statusCode == HttpStatus.noContent;
  }

  Future<bool> closeAllConnections() async {
    final res = await _clash.delete('/connections');
    return res.statusCode == HttpStatus.noContent;
  }

  Future<bool> closeConnection(String id) async {
    final res = await _clash.delete('/connections/$id');
    return res.statusCode == HttpStatus.noContent;
  }

  Future<String?> getVersion() async {
    final res = await _clash.get<Map<String, dynamic>>('/version');
    return res.data?['version'] as String?;
  }

  Future<Profile> downloadSubscription({
    required String url,
    required String profilesDir,
    String? name,
  }) async {
    final time = DateTime.now();
    final file = '${time.millisecondsSinceEpoch}.yaml';
    final savePath = p.join(profilesDir, file);

    final resp = await _download.download(url, savePath);

    String fileName = name ?? '';
    if (fileName.isEmpty) {
      final headerDis = resp.headers.value('content-disposition');
      if (headerDis != null) {
        final disposition = HeaderValue.parse(headerDis);
        for (final entry in disposition.parameters.entries) {
          if (entry.key.startsWith('filename')) {
            fileName = entry.key == 'filename*'
                ? Uri.decodeComponent(entry.value.split("'").last)
                : entry.value;
          }
        }
      }
      if (fileName.isEmpty) fileName = file;
    }

    SubscriptionInfo? info;
    final headerInfo = resp.headers.value('subscription-userinfo');
    if (headerInfo != null) info = SubscriptionInfo.fromHeader(headerInfo);

    int interval = 0;
    final intervalStr = resp.headers.value('profile-update-interval');
    if (intervalStr != null) interval = int.tryParse(intervalStr) ?? 0;

    return Profile(
      file: file,
      name: fileName,
      type: ProfileType.url,
      time: time,
      url: url,
      interval: interval,
      userinfo: info,
    );
  }

  Future<String> downloadFile(String url, String savePath,
      {void Function(int, int)? onProgress}) {
    return _download
        .download(url, savePath, onReceiveProgress: onProgress)
        .then((_) => savePath);
  }

  Future<String?> checkLatestVersion() async {
    final res = await Dio().get<Map<String, dynamic>>(Constants.releaseUrl);
    return res.data?['tag_name'] as String?;
  }
}
```

- [ ] **Step 2: 创建 data/api/ws_streams.dart**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:clash_for_flutter/domain/connection.dart';
import 'package:clash_for_flutter/domain/log.dart';
import 'package:clash_for_flutter/domain/net_speed.dart';
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

String _ws(String path) => 'ws://${Constants.rustAddr}$path';

Stream<NetSpeed> trafficStream() {
  final channel = WebSocketChannel.connect(Uri.parse(_ws('/traffic')));
  return channel.stream.map((e) => NetSpeed.fromJson(jsonDecode(e)));
}

Stream<LogEntry> logsStream(LogLevel level) {
  final uri = Uri.parse(_ws('/logs?level=${level.name}'));
  final channel = WebSocketChannel.connect(uri);
  return channel.stream.map((e) {
    final entry = LogEntry.fromJson(jsonDecode(e));
    return entry;
  });
}

Stream<ConnectionsSnapshot> connectionsStream() {
  final channel = WebSocketChannel.connect(Uri.parse(_ws('/connections')));
  return channel.stream.map((e) =>
      ConnectionsSnapshot.fromJson(jsonDecode(e)));
}
```

- [ ] **Step 3: 创建 data/local/app_config_storage.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:clash_for_flutter/domain/profile.dart';
import 'package:clash_for_flutter/utils/constants.dart';

class AppConfigStorage {
  static final _file =
      File('${Constants.homeDir.path}${Constants.clashForMe}');

  static AppStoredConfig load() {
    if (!_file.existsSync()) return AppStoredConfig.empty();
    final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    return AppStoredConfig.fromJson(json);
  }

  static void save(AppStoredConfig config) {
    _file.createSync(recursive: true);
    _file.writeAsStringSync(jsonEncode(config.toJson()));
  }
}

class AppStoredConfig {
  final String? selectedFile;
  final List<Profile> profiles;
  final String mmdbUrl;
  final String delayTestUrl;
  final bool? tunIf;

  AppStoredConfig({
    this.selectedFile,
    required this.profiles,
    required this.mmdbUrl,
    required this.delayTestUrl,
    this.tunIf,
  });

  factory AppStoredConfig.fromJson(Map<String, dynamic> json) =>
      AppStoredConfig(
        selectedFile: json['selected-file'] as String?,
        profiles: (json['profiles'] as List?)
                ?.map((e) => Profile.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        mmdbUrl: json['mmdb-url'] as String? ?? Defaults.mmdbUrl,
        delayTestUrl: json['delay-test-url'] as String? ?? Defaults.delayTestUrl,
        tunIf: json['tun-if'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'selected-file': selectedFile,
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'mmdb-url': mmdbUrl,
        'delay-test-url': delayTestUrl,
        'tun-if': tunIf,
      };

  factory AppStoredConfig.empty() => AppStoredConfig(
        profiles: [],
        mmdbUrl: Defaults.mmdbUrl,
        delayTestUrl: Defaults.delayTestUrl,
      );
}
```

- [ ] **Step 4: 创建 data/local/core_config_storage.dart**

```dart
import 'dart:io';

import 'package:clash_for_flutter/domain/config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:settings_yaml/settings_yaml.dart';

class CoreConfigStorage {
  static final _path =
      '${Constants.homeDir.path}${Constants.clashConfig}';

  static bool exists() => File(_path).existsSync();

  static ClashConfig load() {
    final yaml = SettingsYaml.load(pathToSettings: _path);
    return ClashConfig(
      mixedPort: yaml['mixed-port'] as int?,
      redirPort: yaml['redir-port'] as int?,
      tproxyPort: yaml['tproxy-port'] as int?,
      allowLan: yaml['allow-lan'] as bool?,
      mode: null,
      logLevel: null,
      ipv6: yaml['ipv6'] as bool?,
    );
  }

  static void save(ClashConfig config) {
    final yaml = SettingsYaml.load(pathToSettings: _path);
    if (config.mixedPort != null) yaml['mixed-port'] = config.mixedPort;
    if (config.redirPort != null) yaml['redir-port'] = config.redirPort;
    if (config.tproxyPort != null) yaml['tproxy-port'] = config.tproxyPort;
    if (config.allowLan != null) yaml['allow-lan'] = config.allowLan;
    if (config.mode != null) yaml['mode'] = config.mode!.name;
    if (config.logLevel != null) yaml['log-level'] = config.logLevel!.name;
    if (config.ipv6 != null) yaml['ipv6'] = config.ipv6;
    yaml.save();
  }

  static void createDefault() {
    if (!exists()) {
      File(_path).createSync(recursive: true);
      File(_path).writeAsStringSync('mixed-port: 7890\n');
    }
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add lib/data/ lib/utils/
git commit -m "feat: data 层 — API 客户端、WebSocket 流、本地存储"
```

---

### Task 4: Services 层 — 全局状态

**Files:**
- Create: `lib/services/clash_api.dart` (全局单例导出)
- Create: `lib/services/app_config.dart`
- Create: `lib/services/core_config.dart`
- Create: `lib/services/tray_service.dart`

- [ ] **Step 1: 创建 services/clash_api.dart**

全局单例，替代原 Modular DI：

```dart
import 'package:clash_for_flutter/data/api/clash_api.dart';

final api = ClashApi();
```

- [ ] **Step 2: 创建 services/app_config.dart**

```dart
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
```

- [ ] **Step 3: 创建 services/core_config.dart**

```dart
import 'package:clash_for_flutter/data/local/core_config_storage.dart';
import 'package:clash_for_flutter/domain/config.dart';
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:clash_for_flutter/core_control.dart' as core;
import 'package:signals_flutter/signals_flutter.dart';

final clashConfig = signal(ClashConfig.defaults());

Timer? _syncTimer;

void initCoreConfig() {
  effect(() {
    clashConfig.value;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      CoreConfigStorage.save(clashConfig.value);
      api.patchConfigs(clashConfig.value);
    });
  });
}

Future<void> syncFromCore() async {
  final config = await api.getConfigs();
  if (config != null) clashConfig.value = config;
}

void updateClashConfig({
  int? mixedPort,
  int? redirPort,
  int? tproxyPort,
  bool? allowLan,
  Mode? mode,
  LogLevel? logLevel,
  bool? ipv6,
}) {
  final old = clashConfig.value;
  clashConfig.value = ClashConfig(
    mixedPort: mixedPort ?? old.mixedPort,
    redirPort: redirPort ?? old.redirPort,
    tproxyPort: tproxyPort ?? old.tproxyPort,
    allowLan: allowLan ?? old.allowLan,
    mode: mode ?? old.mode,
    logLevel: logLevel ?? old.logLevel,
    ipv6: ipv6 ?? old.ipv6,
    tun: old.tun,
  );
}

Future<void> openTun() async {
  if (Constants.isDesktop) {
    await api.patchConfigs(ClashConfig(tun: TunConfig(enable: true)));
  } else {
    await core.CoreControl.startVpn();
  }
  await syncFromCore();
}

Future<void> closeTun() async {
  if (Constants.isDesktop) {
    await api.patchConfigs(ClashConfig(tun: TunConfig(enable: false)));
  } else {
    await core.CoreControl.stopVpn();
  }
  await syncFromCore();
}
```

- [ ] **Step 4: 创建 services/tray_service.dart**

```dart
import 'dart:io';

import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initTray() async {
  if (!Constants.isDesktop) return;

  await trayManager.setIcon(
    Platform.isWindows ? 'assets/icon.ico' : 'assets/logo_64.png',
  );

  effect(() => _rebuildMenu(systemProxy.value, clashConfig.value.mode));
}

Future<void> _rebuildMenu(bool proxyOn, Mode? mode) async {
  final menu = Menu(items: [
    MenuItem(key: 'show', label: '显示窗口'),
    MenuItem.separator(),
    MenuItem.checkbox(key: 'proxy', label: '代理', checked: proxyOn),
    MenuItem.submenu(
      label: '模式',
      submenu: Menu(items: [
        MenuItem.checkbox(key: Mode.rule.name, label: 'Rule', checked: mode == Mode.rule),
        MenuItem.checkbox(key: Mode.global.name, label: 'Global', checked: mode == Mode.global),
        MenuItem.checkbox(key: Mode.direct.name, label: 'Direct', checked: mode == Mode.direct),
      ]),
    ),
    MenuItem(key: 'exit', label: '退出'),
  ]);
  await trayManager.setContextMenu(menu);
}

class TrayListenerImpl with TrayListener {
  @override
  void onTrayIconMouseDown() => windowManager.show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
      case 'proxy':
        if (menuItem.checked ?? false) {
          await closeProxy();
        } else {
          await openProxy();
        }
      case 'exit':
        await closeProxy();
        windowManager.close().then((_) => windowManager.destroy());
      default:
        final mode = Mode.values.where((m) => m.name == menuItem.key);
        if (mode.isNotEmpty) updateClashConfig(mode: mode.first);
    }
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add lib/services/
git commit -m "feat: services 层 — 全局状态和托盘服务"
```

---

### Task 5: Presentation 层 — 路由和布局壳

**Files:**
- Create: `lib/presentation/router.dart`
- Create: `lib/presentation/app.dart`
- Create: `lib/presentation/pages/desktop_shell.dart`
- Create: `lib/presentation/pages/mobile_shell.dart`
- Create: `lib/presentation/widgets/sys_app_bar.dart`
- Create: `lib/presentation/widgets/loading.dart`

- [ ] **Step 1: 创建 presentation/widgets/sys_app_bar.dart**

```dart
import 'package:flutter/material.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const SysAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: true,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
```

- [ ] **Step 2: 创建 presentation/widgets/loading.dart**

```dart
import 'package:flutter/material.dart';

class Loading extends StatelessWidget {
  final OverlayEntry _entry;
  Loading._() : _entry = OverlayEntry(
    builder: (_) => const ColoredBox(
      color: Color(0x66000000),
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  factory Loading.show(BuildContext context) {
    final loading = Loading._();
    Overlay.of(context).insert(loading._entry);
    return loading;
  }

  void remove() => _entry.remove();
}
```

- [ ] **Step 3: 创建 presentation/router.dart**

```dart
import 'package:clash_for_flutter/presentation/pages/connections_page.dart';
import 'package:clash_for_flutter/presentation/pages/desktop_shell.dart';
import 'package:clash_for_flutter/presentation/pages/home_page.dart';
import 'package:clash_for_flutter/presentation/pages/logs_page.dart';
import 'package:clash_for_flutter/presentation/pages/mobile_shell.dart';
import 'package:clash_for_flutter/presentation/pages/profiles_page.dart';
import 'package:clash_for_flutter/presentation/pages/proxies_page.dart';
import 'package:clash_for_flutter/presentation/pages/settings_page.dart';
import 'package:clash_for_flutter/presentation/pages/init_page.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final _shellBuilder = Constants.isDesktop
    ? (_, __, shell) => DesktopShell(shell: shell)
    : (_, __, shell) => MobileShell(shell: shell);

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const InitPage(),
    ),
    StatefulShellRoute.indexedStack(
      builder: _shellBuilder,
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/proxies', builder: (_, __) => const ProxiesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/logs', builder: (_, __) => const LogsPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/connections', builder: (_, __) => const ConnectionsPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/profiles', builder: (_, __) => const ProfilesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
        ]),
      ],
    ),
  ],
);

class NavItem {
  final String path;
  final String label;
  final IconData icon;
  const NavItem(this.path, this.label, this.icon);
}

const navItems = [
  NavItem('/home', '首页', Icons.home_outlined),
  NavItem('/proxies', '代理', Icons.cloud_outlined),
  NavItem('/logs', '日志', Icons.list_alt_outlined),
  NavItem('/connections', '连接', Icons.link_rounded),
  NavItem('/profiles', '订阅', Icons.code_rounded),
  NavItem('/settings', '设置', Icons.settings_outlined),
];
```

- [ ] **Step 4: 创建 presentation/pages/desktop_shell.dart**

```dart
import 'package:clash_for_flutter/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DesktopShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const DesktopShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => _navigate(context, i),
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Clash', style: Theme.of(context).textTheme.titleMedium),
          ),
          destinations: navItems
              .map((e) => NavigationRailDestination(
                    icon: Icon(e.icon),
                    label: Text(e.label),
                  ))
              .toList(),
        ),
        Expanded(child: shell),
      ]),
    );
  }

  void _navigate(BuildContext context, int index) {
    if (shell.currentIndex == index) return;
    context.go(navItems[index].path);
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }
}
```

- [ ] **Step 5: 创建 presentation/pages/mobile_shell.dart**

```dart
import 'package:clash_for_flutter/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MobileShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MobileShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: navItems
            .map((e) => NavigationDestination(icon: Icon(e.icon), label: e.label))
            .toList(),
      ),
    );
  }
}
```

- [ ] **Step 6: 创建 presentation/app.dart**

```dart
import 'package:clash_for_flutter/presentation/router.dart';
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Clash for Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/
git commit -m "feat: presentation 层 — 路由、布局壳、通用组件"
```

---

### Task 6: Presentation 层 — 初始化页和首页

**Files:**
- Create: `lib/presentation/pages/init_page.dart`
- Create: `lib/presentation/pages/home_page.dart`

- [ ] **Step 1: 创建 init_page.dart**

```dart
import 'package:clash_for_flutter/data/api/ws_streams.dart' as ws;
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:clash_for_flutter/core_control.dart' as core;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class InitPage extends StatefulWidget {
  const InitPage({super.key});
  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  double _progress = 0;
  String _status = '初始化中...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await api.hello();
      initCoreConfig();
      await syncFromCore();
      initAppConfig();
      await _downloadMmdbIfNeeded();
      await api.changeConfig(
        p.join(Constants.homeDir.path, Constants.profilesPath, selectedFile.value ?? ''),
      );
      if (clashConfig.value.tunEnabled) {
        await openTun();
      }
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e')),
        );
      }
    }
  }

  Future<void> _downloadMmdbIfNeeded() async {
    final path = '${Constants.homeDir.path}${Constants.mmdb}';
    if (File(path).existsSync()) return;

    setState(() {
      _status = '正在初始下载 Country.mmdb 文件';
      _progress = 0;
    });

    await api.downloadFile(
      mmdbUrl.value,
      path,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_status),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 2: 创建 home_page.dart**

```dart
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

const _btnSize = Size(200, 70);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: 'Clash for Flutter'),
      body: Center(
        child: Watch((context) {
          final enabled = tunIf.value!
              ? clashConfig.value.tunEnabled
              : systemProxy.value;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            _ToggleBtn(enabled: enabled),
            if (Constants.isDesktop) ...[
              const SizedBox(height: 24),
              _TunSwitch(),
            ],
          ]);
        }),
      ),
    );
  }
}

class _ToggleBtn extends StatefulWidget {
  final bool enabled;
  const _ToggleBtn({required this.enabled});
  @override
  State<_ToggleBtn> createState() => _ToggleBtnState();
}

class _ToggleBtnState extends State<_ToggleBtn> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox.fromSize(
        size: _btnSize,
        child: const Card(
          color: Colors.grey,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return SizedBox.fromSize(
      size: _btnSize,
      child: Card(
        color: widget.enabled ? Colors.green : null,
        child: InkWell(
          onTap: _toggle,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.enabled ? Icons.flight_land : Icons.flight_takeoff),
            Text(widget.enabled ? '关闭' : '开启'),
          ]),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      if (tunIf.value!) {
        await (clashConfig.value.tunEnabled ? closeTun() : openTun());
      } else {
        await (systemProxy.value ? closeProxy() : openProxy());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _TunSwitch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Watch((context) => SwitchListTile(
          title: const Text('TUN 模式'),
          subtitle: const Text('需要管理员权限'),
          value: clashConfig.value.tunEnabled,
          onChanged: (v) async {
            await (v ? openTun() : closeTun());
          },
        ));
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/pages/init_page.dart lib/presentation/pages/home_page.dart
git commit -m "feat: 初始化页和首页"
```

---

### Task 7: Presentation 层 — 代理页

**Files:**
- Create: `lib/presentation/pages/proxies_page.dart`

- [ ] **Step 1: 创建 proxies_page.dart**

```dart
import 'package:clash_for_flutter/data/api/clash_api.dart';
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/domain/proxy.dart';
import 'package:clash_for_flutter/domain/proxy_group.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

final _groups = signal<List<ProxyGroup>>([]);
final _proxies = signal<Map<String, dynamic>>({});
final _sortType = signal(SortType.defaults);
final _loading = signal(false);

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({super.key});
  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await api.getProxies();
    final groupList = <ProxyGroup>[];
    final allProxies = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        allProxies[key] = value;
        if (isGroupType(value['type'] as String? ?? '') &&
            !isUsedProxy(key)) {
          groupList.add(ProxyGroup.fromJson(value));
        }
      }
    });

    if (clashConfig.value.mode == Mode.global) {
      final? global = allProxies['GLOBAL'];
      if (global is Map<String, dynamic>) {
        groupList.insert(0, ProxyGroup.fromJson(global));
      }
    }

    _groups.value = groupList;
    _proxies.value = allProxies;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: '代理'),
      floatingActionButton: Watch((context) {
        if (_loading.value) return const CircularProgressIndicator();
        return FloatingActionButton(
          child: const Icon(Icons.speed),
          onPressed: _loading.value ? null : _testAllDelay,
        );
      }),
      body: Watch((context) {
        final groups = _groups.value;
        if (groups.isEmpty) return const Center(child: Text('暂无代理'));
        return DefaultTabController(
          length: groups.length,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabs: groups.map((g) => Tab(text: g.name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                children: groups.map((g) => _ProxyList(
                      group: g,
                      onRefresh: _load,
                    )).toList(),
              ),
            ),
          ]),
        );
      }),
    );
  }

  Future<void> _testAllDelay() async {
    _loading.value = true;
    try {
      final group = _groups.value.isNotEmpty ? _groups.value[0] : null;
      if (group == null) return;
      await Future.wait(group.all.map((name) async {
        try {
          await api.getProxyDelay(name, delayTestUrl.value);
        } catch (_) {}
      }));
      await _load();
    } finally {
      _loading.value = false;
    }
  }
}

class _ProxyList extends StatelessWidget {
  final ProxyGroup group;
  final VoidCallback onRefresh;
  const _ProxyList({required this.group, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final sorted = _sortedItems();
      return ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (_, i) => _ProxyTile(
          item: sorted[i],
          selected: sorted[i].name == group.now,
          onRefresh: onRefresh,
        ),
      );
    });
  }

  List<_ProxyItem> _sortedItems() {
    final items = group.all
        .where((name) => !isUsedProxy(name))
        .map((name) {
      final data = _proxies.value[name];
      final type = data is Map ? data['type'] as String? : null;
      int delay = -1;
      if (data is Map<String, dynamic>) {
        final history = data['history'] as List?;
        if (history != null && history.isNotEmpty) {
          delay = (history.last['delay'] as int?) ?? -1;
        }
      }
      return _ProxyItem(name: name, type: type ?? '', delay: delay);
    }).toList();

    switch (_sortType.value) {
      case SortType.name:
        items.sort((a, b) => a.name.compareTo(b.name));
      case SortType.delay:
        items.sort((a, b) => a.delay.compareTo(b.delay));
      case SortType.defaults:
        break;
    }
    return items;
  }
}

class _ProxyTile extends StatelessWidget {
  final _ProxyItem item;
  final bool selected;
  final VoidCallback onRefresh;
  const _ProxyTile({
    required this.item,
    required this.selected,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      dense: true,
      title: Text(item.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(item.type, style: const TextStyle(fontSize: 12)),
      trailing: _delayWidget(item.delay),
      onTap: () async {
        // 需要找到包含此代理的 group name 来切换
        final group = _groups.value.firstWhere(
          (g) => g.all.contains(item.name),
        );
        await api.changeProxy(name: group.name, select: item.name);
        onRefresh();
      },
    );
  }
}

Widget _delayWidget(int delay) {
  if (delay < 0) return const SizedBox.shrink();
  if (delay == 0) return const Text('...');
  return Text('${delay}ms');
}

class _ProxyItem {
  final String name;
  final String type;
  final int delay;
  _ProxyItem({required this.name, required this.type, required this.delay});
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/pages/proxies_page.dart
git commit -m "feat: 代理页"
```

---

### Task 8: Presentation 层 — 日志页

**Files:**
- Create: `lib/presentation/pages/logs_page.dart`

- [ ] **Step 1: 创建 logs_page.dart**

```dart
import 'dart:async';
import 'dart:collection';

import 'package:clash_for_flutter/data/api/ws_streams.dart' as ws;
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/domain/log.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:intl/intl.dart';

final _logs = signal<Queue<LogEntry>>(Queue());
final _logLevel = signal(LogLevel.info);
StreamSubscription? _logSub;

void startLogSubscription() {
  effect(() {
    _logSub?.cancel();
    _logSub = ws.logsStream(_logLevel.value).listen((entry) {
      final queue = Queue<LogEntry>.from(_logs.value);
      if (queue.length >= Constants.logsCapacity) queue.removeFirst();
      queue.add(entry);
      _logs.value = queue;
    });
  });
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: '日志'),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'filter',
            mini: true,
            child: const Icon(Icons.filter_list),
            onPressed: _showFilter,
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'clear',
            mini: true,
            child: const Icon(Icons.delete),
            onPressed: () => _logs.value = Queue(),
          ),
        ],
      ),
      body: Watch((context) {
        final logs = _logs.value.toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _scrollController,
          itemCount: logs.length,
          itemBuilder: (_, i) {
            final log = logs[i];
            final time = DateFormat('yyyy/MM/dd HH:mm:ss')
                .format(DateTime.now());
            return SelectableText(
              '[$time] [${log.type.name.toUpperCase()}] ${log.payload}',
              style: const TextStyle(fontSize: 12),
            );
          },
        );
      }),
    );
  }

  void _showFilter() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: LogLevel.values.map((level) => ListTile(
              title: Text(level.name.toUpperCase()),
              onTap: () {
                _logLevel.value = level;
                Navigator.pop(context);
              },
            )).toList(),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/pages/logs_page.dart
git commit -m "feat: 日志页"
```

---

### Task 9: Presentation 层 — 连接页

**Files:**
- Create: `lib/presentation/pages/connections_page.dart`

- [ ] **Step 1: 创建 connections_page.dart**

```dart
import 'dart:async';

import 'package:clash_for_flutter/data/api/ws_streams.dart' as ws;
import 'package:clash_for_flutter/domain/connection.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/utils/format.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

final _connections = signal<List<Connection>>([]);
final _prevConnections = signal<Map<String, Connection>>({});
StreamSubscription? _connSub;

void startConnectionsSubscription() {
  _connSub = ws.connectionsStream().listen((snapshot) {
    final prev = {for (final c in _connections.value) c.id: c};
    _prevConnections.value = prev;
    _connections.value = snapshot.connections
      ..sort((a, b) => b.start.compareTo(a.start));
  });
}

class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '连接'),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.close),
        onPressed: () async {
          await api.closeAllConnections();
        },
      ),
      body: Watch((context) {
        final conns = _connections.value;
        final prev = _prevConnections.value;
        return PaginatedDataTable2(
          columns: const [
            DataColumn2(label: Text('域名'), size: ColumnSize.L),
            DataColumn2(label: Text('网络'), size: ColumnSize.S),
            DataColumn2(label: Text('类型'), size: ColumnSize.M),
            DataColumn2(label: Text('节点链'), size: ColumnSize.L),
            DataColumn2(label: Text('规则'), size: ColumnSize.L),
            DataColumn2(label: Text('进程'), size: ColumnSize.S),
            DataColumn2(label: Text('速率'), size: ColumnSize.M),
            DataColumn2(label: Text('上传'), size: ColumnSize.S),
            DataColumn2(label: Text('下载'), size: ColumnSize.S),
            DataColumn2(label: Text('来源IP'), size: ColumnSize.S),
            DataColumn2(label: Text('连接时间'), size: ColumnSize.M),
          ],
          source: _ConnSource(conns, prev, context),
          rowsPerPage: 20,
          minWidth: 1200,
        );
      }),
    );
  }
}

class _ConnSource extends DataTableSource {
  final List<Connection> conns;
  final Map<String, Connection> prev;
  final BuildContext context;

  _ConnSource(this.conns, this.prev, this.context);

  @override
  int get rowCount => conns.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;

  @override
  DataRow getRow(int index) {
    final c = conns[index];
    final old = prev[c.id];
    final speedUp = old != null ? c.upload - old.upload : 0;
    final speedDown = old != null ? c.download - old.download : 0;
    final host = c.metadata.host.isNotEmpty
        ? c.metadata.host
        : c.metadata.destinationIP;

    return DataRow(cells: [
      DataCell(Text(host), onTap: () => _showDetail(context, c)),
      DataCell(Text(c.metadata.network)),
      DataCell(Text(c.metadata.type)),
      DataCell(Text(c.chains.join(' → '))),
      DataCell(Text(c.rule)),
      DataCell(Text(c.metadata.process)),
      DataCell(Text('${formatBytes(speedDown)}/s')),
      DataCell(Text(formatBytes(c.upload))),
      DataCell(Text(formatBytes(c.download))),
      DataCell(Text(c.metadata.sourceIP)),
      DataCell(Text(timeago.format(DateTime.tryParse(c.start) ?? DateTime.now(), locale: 'zh_cn'))),
    ]);
  }

  void _showDetail(BuildContext context, Connection c) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.metadata.host),
        content: Table(
          children: [
            _row('ID', c.id),
            _row('Network', c.metadata.network),
            _row('Type', c.metadata.type),
            _row('Host', c.metadata.host),
            _row('Destination IP', c.metadata.destinationIP),
            _row('Source IP', c.metadata.sourceIP),
            _row('Process', c.metadata.processPath),
            _row('Rule', c.rule),
            _row('Upload', formatBytes(c.upload)),
            _row('Download', formatBytes(c.download)),
            _row('Status', '连接中'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await api.closeConnection(c.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('关闭连接'),
          ),
        ],
      ),
    );
  }

  TableRow _row(String label, String value) => TableRow(
        children: [Padding(
          padding: const EdgeInsets.all(4),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ), Padding(
          padding: const EdgeInsets.all(4),
          child: Text(value),
        )],
      );
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/pages/connections_page.dart
git commit -m "feat: 连接页"
```

---

### Task 10: Presentation 层 — 订阅页

**Files:**
- Create: `lib/presentation/pages/profiles_page.dart`

- [ ] **Step 1: 创建 profiles_page.dart**

```dart
import 'dart:io';

import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/domain/profile.dart';
import 'package:clash_for_flutter/domain/subscription_info.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/utils/constants.dart';
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
    return Card(
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
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
          if (profile.userinfo != null) ...[
            const SizedBox(height: 8),
            _TrafficBar(info: profile.userinfo!),
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/pages/profiles_page.dart
git commit -m "feat: 订阅页"
```

---

### Task 11: Presentation 层 — 设置页

**Files:**
- Create: `lib/presentation/pages/settings_page.dart`

- [ ] **Step 1: 创建 settings_page.dart**

```dart
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '设置'),
      body: Watch((context) {
        final config = clashConfig.value;
        return ListView(children: [
          _Section('Clash 代理端口'),
          _PortTile('Mixed Port', config.mixedPort, (v) => updateClashConfig(mixedPort: v)),
          _PortTile('Redir Port', config.redirPort, (v) => updateClashConfig(redirPort: v)),
          _PortTile('TProxy Port', config.tproxyPort, (v) => updateClashConfig(tproxyPort: v)),
          _Section('Clash 设置'),
          SwitchListTile(
            title: const Text('允许局域网'),
            value: config.allowLan ?? false,
            onChanged: (v) => updateClashConfig(allowLan: v),
          ),
          SwitchListTile(
            title: const Text('IPv6'),
            value: config.ipv6 ?? false,
            onChanged: (v) => updateClashConfig(ipv6: v),
          ),
          ListTile(
            title: const Text('代理模式'),
            trailing: DropdownButton<Mode>(
              value: config.mode ?? Mode.rule,
              items: Mode.values.map((m) => DropdownMenuItem(
                value: m, child: Text(m.name))).toList(),
              onChanged: (m) { if (m != null) updateClashConfig(mode: m); },
            ),
          ),
          ListTile(
            title: const Text('日志等级'),
            trailing: DropdownButton<LogLevel>(
              value: config.logLevel ?? LogLevel.info,
              items: LogLevel.values.map((l) => DropdownMenuItem(
                value: l, child: Text(l.name))).toList(),
              onChanged: (l) { if (l != null) updateClashConfig(logLevel: l); },
            ),
          ),
          _Section('其他设置'),
          _UrlTile('MMDB Url', mmdbUrl.value, (v) => mmdbUrl.value = v),
          _UrlTile('延迟测试 Url', delayTestUrl.value, (v) => delayTestUrl.value = v),
          _Section('关于'),
          ListTile(
            title: const Text('官方网站'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse(Constants.homeUrl)),
          ),
          ListTile(
            title: const Text('源码仓库'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse(Constants.sourceUrl)),
          ),
          _CheckUpdateTile(),
        ]);
      }),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _PortTile extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onChanged;
  const _PortTile(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 100,
        child: TextFormField(
          initialValue: value?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onFieldSubmitted: (v) {
            final port = int.tryParse(v);
            if (port != null) onChanged(port);
          },
        ),
      ),
    );
  }
}

class _UrlTile extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _UrlTile(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(label),
            content: TextFormField(
              initialValue: value,
              onFieldSubmitted: (v) => Navigator.pop(context, v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(context, value),
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (result != null) onChanged(result);
      },
    );
  }
}

class _CheckUpdateTile extends StatefulWidget {
  @override
  State<_CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends State<_CheckUpdateTile> {
  int _state = 0; // 0=idle, 1=checking, 2=up-to-date, -1=error

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('检查更新'),
      trailing: _trailing(),
      onTap: _state == 1 ? null : _check,
    );
  }

  Widget _trailing() {
    return switch (_state) {
      1 => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      2 => const Icon(Icons.check, color: Colors.green),
      -1 => const Icon(Icons.error, color: Colors.red),
      _ => const Icon(Icons.refresh),
    };
  }

  Future<void> _check() async {
    setState(() => _state = 1);
    try {
      await api.checkLatestVersion();
      if (mounted) setState(() => _state = 2);
    } catch (_) {
      if (mounted) setState(() => _state = -1);
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/pages/settings_page.dart
git commit -m "feat: 设置页"
```

---

### Task 12: 入口 main.dart 重写

**Files:**
- Create: `lib/main.dart`

- [ ] **Step 1: 创建 main.dart**

```dart
import 'dart:io';
import 'dart:math';

import 'package:clash_for_flutter/presentation/app.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:clash_for_flutter/core_control.dart' as core;
import 'package:clash_for_flutter/data/local/core_config_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Constants.isDesktop) {
    await windowManager.ensureInitialized();
    if (!Platform.isLinux) await protocolHandler.register('clash');
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        minimumSize: Size(460, 600),
        size: Size(900, 650),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  timeago.setLocaleMessages('zh_cn', TimeagoZhCnMessages());

  core.CoreControl.init();
  Constants.homeDir = await getApplicationSupportDirectory();
  await core.CoreControl.setHomeDir(Constants.homeDir);

  CoreConfigStorage.createDefault();

  final addr = '${Constants.localhost}:${Random().nextInt(9999) + 10000}';
  Constants.rustAddr =
      await core.CoreControl.startRust(addr) ?? '';
  await core.CoreControl.startService();

  runApp(const App());
}

class TimeagoZhCnMessages extends timeago.LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => '';
  @override
  String suffixAgo() => '前';
  @override
  String suffixFromNow() => '后';
  @override
  String lessThanOneMinute(int seconds) => '刚刚';
  @override
  String aboutAMinute(int minutes) => '1 分钟';
  @override
  String minutes(int minutes) => '$minutes 分钟';
  @override
  String aboutAnHour(int minutes) => '1 小时';
  @override
  String hours(int hours) => '$hours 小时';
  @override
  String aDay(int hours) => '1 天';
  @override
  String days(int days) => '$days 天';
  @override
  String aboutAMonth(int days) => '1 个月';
  @override
  String months(int months) => '$months 个月';
  @override
  String aboutAYear(int year) => '1 年';
  @override
  String years(int years) => '$years 年';
  @override
  String wordSeparator() => '';
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/main.dart
git commit -m "feat: 重写 main.dart 入口"
```

---

### Task 13: 编译验证 + flutter analyze

**Files:**
- Possibly fix issues in any files above

- [ ] **Step 1: 运行 build_runner 确保所有 .g.dart 文件生成**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 2: 运行 flutter analyze**

```bash
flutter analyze
```

Expected: 零 error，零 warning（clash_generated_bindings.dart 中的 warning 可忽略）

- [ ] **Step 3: 修复所有 analyze 报告的问题**

如有 error 或 warning（除 clash_generated_bindings.dart 外），逐个修复。

- [ ] **Step 4: 运行构建验证（Linux 桌面）**

```bash
flutter build linux
```

Expected: 构建成功

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix: 编译验证修复"
```

---

### Task 14: 运行时验证

- [ ] **Step 1: 启动应用**

```bash
flutter run -d linux
```

- [ ] **Step 2: 逐项验证设计文档中的验收检查点**

对照 `docs/superpowers/specs/2026-04-24-modernize-rewrite-design.md` 中的功能清单，逐项勾选验证。

- [ ] **Step 3: 修复发现的问题**

- [ ] **Step 4: 最终 Commit**

```bash
git add -A
git commit -m "fix: 运行时验证修复"
```

---

## Self-Review

**Spec coverage check:**
- 导航与布局: Task 5 (router, desktop_shell, mobile_shell)
- 首页: Task 6 (home_page)
- 代理页: Task 7 (proxies_page)
- 日志页: Task 8 (logs_page)
- 连接页: Task 9 (connections_page)
- 订阅页: Task 10 (profiles_page)
- 设置页: Task 11 (settings_page)
- 托盘: Task 4 (tray_service)
- 初始化: Task 6 (init_page)
- 窗口管理: Task 6 (init_page) + Task 4 (tray_service)
- 数据层: Task 3 (clash_api, ws_streams, storage)
- Signals 状态: Task 4 (app_config, core_config)
- go_router 路由: Task 5 (router)
- json_serializable: Task 2 (domain models)

**Placeholder scan:** 无 TBD/TODO/等占位符

**Type consistency:**
- `ClashConfig` 定义在 domain/config.dart，被 services/core_config.dart 和 data/api/clash_api.dart 引用
- `Profile` 定义在 domain/profile.dart，被 services/app_config.dart 和 presentation/pages/profiles_page.dart 引用
- `api` 全局实例定义在 services/clash_api.dart，被多处引用
- 信号名称一致：`systemProxy`, `selectedFile`, `profiles`, `clashConfig`, `_groups`, `_proxies`, `_logs`, `_connections`
