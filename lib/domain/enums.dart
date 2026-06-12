enum Mode { rule, global, direct }

enum LogLevel { debug, info, warning, error }

enum ProfileType { url, file }

enum SortType { defaults, name, delay }

// sing-box outbound group types (constant/proxy.go)
const kGroupTypeSelector = 'selector';
const kGroupTypeUrlTest = 'urltest';
