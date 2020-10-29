import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:clash_for_flutter/app/app_module.dart';
import 'package:dart_json_mapper_mobx/dart_json_mapper_mobx.dart';

import 'main.mapper.g.dart' show initializeJsonMapper;

void main() {
  initializeJsonMapper(adapters: [mobXAdapter]);
  JsonMapper().useAdapter(JsonMapperAdapter(valueDecorators: {
    typeOf<Map<String, String>>(): (value) {
      return Map.castFrom<dynamic, dynamic, String, String>(value);
    },
  }, converters: {
    Enum: enumConverterNumeric
  }));
  runApp(ModularApp(module: AppModule()));
}
