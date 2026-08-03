enum Mode { rule, global, direct }

enum LogLevel { debug, info, warning, error }

/// sing-box clash_api 的 mode 字段需首字母大写（如 Rule / Global / Direct）。
extension ModeSingboxExt on Mode {
  String get singboxName => name[0].toUpperCase() + name.substring(1);
}

/// sing-box log.level 对应值：warning 映射为 'warn'，其余与枚举名一致。
extension LogLevelSingboxExt on LogLevel {
  String get singboxName => this == LogLevel.warning ? 'warn' : name;
}

/// TUN 协议栈实现。
///
/// - [gvisor]：全用户态协议栈，兼容性最好，不依赖内核 ip_forward；
///   适合 rp_filter / strict_route 可能干扰 system 栈的环境。
/// - [mixed]：TCP 走 system NAT（需内核转发），UDP 走 gvisor，吞吐更高。
/// - [system]：TCP/UDP 均走 system，依赖内核网络栈配置。
enum TunStack { gvisor, mixed, system }

enum ProfileType { url, file }

enum SortType { defaults, name, delay }

// sing-box outbound group types (constant/proxy.go)
const kGroupTypeUrlTest = 'urltest';
