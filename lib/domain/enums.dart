enum GroupType { selector, urlTest, fallback, loadBalance }

enum Mode { rule, global, direct }

enum LogLevel { debug, info, warning, error, silent }

enum ProfileType { url, file }

enum SortType { defaults, name, delay }

const _usedProxyNames = {'DIRECT', 'REJECT', 'GLOBAL'};
bool isUsedProxy(String name) => _usedProxyNames.contains(name);

const _groupTypeNames = {'Selector', 'URLTest', 'Fallback', 'LoadBalance'};
bool isGroupType(String type) => _groupTypeNames.contains(type);