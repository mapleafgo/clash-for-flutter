import 'dart:io';

import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_bean.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/utils/constant.dart';

import '../../source/request.dart';

class ProfileController extends Disposable {
  final _request = Modular.get<Request>();
  final _config = Modular.get<GlobalConfig>();

  String get selectedFile => _config.clashForMe.selectedFile;

  List<Profile> get profiles => _config.clashForMe.profiles;

  @override
  void dispose() => _config.dispose();

  _setCFM({String select, List<Profile> list}) {
    _config.setState(
      clashForMe: ClashForMeConfig(
        selectedFile: select ?? selectedFile,
        profiles: list ?? profiles,
      ),
    );
  }

  Future<dynamic> getNewProfile(String url) {
    var file = "${DateTime.now().millisecondsSinceEpoch}.yaml";
    return _request
        .downFile(
      urlPath: url,
      savePath: "${_config.configDir.path}${Constant.profilesPath}/$file",
    )
        .then(
      (_) {
        var tempList = profiles.toList();
        tempList.add(Profile.defalut(url: url, file: file, name: file));
        if (tempList.length == 1)
          _setCFM(select: file, list: tempList);
        else
          _setCFM(list: tempList);
      },
    );
  }

  /// 选择某源
  select(String file) => _setCFM(select: file);

  /// 重命名源
  rename(String file, String name) {
    var tempList = profiles.toList();
    var i = tempList.indexWhere((element) => element.file == file);
    tempList[i].name = name;
    _setCFM(list: tempList);
  }

  /// 移除源
  Future<void> removeProfile(String file) async {
    var isActive = selectedFile == file;
    var tempList = profiles.toList();
    tempList.removeWhere((e) => e.file == file);
    if (isActive) {
      _setCFM(select: tempList.first?.file, list: tempList);
      tempList.first ?? _config.start();
    } else {
      _setCFM(list: tempList);
    }
    await File("${_config.configDir.path}${Constant.profilesPath}/$file")
        .delete();
  }

  /// 更新源
  Future<void> updateProfile(String file) async {
    var tempList = profiles.toList();
    var i = tempList.indexWhere((element) => element.file == file);

    var newFile = "${DateTime.now().millisecondsSinceEpoch}.yaml";
    await _request.downFile(
      urlPath: tempList[i].url,
      savePath: "${_config.configDir.path}${Constant.profilesPath}/$newFile",
    );

    tempList[i].file = newFile;

    if (selectedFile == file) {
      _setCFM(select: newFile, list: tempList);
      _config.start();
    } else {
      _setCFM(list: tempList);
    }
    await File("${_config.configDir.path}${Constant.profilesPath}/$file")
        .delete();
  }
}
