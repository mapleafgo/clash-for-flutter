/// 代理类型
enum ProxieType { Direct, Reject, Shadowsocks, Vmess, Socks, Http, Snell }
const ProxieTypeMap = {
  ProxieType.Direct: "Direct",
  ProxieType.Reject: "Reject",
  ProxieType.Shadowsocks: "Shadowsocks",
  ProxieType.Vmess: "Vmess",
  ProxieType.Socks: "Socks",
  ProxieType.Http: "Http",
  ProxieType.Snell: "Snell",
};

/// 分组类型
enum GroupType { Selector, URLTest, Fallback, LoadBalance }
const GroupTypeMap = {
  GroupType.Selector: "Selector",
  GroupType.URLTest: "URLTest",
  GroupType.Fallback: "Fallback",
  GroupType.LoadBalance: "LoadBalance",
};

enum VehicleType { HTTP, File, Compatible }
const VehicleTypeMap = {
  VehicleType.HTTP: "HTTP",
  VehicleType.File: "File",
  VehicleType.Compatible: "Compatible",
};

/// 使用的选择代理
enum UsedProxy { DIRECT, REJECT, GLOBAL }
const UsedProxyMap = {
  UsedProxy.DIRECT: "DIRECT",
  UsedProxy.REJECT: "REJECT",
  UsedProxy.GLOBAL: "GLOBAL",
};

enum Mode { Rule, Global, Direct }
const ModeMap = {
  Mode.Rule: "Rule",
  Mode.Global: "Global",
  Mode.Direct: "Direct",
};
