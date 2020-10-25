import 'package:json_annotation/json_annotation.dart';

import 'provider_bean.dart';

part 'proxy_providers_bean.g.dart';

@JsonSerializable()
class ProxyProviders {
  Map<String, Provider> providers;

  ProxyProviders({this.providers});

  factory ProxyProviders.fromJson(Map<String, dynamic> json) =>
      _$ProxyProvidersFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyProvidersToJson(this);
}
