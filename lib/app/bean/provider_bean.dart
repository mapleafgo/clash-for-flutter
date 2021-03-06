import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'group_bean.dart';
import 'proxy_bean.dart';

@JsonSerializable()
class Provider {
  String name;
  @JsonProperty(converter: ProviderProxiesConverter())
  List<dynamic> proxies;
  String type;
  VehicleType vehicleType;
  String? updatedAt;

  Provider({
    required this.name,
    required this.proxies,
    required this.type,
    required this.vehicleType,
    this.updatedAt,
  });
}

class ProviderProxiesConverter implements ICustomConverter<List<dynamic>> {
  const ProviderProxiesConverter() : super();

  @override
  List<dynamic> fromJSON(jsonValue, [DeserializationContext? context]) {
    return jsonValue
        .map(
          (e) => GroupTypeValue.valueList.contains(e["type"])
              ? JsonMapper.fromMap<Group>(e)
              : JsonMapper.fromMap<Proxy>(e),
        )
        .toList();
  }

  @override
  toJSON(List<dynamic> object, [SerializationContext? context]) {
    return object.map((e) => e.toJson()).toList();
  }
}
