import 'package:dart_json_mapper/dart_json_mapper.dart';

import 'provider_bean.dart';

@JsonSerializable()
@Json(valueDecorators: ProxyProviders.valueDecorators)
class ProxyProviders {
  static Map<Type, ValueDecoratorFunction> valueDecorators() => {
        typeOf<Map<String, Provider>>(): (value) =>
            Map.castFrom<dynamic, dynamic, String, Provider>(value),
      };

  Map<String, Provider> providers;

  ProxyProviders({required this.providers});
}
