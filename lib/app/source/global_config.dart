import 'dart:ffi';
import 'dart:io';

import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:clash_for_flutter/clash_generated_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxy_manager/proxy_manager.dart';

part 'global_config.g.dart';

class GlobalConfig = ConfigFileBase with _$GlobalConfig;

final proxyManager = ProxyManager();

abstract class ConfigFileBase extends Disposable with Store {
  final _request = Modular.get<Request>();
  late Directory configDir;
  late final Clash clash;
  late final String clashConfigPath;
  late final String clashForMePath;
  late final String profilesPath;

  List<ReactionDisposer> _disposers = [];
  @observable
  bool systemProxy = false;
  @observable
  Config clashConfig = Config.defaultConfig();
  @observable
  ClashForMeConfig clashForMe = ClashForMeConfig.defaultConfig();

  @override
  dispose() async {
    await for (ReactionDisposer item in Stream.fromIterable(_disposers)) {
      item();
    }
  }

  Future<void> init() async {
    await getApplicationSupportDirectory().then((dir) => configDir = dir);

    profilesPath = "${configDir.path}${Constants.profilesPath}";
    clashForMePath = "${configDir.path}${Constants.clashForMe}";

    ClashForMeConfig? tempCfm = ClashForMeConfig.formYamlFile(clashForMePath);
    tempCfm = await _profilesInitCheck(tempCfm);
    if (tempCfm != null) {
      clashForMe = tempCfm;
    }

    clashConfigPath = "${configDir.path}${Constants.clashConfig}";
    clashConfig = Config.formYamlFile(clashConfigPath);

    await _initClash();

    _initDispose();
  }

  // 初始化clash
  Future<void> _initClash() async {
    String fullPath = "";
    if (Platform.isWindows) {
      fullPath = "libclash.dll";
    } else if (Platform.isMacOS) {
      fullPath = "libclash.dylib";
    } else {
      fullPath = "libclash.so";
    }
    final lib = DynamicLibrary.open(fullPath);
    clash = Clash(lib);
  }

  _initDispose() {
    _disposers = [
      reaction(
        (_) => clashConfig,
        (Config config) {
          _request.patchConfigs(config);
          config.saveFile(clashConfigPath);
          if (systemProxy) {
            openProxy();
          }
        },
        delay: 1000,
      ),
      reaction(
        (_) => clashForMe,
        (ClashForMeConfig config) => config.saveFile(clashForMePath),
        delay: 1000,
      ),
      reaction(
        (_) => clashForMe.selectedFile ?? clashConfigPath,
        (String file) {
          if (!File(file).isAbsolute) {
            file = "$profilesPath/$file";
          }
          _changeProfile(file);
        },
      ),
    ];
  }

  /// 校验本地订阅文件与配置里对应
  Future<ClashForMeConfig?> _profilesInitCheck(ClashForMeConfig? config) async {
    if (config == null) return null;

    var profilesDir = Directory(profilesPath);
    var fileList = <String>[];
    if (await profilesDir.exists()) {
      fileList = await profilesDir.list().where((e) => e is File).map((file) {
        var lastIndex = file.path.replaceAll("/", "\\").lastIndexOf("\\");
        return file.path.substring(lastIndex + 1);
      }).toList();
    }

    List<ProfileBase> profiles =
        config.profiles.where((e) => fileList.contains(e.file)).toList();

    var selectElements = profiles.where((e) => e.file == config.selectedFile);
    if (selectElements.isNotEmpty) {
      return ClashForMeConfig(
        selectedFile: selectElements.first.file,
        profiles: profiles,
      );
    }
    return ClashForMeConfig(profiles: profiles);
  }

  /// 当前应用中的配置文件
  @computed
  ProfileBase? get active {
    if (selectedFile == null) {
      return null;
    }
    return clashForMe.profiles.firstWhere((e) => e.file == selectedFile);
  }

  @computed
  String? get selectedFile => clashForMe.selectedFile;

  @computed
  List<ProfileBase> get profiles => clashForMe.profiles;

  /// 由于切换 profile 后，部分如 mode 会随 profile 更改，这里相当于同步配置
  _changeProfile(String file) async {
    await _request.changeConfig(file);
    await _request.patchConfigs(clashConfig);
  }

  @action
  setState({
    String? selectedFile,
    List<ProfileBase>? profiles,
    int? port,
    int? socksPort,
    int? redirPort,
    int? tproxyPort,
    int? mixedPort,
    bool? allowLan,
    Mode? mode,
    LogLevel? logLevel,
    bool? ipv6,
  }) {
    clashForMe = clashForMe.copyWith(
      selectedFile: selectedFile,
      profiles: profiles,
    );
    clashConfig = clashConfig.copyWith(
      port: port,
      socksPort: socksPort,
      redirPort: redirPort,
      tproxyPort: tproxyPort,
      mixedPort: mixedPort,
      allowLan: allowLan,
      mode: mode,
      logLevel: logLevel,
      ipv6: ipv6,
    );
  }

  /// 启动clash
  bool start() {
    clash.setHomeDir(configDir.path.toNativeUtf8().cast());
    clash.setConfig(File(clashConfigPath).absolute.path.toNativeUtf8().cast());
    clash.withExternalController(
      "${Constants.localhost}:9090".toNativeUtf8().cast(),
    );
    if (clash.startService() == 1) {
      if (active != null) {
        _changeProfile("$profilesPath/${active?.file}");
      }
      return true;
    }
    return false;
  }

  /// 打开代理
  @action
  Future<void> openProxy() async {
    await proxyManager.setAsSystemProxy(
      ProxyTypes.http,
      Constants.localhost,
      clashConfig.port ?? clashConfig.mixedPort ?? 7890,
    );
    await proxyManager.setAsSystemProxy(
      ProxyTypes.https,
      Constants.localhost,
      clashConfig.port ?? clashConfig.mixedPort ?? 7890,
    );
    if (!Platform.isWindows) {
      await proxyManager.setAsSystemProxy(
        ProxyTypes.socks,
        Constants.localhost,
        clashConfig.socksPort ?? clashConfig.mixedPort ?? 7890,
      );
    }
    systemProxy = true;
  }

  /// 关闭代理
  @action
  Future<void> closeProxy() async {
    proxyManager.cleanSystemProxy();
    systemProxy = false;
  }
}
