import 'dart:io';

import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_bean.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/utils/constant.dart';

import '../../source/request.dart';

class ProfileController {
  final _request = Modular.get<Request>();
  final _config = Modular.get<GlobalConfig>();

  String? get selectedFile => _config.clashForMe.selectedFile;

  List<Profile> get profiles => _config.clashForMe.profiles;

  _setCFM({String? select, List<Profile>? list}) {
    _config.setState(
      clashForMe: ClashForMeConfig(
        selectedFile: select ?? selectedFile,
        profiles: list ?? profiles,
      ),
    );
  }

  Future<dynamic> getNewProfile(String url) {
    var time = DateTime.now();
    var file = "${time.millisecondsSinceEpoch}.yaml";
    return _request
        .downFile(
      urlPath: url,
      savePath: "${_config.configDir.path}${Constant.profilesPath}/$file",
    )
        .then(
      (_) {
        var tempList = profiles.toList();
        tempList.add(
          Profile.defaultBean(url: url, file: file, name: file, time: time),
        );
        if (tempList.length == 1)
          _setCFM(select: file, list: tempList);
        else
          _setCFM(list: tempList);
      },
    );
  }

  /// 选择某源
  select(String file) => _setCFM(select: file);

  /// 编辑源
  edit(Profile profile) {
    var tempList = profiles.toList();
    var i = tempList.indexWhere((element) => element.file == profile.file);
    tempList[i] = profile;
    _setCFM(list: tempList);
  }

  /// 移除源
  void removeProfile(String file) {
    var isActive = selectedFile == file;
    var tempList = profiles.toList();
    tempList.removeWhere((e) => e.file == file);
    if (isActive) {
      if (tempList.isNotEmpty) {
        _setCFM(select: tempList.first.file, list: tempList);
        _config.start();
      } else {
        _config.closeProxy();
        _setCFM(select: "", list: tempList);
      }
    } else {
      _setCFM(list: tempList);
    }
    File("${_config.configDir.path}${Constant.profilesPath}/$file").delete();
  }

  /// 更新源
  Future<void> updateProfile(String file) async {
    var tempList = profiles.toList();
    var index = tempList.indexWhere((e) => e.file == file);

    var profile = Profile.clone(tempList[index]);
    profile.time = DateTime.now();
    profile.file = "${profile.time.millisecondsSinceEpoch}.yaml";

    await _request.downFile(
      urlPath: profile.url,
      savePath:
          "${_config.configDir.path}${Constant.profilesPath}/${profile.file}",
    );

    tempList.replaceRange(index, index + 1, [profile]);

    if (selectedFile == file) {
      _setCFM(select: profile.file, list: tempList);
      await _config.start();
    } else {
      _setCFM(list: tempList);
    }
    File("${_config.configDir.path}${Constant.profilesPath}/$file").delete();
  }
}
