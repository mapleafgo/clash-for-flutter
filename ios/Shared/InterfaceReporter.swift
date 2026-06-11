import Foundation
import Network
import Singcast

enum InterfaceReporter {

    private static let TYPE_LOOPBACK = 0
    private static let TYPE_OTHER = 1
    private static let TYPE_WIFI = 2
    private static let TYPE_CELLULAR = 3
    private static let TYPE_ETHERNET = 4

    /// 按需回调：内核通过 InterfaceProvider.GetInterfaces() 调用。
    static func getInterfacesJSON() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "[]" }
        defer { freeifaddrs(ifaddr) }

        let typeMap = buildTypeMap()

        var seen = Set<String>()
        var arr = [[String: Any]]()
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if !seen.contains(name) {
                seen.insert(name)
                let addrs = collectAddresses(for: name, from: first)
                let type = typeMap[name] ?? fallbackType(name: name)
                arr.append([
                    "name": name,
                    "index": Int(if_nametoindex(name)),
                    "mtu": getMTU(for: name),
                    "addresses": addrs,
                    "flags": Int(current.pointee.ifa_flags) & 0xFFFF,
                    "type": type,
                ])
            }
            ptr = current.pointee.ifa_next
        }

        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// 按需回调：内核通过 WiFiStateProvider.GetWiFiState() 调用。
    static func getWiFiStateJSON() -> String {
        return "{}"
    }

    // MARK: - Type detection

    /// Build interface name → type map from NWPathMonitor (authoritative source).
    private static func buildTypeMap() -> [String: Int] {
        var map = [String: Int]()
        let monitor = NWPathMonitor()
        let group = DispatchGroup()
        group.enter()
        monitor.pathUpdateHandler = { path in
            for iface in path.availableInterfaces {
                map[iface.name] = swiftTypeToConst(iface.type)
            }
            group.leave()
            monitor.pathUpdateHandler = nil
        }
        monitor.start(queue: DispatchQueue.global())
        group.wait()
        monitor.cancel()
        return map
    }

    private static func swiftTypeToConst(_ type: NWInterface.InterfaceType) -> Int {
        switch type {
        case .wifi: return TYPE_WIFI
        case .cellular: return TYPE_CELLULAR
        case .wiredEthernet: return TYPE_ETHERNET
        case .loopback: return TYPE_LOOPBACK
        default: return TYPE_OTHER
        }
    }

    /// Fallback for interfaces not in the current network path (e.g. loopback, awdl).
    private static func fallbackType(name: String) -> Int {
        if name == "lo0" { return TYPE_LOOPBACK }
        if name.hasPrefix("en") { return TYPE_WIFI }
        if name.hasPrefix("pdp_ip") { return TYPE_CELLULAR }
        return TYPE_OTHER
    }

    // MARK: - Address collection

    private static func collectAddresses(for name: String, from first: UnsafeMutablePointer<ifaddrs>) -> [String] {
        var addresses = [String]()
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let curName = String(cString: current.pointee.ifa_name)
            if curName == name, let addr = current.pointee.ifa_addr {
                let family = addr.pointee.sa_family
                if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                        ptr = current.pointee.ifa_next
                        continue
                    }
                    let hostStr = String(cString: host).components(separatedBy: "%").first ?? ""
                    guard !hostStr.isEmpty else {
                        ptr = current.pointee.ifa_next
                        continue
                    }
                    let prefix = prefixLength(from: current.pointee.ifa_netmask, family: family)
                    addresses.append("\(hostStr)/\(prefix)")
                }
            }
            ptr = current.pointee.ifa_next
        }
        return addresses
    }

    private static func prefixLength(from mask: UnsafeMutablePointer<sockaddr>?, family: sa_family_t) -> Int {
        guard let mask = mask else { return 0 }
        if family == UInt8(AF_INET) {
            let sin = mask.assumingMemoryBound(to: sockaddr_in.self).pointee
            return sin.sin_addr.s_addr.bigEndian.nonzeroBitCount
        }
        if family == UInt8(AF_INET6) {
            let sin6 = mask.assumingMemoryBound(to: sockaddr_in6.self).pointee
            return withUnsafeBytes(of: sin6.sin6_addr) { ptr in
                ptr.reduce(0) { $0 + $1.nonzeroBitCount }
            }
        }
        return 0
    }

    // MARK: - MTU

    private static func getMTU(for name: String) -> Int {
        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return 1500 }
        defer { Darwin.close(sock) }

        // ifreq on 64-bit Darwin: 16 bytes ifr_name + 16 bytes ifr_ifru union
        var storage = Data(count: 32)
        let ok = storage.withUnsafeMutableBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            name.withCString { strncpy(base.assumingMemoryBound(to: CChar.self), $0, 16) }
            return Darwin.ioctl(sock, UInt(SIOCGIFMTU), base) == 0
        }
        guard ok else { return 1500 }
        return storage.withUnsafeBytes { Int($0.baseAddress!.load(fromByteOffset: 16, as: Int32.self)) }
    }
}
