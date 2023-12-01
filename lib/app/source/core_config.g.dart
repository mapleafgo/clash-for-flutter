// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'core_config.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$CoreConfig on CoreConfigBase, Store {
  late final _$clashConfigAtom =
      Atom(name: 'CoreConfigBase.clashConfig', context: context);

  @override
  Config get clash {
    _$clashConfigAtom.reportRead();
    return super.clash;
  }

  @override
  set clash(Config value) {
    _$clashConfigAtom.reportWrite(value, super.clash, () {
      super.clash = value;
    });
  }

  late final _$asyncConfigAsyncAction =
      AsyncAction('CoreConfigBase.asyncConfig', context: context);

  @override
  Future<void> asyncConfig() {
    return _$asyncConfigAsyncAction.run(() => super.asyncConfig());
  }

  late final _$CoreConfigBaseActionController =
      ActionController(name: 'CoreConfigBase', context: context);

  @override
  dynamic setState(
      {int? redirPort,
      int? tproxyPort,
      int? mixedPort,
      bool? allowLan,
      Mode? mode,
      LogLevel? logLevel,
      bool? ipv6}) {
    final _$actionInfo = _$CoreConfigBaseActionController.startAction(
        name: 'CoreConfigBase.setState');
    try {
      return super.setState(
          redirPort: redirPort,
          tproxyPort: tproxyPort,
          mixedPort: mixedPort,
          allowLan: allowLan,
          mode: mode,
          logLevel: logLevel,
          ipv6: ipv6);
    } finally {
      _$CoreConfigBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
clashConfig: ${clash}
    ''';
  }
}
