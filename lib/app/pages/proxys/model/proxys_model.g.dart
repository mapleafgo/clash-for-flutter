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

  late final _$allAtom = Atom(name: 'ProxysModelBase.all', context: context);

  @override
  List<dynamic> get all {
    _$allAtom.reportRead();
    return super.all;
  }

  @override
  set all(List<dynamic> value) {
    _$allAtom.reportWrite(value, super.all, () {
      super.all = value;
    });
  }

  late final _$proxiesAtom =
      Atom(name: 'ProxysModelBase.proxies', context: context);

  @override
  List<Proxy> get proxies {
    _$proxiesAtom.reportRead();
    return super.proxies;
  }

  @override
  set proxies(List<Proxy> value) {
    _$proxiesAtom.reportWrite(value, super.proxies, () {
      super.proxies = value;
    });
  }

  late final _$providersAtom =
      Atom(name: 'ProxysModelBase.providers', context: context);

  @override
  Map<String, Provider> get providers {
    _$providersAtom.reportRead();
    return super.providers;
  }

  @override
  set providers(Map<String, Provider> value) {
    _$providersAtom.reportWrite(value, super.providers, () {
      super.providers = value;
    });
  }

  late final _$proxiesMapAtom =
      Atom(name: 'ProxysModelBase.proxiesMap', context: context);

  @override
  Map<String, List<ProxieShow>> get proxiesMap {
    _$proxiesMapAtom.reportRead();
    return super.proxiesMap;
  }

  @override
  set proxiesMap(Map<String, List<ProxieShow>> value) {
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
      List<dynamic>? all,
      List<Group>? groups,
      List<Proxy>? proxies,
      Map<String, Provider>? providers,
      Map<String, List<ProxieShow>>? proxiesMap}) {
    final _$actionInfo = _$ProxysModelBaseActionController.startAction(
        name: 'ProxysModelBase.setState');
    try {
      return super.setState(
          global: global,
          sortType: sortType,
          all: all,
          groups: groups,
          proxies: proxies,
          providers: providers,
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
all: ${all},
proxies: ${proxies},
providers: ${providers},
proxiesMap: ${proxiesMap}
    ''';
  }
}
