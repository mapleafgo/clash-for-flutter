// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proxys_model.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ProxysModel on ProxysModelBase, Store {
  late final _$groupsAtom =
      Atom(name: 'ProxysModelBase.groups', context: context);

  @override
  List<Group> get groups {
    _$groupsAtom.reportRead();
    return super.groups;
  }

  @override
  set groups(List<Group> value) {
    _$groupsAtom.reportWrite(value, super.groups, () {
      super.groups = value;
    });
  }

  late final _$globalAtom =
      Atom(name: 'ProxysModelBase.global', context: context);

  @override
  Group? get global {
    _$globalAtom.reportRead();
    return super.global;
  }

  @override
  set global(Group? value) {
    _$globalAtom.reportWrite(value, super.global, () {
      super.global = value;
    });
  }

  late final _$sortTypeAtom =
      Atom(name: 'ProxysModelBase.sortType', context: context);

  @override
  SortType get sortType {
    _$sortTypeAtom.reportRead();
    return super.sortType;
  }

  @override
  set sortType(SortType value) {
    _$sortTypeAtom.reportWrite(value, super.sortType, () {
      super.sortType = value;
    });
  }

  late final _$proxiesMapAtom =
      Atom(name: 'ProxysModelBase.proxiesMap', context: context);

  @override
  Map<String, dynamic> get proxiesMap {
    _$proxiesMapAtom.reportRead();
    return super.proxiesMap;
  }

  @override
  set proxiesMap(Map<String, dynamic> value) {
    _$proxiesMapAtom.reportWrite(value, super.proxiesMap, () {
      super.proxiesMap = value;
    });
  }

  late final _$ProxysModelBaseActionController =
      ActionController(name: 'ProxysModelBase', context: context);

  @override
  dynamic setState(
      {Group? global,
      SortType? sortType,
      List<Group>? groups,
      Map<String, dynamic>? proxiesMap}) {
    final _$actionInfo = _$ProxysModelBaseActionController.startAction(
        name: 'ProxysModelBase.setState');
    try {
      return super.setState(
          global: global,
          sortType: sortType,
          groups: groups,
          proxiesMap: proxiesMap);
    } finally {
      _$ProxysModelBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
groups: ${groups},
global: ${global},
sortType: ${sortType},
proxiesMap: ${proxiesMap}
    ''';
  }
}
