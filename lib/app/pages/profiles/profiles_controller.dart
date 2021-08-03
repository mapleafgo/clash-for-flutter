import 'dart:io';

import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_file_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/bean/clash_for_me_config_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/source/global_config.dart';
import 'package:clash_for_flutter/app/utils/constant.dart';

import '../../source/request.dart';

class ProfileController {
  final _request = Modular.get<Request>();
  final _config = Modular.get<GlobalConfig>();

  String? get selectedFile => _config.clashForMe.selectedFile;

  List<ProfileBase> get profiles => _config.clashForMe.profiles;

  _setCFM({String? select, List<ProfileBase>? list}) {
    _config.setState(
      clashForMe: ClashForMeConfig(
        selectedFile: select ?? selectedFile,
        profiles: list ?? profiles,
      ),
    );
  }

  Future<dynamic> getNewProfile(ProfileBase profile) {
    var time = DateTime.now();
    var file = "${time.millisecondsSinceEpoch}.yaml";
    var savePath = "${_config.configDir.path}${Constant.profilesPath}/$file";

    Future<dynamic> handle;
    switch (profile.type) {
      case ProfileType.URL:
        handle = _request.downFile(
          urlPath: (profile as ProfileURL).url,
          savePath: savePath,
        );
        break;
      default:
        handle = File((profile as ProfileFile).path!).copy(savePath);
    }

    return handle.then((_) {
      var tempList = profiles.toList();
      profile.file = file;
      profile.time = time;
      tempList.add(profile);
      if (tempList.length == 1)
        _setCFM(select: file, list: tempList);
      else
        _setCFM(list: tempList);
    });
  }

  /// 选择某源
  Future<void> select(String file) async {
    _setCFM(select: file);
    await _config.start();
  }

  /// 编辑源
  edit(ProfileBase profile) {
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

  /// 更新源(仅限URL)
  Future<void> updateProfile(String file) async {
    var tempList = profiles.toList();
    var index = tempList.indexWhere((e) => e.file == file);

    var profile = JsonMapper.clone<ProfileURL>(tempList[index] as ProfileURL);
    if (profile == null) return;

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
