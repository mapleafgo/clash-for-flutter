import '../enum/type_enum.dart';
import 'package:dart_json_mapper/dart_json_mapper.dart';

import 'group_bean.dart';
import 'proxy_bean.dart';

@JsonSerializable()
class Proxies {
  @JsonProperty(converter: ProxiesConverter())
  Map<String, dynamic> proxies;

  Proxies({this.proxies});
}

class ProxiesConverter implements ICustomConverter<Map<String, dynamic>> {
  const ProxiesConverter() : super();

  @override
  Map<String, dynamic> fromJSON(jsonValue, [JsonProperty jsonProperty]) {
    return jsonValue.map((key, e) {
      return MapEntry(
        key,
        GroupTypeMap.values.contains(e["type"])
            ? JsonMapper.deserialize<Group>(e)
            : JsonMapper.deserialize<Proxy>(e),
      );
    });
  }

  @override
  toJSON(Map<String, dynamic> object, [JsonProperty jsonProperty]) {
    return object.map(
      (key, value) => MapEntry(key, JsonMapper.serialize(value)),
    );
  }
}
