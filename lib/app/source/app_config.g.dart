// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$AppConfig on AppConfigBase, Store {
  Computed<ProfileBase?>? _$activeComputed;

  @override
  ProfileBase? get active =>
      (_$activeComputed ??= Computed<ProfileBase?>(() => super.active,
              name: 'AppConfigBase.active'))
          .value;
  Computed<String?>? _$selectedFileComputed;

  @override
  String? get selectedFile =>
      (_$selectedFileComputed ??= Computed<String?>(() => super.selectedFile,
              name: 'AppConfigBase.selectedFile'))
          .value;
  Computed<bool>? _$tunIfComputed;

  @override
  bool get tunIf => (_$tunIfComputed ??=
          Computed<bool>(() => super.tunIf, name: 'AppConfigBase.tunIf'))
      .value;
  Computed<List<ProfileBase>>? _$profilesComputed;

  @override
  List<ProfileBase> get profiles =>
      (_$profilesComputed ??= Computed<List<ProfileBase>>(() => super.profiles,
              name: 'AppConfigBase.profiles'))
          .value;

  late final _$systemProxyAtom =
      Atom(name: 'AppConfigBase.systemProxy', context: context);

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

  late final _$clashForMeAtom =
      Atom(name: 'AppConfigBase.clashForMe', context: context);

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

  late final _$_initConfigAsyncAction =
      AsyncAction('AppConfigBase._initConfig', context: context);

  @override
  Future _initConfig() {
    return _$_initConfigAsyncAction.run(() => super._initConfig());
  }

  late final _$openProxyAsyncAction =
      AsyncAction('AppConfigBase.openProxy', context: context);

  @override
  Future<void> openProxy() {
    return _$openProxyAsyncAction.run(() => super.openProxy());
  }

  late final _$closeProxyAsyncAction =
      AsyncAction('AppConfigBase.closeProxy', context: context);

  @override
  Future<void> closeProxy() {
    return _$closeProxyAsyncAction.run(() => super.closeProxy());
  }

  late final _$AppConfigBaseActionController =
      ActionController(name: 'AppConfigBase', context: context);

  @override
  dynamic setState(
      {String? selectedFile,
      List<ProfileBase>? profiles,
      String? mmdbUrl,
      String? delayTestUrl,
      bool? tunIf}) {
    final _$actionInfo = _$AppConfigBaseActionController.startAction(
        name: 'AppConfigBase.setState');
    try {
      return super.setState(
          selectedFile: selectedFile,
          profiles: profiles,
          mmdbUrl: mmdbUrl,
          delayTestUrl: delayTestUrl,
          tunIf: tunIf);
    } finally {
      _$AppConfigBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
systemProxy: ${systemProxy},
clashForMe: ${clashForMe},
active: ${active},
selectedFile: ${selectedFile},
tunIf: ${tunIf},
profiles: ${profiles}
    ''';
  }
}
