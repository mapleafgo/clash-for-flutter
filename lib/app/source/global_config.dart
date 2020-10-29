import 'dart:convert';
import 'dart:io';

import 'package:clash_for_flutter/app/source/request.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_bean.dart';
import 'package:clash_for_flutter/app/utils/constant.dart';
import 'package:go_flutter_clash/go_flutter_clash.dart';
import 'package:go_flutter_clash/model/flutter_clash_config_model.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

part 'global_config.g.dart';

class GlobalConfig = _ConfigFileBase with _$GlobalConfig;

abstract class _ConfigFileBase extends Disposable with Store {
  final _request = Modular.get<Request>();
  Directory configDir;

  List<ReactionDisposer> _disposers = [];
  @observable
  FlutterClashConfig clashConfig;
  @observable
  ClashForMeConfig clashForMe;

  @override
  dispose() async {
    await for (ReactionDisposer item in Stream.fromIterable(_disposers)) {
      item();
    }
  }

  Future<void> init() async {
    configDir = await getApplicationSupportDirectory();
    var clashConfigFile = File(configDir.path + Constant.clashConfig);
    var clashForMeFile = File(configDir.path + Constant.clashForMe);
    this.clashConfig = await clashConfigFile.exists()
        ? FlutterClashConfig.fromJson(
            jsonDecode(await clashConfigFile.readAsString()),
          )
        : FlutterClashConfig.defaultConfig();
    this.clashForMe = await clashForMeFile.exists()
        ? await _profilesInitCheck(
            JsonMapper.deserialize<ClashForMeConfig>(
              await clashForMeFile.readAsString(),
            ),
          )
        : ClashForMeConfig.defaultConfig();

    await _initClash();

    _initDispose();
  }

  // 初始化clash
  Future<void> _initClash() async {
    var dbFile = File(configDir.path + Constant.db);
    if (!dbFile.existsSync()) {
      await _request.downFile(
        urlPath: Constant.dbUrl,
        savePath: dbFile.path,
      );
    }
    return GoFlutterClash.init(configDir.path);
  }

  _initDispose() {
    _disposers = [
      reaction(
        (_) => clashConfig,
        (FlutterClashConfig config) {
          File(configDir.path + Constant.clashConfig)
              .create(recursive: true)
              .then(
                (file) => file.writeAsString(jsonEncode(config)),
              );
        },
        delay: 2000,
      ),
      reaction(
        (_) => clashForMe,
        (ClashForMeConfig config) {
          File(configDir.path + Constant.clashForMe)
              .create(recursive: true)
              .then(
                (file) => file.writeAsString(jsonEncode(config)),
              );
        },
        delay: 2000,
      ),
    ];
  }

  /// 校验本地配置文件
  Future<ClashForMeConfig> _profilesInitCheck(ClashForMeConfig config) async {
    var profilesDir = Directory(configDir.path + Constant.profilesPath);
    var fileList = <String>[];
    if (await profilesDir.exists()) {
      fileList = await profilesDir.list().where((e) => e is File).map((file) {
        var lastIndex = file.path.replaceAll("\/", "\\").lastIndexOf("\\");
        return file.path.substring(lastIndex + 1);
      }).toList();
    }

    List<Profile> profiles =
        config.profiles.where((e) => fileList.contains(e.file)).toList();

    var selectFile = profiles
        .firstWhere(
          (e) => e.file == config.selectedFile,
          orElse: () => null,
        )
        ?.file;

    return ClashForMeConfig(selectedFile: selectFile, profiles: profiles);
  }

  /// 当前应用中的配置文件
  @computed
  Profile get active {
    var selectedFile = clashForMe.selectedFile;
    var profiles = clashForMe.profiles;
    if (selectedFile.isNotEmpty) {
      return profiles.firstWhere((item) => item.file == selectedFile);
    } else {
      return null;
    }
  }

  @action
  setState({ClashForMeConfig clashForMe, FlutterClashConfig clashConfig}) {
    if (clashForMe != null) this.clashForMe = clashForMe;
    if (clashConfig != null) this.clashConfig = clashConfig;
  }

  /// 启动clash
  Future<void> start() async {
    var file = File(
      "${configDir.path}${Constant.profilesPath}/${clashForMe.selectedFile}",
    );
    var profile = jsonEncode(loadYaml(await file.readAsString()));
    return GoFlutterClash.start(profile, clashConfig).then((_) {
      active.selected?.forEach((key, value) {
        _request.changeProxy(name: key, select: value);
      });
    });
  }

  /// 切换代理
  proxySelect({String name, String select}) {
    var i = clashForMe.profiles.indexOf(active);
    var profile = JsonMapper.deserialize<Profile>(JsonMapper.serialize(active));

    profile.selected != null
        ? profile.selected[name] = select
        : profile.selected = Map.fromEntries([MapEntry(name, select)]);

    var config = JsonMapper.deserialize<ClashForMeConfig>(
        JsonMapper.serialize(clashForMe));
    config.profiles[i] = profile;
    setState(clashForMe: config);
  }
}
