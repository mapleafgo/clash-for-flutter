import 'dart:io';

import 'package:asuka/asuka.dart';
import 'package:clash_for_flutter/app/bean/profile_base_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_file_bean.dart';
import 'package:clash_for_flutter/app/bean/profile_url_bean.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/source/app_config.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/constants.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ProfileShow {
  final String title;
  final ProfileType type;
  int? use;
  int? total;
  DateTime? expire;
  final DateTime lastUpdate;

  ProfileShow({
    required this.title,
    required this.type,
    this.use,
    this.total,
    this.expire,
    required this.lastUpdate,
  });
}

class ProfileController {
  final _request = Modular.get<Request>();
  final _config = Modular.get<AppConfig>();

  Future<void> addProfile(ProfileBase profile) {
    Future<ProfileBase> handle;
    switch (profile.type) {
      case ProfileType.URL:
        handle = _request.getSubscribe(
          profile: profile as ProfileURL,
          profilesDir: _config.profilesPath,
        );
        break;
      case ProfileType.FILE:
        var time = DateTime.now();
        var file = "${time.millisecondsSinceEpoch}.yaml";
        var savePath = "${_config.profilesPath}/$file";
        handle = File((profile as ProfileFile).path!).copy(savePath).then((_) {
          return profile
            ..time = time
            ..file = file;
        });
        break;
      default:
        return Future(() => null);
    }

    return handle.then((p) {
      var tempList = _config.profiles.toList();
      tempList.add(p);
      _config.setState(profiles: tempList);
    });
  }

  /// 选择某源
  select(String file) {
    _config.setState(selectedFile: file);
  }

  /// 编辑源
  edit(ProfileBase profile) {
    var tempList = _config.profiles.toList();
    var i = tempList.indexWhere((element) => element.file == profile.file);
    tempList[i] = profile;
    _config.setState(profiles: tempList);
  }

  /// 移除源
  void removeProfile(String file) {
    var isActive = _config.selectedFile == file;
    var tempList = _config.profiles.toList();
    tempList.removeWhere((e) => e.file == file);
    if (isActive && tempList.isNotEmpty) {
      _config.setState(selectedFile: tempList.first.file, profiles: tempList);
    } else {
      _config.setState(profiles: tempList);
    }
    File("${Constants.homeDir.path}${Constants.profilesPath}/$file").delete();
  }

  /// 更新源(仅限URL)
  Future<void> updateProfile(String file) async {
    var tempList = _config.profiles.toList();
    var index = tempList.indexWhere((e) => e.file == file);

    var profile = JsonMapper.clone<ProfileURL>(tempList[index] as ProfileURL);
    if (profile == null) return;

    try {
      profile = await _request.getSubscribe(
        profile: profile,
        profilesDir: _config.profilesPath,
      );
    } catch (e) {
      Asuka.showSnackBar(SnackBar(content: Text("更新异常: $e")));
      return;
    }

    tempList.replaceRange(index, index + 1, [profile]);

    if (_config.selectedFile == file) {
      _config.setState(selectedFile: profile.file, profiles: tempList);
    } else {
      _config.setState(profiles: tempList);
    }
    File("${Constants.homeDir.path}${Constants.profilesPath}/$file").delete();
  }
}
