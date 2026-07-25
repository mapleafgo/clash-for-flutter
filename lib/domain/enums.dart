enum Mode { rule, global, direct }

enum LogLevel { debug, info, warning, error }

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
