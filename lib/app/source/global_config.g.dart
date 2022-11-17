// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'global_config.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$GlobalConfig on ConfigFileBase, Store {
  Computed<ProfileBase?>? _$activeComputed;

  @override
  ProfileBase? get active =>
      (_$activeComputed ??= Computed<ProfileBase?>(() => super.active,
              name: 'ConfigFileBase.active'))
          .value;
  Computed<String?>? _$selectedFileComputed;

  @override
  String? get selectedFile =>
      (_$selectedFileComputed ??= Computed<String?>(() => super.selectedFile,
              name: 'ConfigFileBase.selectedFile'))
          .value;
  Computed<List<ProfileBase>>? _$profilesComputed;

  @override
  List<ProfileBase> get profiles =>
      (_$profilesComputed ??= Computed<List<ProfileBase>>(() => super.profiles,
              name: 'ConfigFileBase.profiles'))
          .value;

  late final _$systemProxyAtom =
      Atom(name: 'ConfigFileBase.systemProxy', context: context);

  @override
  bool get systemProxy {
    _$systemProxyAtom.reportRead();
    return super.systemProxy;
  }

  @override
  set systemProxy(bool value) {
    _$systemProxyAtom.reportWrite(value, super.systemProxy, () {
      super.systemProxy = value;
    });
  }

  late final _$clashConfigAtom =
      Atom(name: 'ConfigFileBase.clashConfig', context: context);

  @override
  Config get clashConfig {
    _$clashConfigAtom.reportRead();
    return super.clashConfig;
  }

  @override
  set clashConfig(Config value) {
    _$clashConfigAtom.reportWrite(value, super.clashConfig, () {
      super.clashConfig = value;
    });
  }

  late final _$clashForMeAtom =
      Atom(name: 'ConfigFileBase.clashForMe', context: context);

  @override
  ClashForMeConfig get clashForMe {
    _$clashForMeAtom.reportRead();
    return super.clashForMe;
  }

  @override
  set clashForMe(ClashForMeConfig value) {
    _$clashForMeAtom.reportWrite(value, super.clashForMe, () {
      super.clashForMe = value;
    });
  }

  late final _$openProxyAsyncAction =
      AsyncAction('ConfigFileBase.openProxy', context: context);

  @override
  Future<void> openProxy() {
    return _$openProxyAsyncAction.run(() => super.openProxy());
  }

  late final _$closeProxyAsyncAction =
      AsyncAction('ConfigFileBase.closeProxy', context: context);

  @override
  Future<void> closeProxy() {
    return _$closeProxyAsyncAction.run(() => super.closeProxy());
  }

  late final _$ConfigFileBaseActionController =
      ActionController(name: 'ConfigFileBase', context: context);

  @override
  dynamic setState(
      {String? selectedFile,
      List<ProfileBase>? profiles,
      int? port,
      int? socksPort,
      int? redirPort,
      int? tproxyPort,
      int? mixedPort,
      bool? allowLan,
      Mode? mode,
      LogLevel? logLevel,
      bool? ipv6}) {
    final _$actionInfo = _$ConfigFileBaseActionController.startAction(
        name: 'ConfigFileBase.setState');
    try {
      return super.setState(
          selectedFile: selectedFile,
          profiles: profiles,
          port: port,
          socksPort: socksPort,
          redirPort: redirPort,
          tproxyPort: tproxyPort,
          mixedPort: mixedPort,
          allowLan: allowLan,
          mode: mode,
          logLevel: logLevel,
          ipv6: ipv6);
    } finally {
      _$ConfigFileBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
systemProxy: ${systemProxy},
clashConfig: ${clashConfig},
clashForMe: ${clashForMe},
active: ${active},
selectedFile: ${selectedFile},
profiles: ${profiles}
    ''';
  }
}
