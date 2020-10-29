import 'package:dart_json_mapper/dart_json_mapper.dart';

import 'provider_bean.dart';

@JsonSerializable()
class ProxyProviders {
  Map<String, Provider> providers;

  ProxyProviders({this.providers});
}
