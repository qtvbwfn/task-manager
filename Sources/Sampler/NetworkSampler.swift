import Darwin
import Foundation
import CoreWLAN

/// WiFi 详情（macOS 14+ 读取 SSID 需要定位权限，未授权时 ssid 为 nil）
struct WiFiInfo: Sendable {
    let ssid: String?
    let channel: String        // 如 "56 • 5 GHz • 80 MHz"
    let transmitMbps: Double   // 当前协商发送速率
    let rssi: Int              // 信号强度 dBm（越接近 0 越强）
    let noise: Int             // 噪声 dBm
    let security: String
}

/// 单接口信息：静态属性（MAC/IP/类型/连接速率）+ 计数器与速率
struct NetworkInterfaceSample: Sendable {
    let name: String
    let isUp: Bool
    let isWiFi: Bool
    let mac: String
    let ipv4: [String]
    let baudrateBps: UInt64    // 网口协商速率（bits/s），RJ45 即连接速率
    let wifi: WiFiInfo?
    let bytesIn: UInt64
    let bytesOut: UInt64
    let inPerSecond: Double
    let outPerSecond: Double
}

/// 网络速率：NET_RT_IFLIST2 枚举接口（方案 §0 的 6 元素 mib），再用 net.link.generic.ifdata
/// 读取 64 位计数器。实测 macOS 15 对普通进程只往 if_msghdr2 里写低 32 位，IFMIB 才返回完整
/// 64 位累计值；差分求速率时按接口聚合，排除回环。
final class NetworkSampler {
    private var previous: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var lastSampleTime: UInt64 = 0
    private var tick: UInt64 = 0
    /// WiFi 详情读取较重，每 5 个采样周期刷新一次
    private var wifiNames: Set<String> = []
    private var wifiCache: [String: WiFiInfo] = [:]

    struct Sample {
        let interfaces: Int
        let bytesInPerSecond: Double
        let bytesOutPerSecond: Double
        let totalBytesIn: UInt64
        let totalBytesOut: UInt64
        let perInterface: [NetworkInterfaceSample]
    }

    func sample() -> Sample {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
            return Sample(interfaces: 0, bytesInPerSecond: 0, bytesOutPerSecond: 0, totalBytesIn: 0, totalBytesOut: 0, perInterface: [])
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else {
            return Sample(interfaces: 0, bytesInPerSecond: 0, bytesOutPerSecond: 0, totalBytesIn: 0, totalBytesOut: 0, perInterface: [])
        }

        // (接口索引, 名称, IFLIST2 自带计数器（作 IFMIB 失败时的回退）)
        var discovered: [(index: UInt16, name: String, fallbackIn: UInt64, fallbackOut: UInt64)] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr2>.size
            while offset + headerSize <= length {
                var header = if_msghdr2()
                withUnsafeMutableBytes(of: &header) { destination in
                    destination.copyBytes(from: UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + headerSize)]))
                }

                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    let name: String? = nameBuffer.withUnsafeMutableBufferPointer { pointer in
                        guard let base = pointer.baseAddress,
                              if_indextoname(UInt32(header.ifm_index), base) != nil else { return nil }
                        return String(cString: base)
                    }
                    if let name, name != "lo0" {
                        discovered.append((header.ifm_index, name, header.ifm_data.ifi_ibytes, header.ifm_data.ifi_obytes))
                    }
                }
                offset += messageLength
            }
        }

        var interfaces = 0
        var current: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        var baudrates: [String: UInt64] = [:]
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        for item in discovered {
            let counters: (UInt64, UInt64)
            var baudrate: UInt64 = 0
            if !item.name.hasPrefix("en") && item.fallbackIn == 0 && item.fallbackOut == 0 {
                // 无流量的虚拟接口不必逐条查 IFMIB（实测可省 ~2/3 的系统调用）；物理网卡要查，连接速率就在里面
                counters = (0, 0)
            } else if let data = Self.ifdata(ifIndex: item.index) {
                counters = (data.inBytes, data.outBytes)
                baudrate = data.baudrate
            } else {
                counters = (item.fallbackIn, item.fallbackOut)
            }
            interfaces += 1
            current[item.name] = counters
            if baudrate > 0 { baudrates[item.name] = baudrate }
            totalIn &+= counters.0
            totalOut &+= counters.1
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastSampleTime == 0 ? 0 : Double(now - lastSampleTime) / 1_000_000_000.0
        lastSampleTime = now

        var deltaIn: UInt64 = 0
        var deltaOut: UInt64 = 0
        var rates: [String: (in: Double, out: Double)] = [:]
        for (name, counters) in current {
            guard let old = previous[name] else { rates[name] = (0, 0); continue }
            var deltaPair: (UInt64, UInt64) = (0, 0)
            if counters.bytesIn >= old.bytesIn { deltaPair.0 = counters.bytesIn - old.bytesIn }
            if counters.bytesOut >= old.bytesOut { deltaPair.1 = counters.bytesOut - old.bytesOut }
            deltaIn &+= deltaPair.0
            deltaOut &+= deltaPair.1
            rates[name] = elapsed > 0 ? (Double(deltaPair.0) / elapsed, Double(deltaPair.1) / elapsed) : (0, 0)
        }
        previous = current

        tick &+= 1
        if tick % 5 == 1 || wifiCache.isEmpty {
            refreshWiFiDetails()
        }

        let link = Self.linkInfo()
        var perInterface: [NetworkInterfaceSample] = []
        for item in discovered {
            guard let counters = current[item.name] else { continue }
            let info = link[item.name]
            let rate = rates[item.name] ?? (0, 0)
            perInterface.append(NetworkInterfaceSample(
                name: item.name,
                isUp: info?.up ?? false,
                isWiFi: wifiNames.contains(item.name),
                mac: info?.mac ?? "",
                ipv4: info?.ipv4 ?? [],
                baudrateBps: baudrates[item.name] ?? 0,
                wifi: wifiCache[item.name],
                bytesIn: counters.bytesIn,
                bytesOut: counters.bytesOut,
                inPerSecond: rate.in,
                outPerSecond: rate.out
            ))
        }
        perInterface.sort { $0.name < $1.name }

        return Sample(
            interfaces: interfaces,
            bytesInPerSecond: elapsed > 0 ? Double(deltaIn) / elapsed : 0,
            bytesOutPerSecond: elapsed > 0 ? Double(deltaOut) / elapsed : 0,
            totalBytesIn: totalIn,
            totalBytesOut: totalOut,
            perInterface: perInterface
        )
    }

    /// net.link.generic.ifdata.<ifindex>.general → ifmibdata（内含 if_data64 与连接速率）
    private static func ifdata(ifIndex: UInt16) -> (inBytes: UInt64, outBytes: UInt64, baudrate: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(ifIndex), IFDATA_GENERAL]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, 6, &data, &size, nil, 0) == 0 else { return nil }
        return (data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes, UInt64(data.ifmd_data.ifi_baudrate))
    }

    /// getifaddrs：MAC（AF_LINK）与 IPv4 地址、UP 标志
    private static func linkInfo() -> [String: (mac: String, ipv4: [String], up: Bool)] {
        var result: [String: (mac: String, ipv4: [String], up: Bool)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let list else { return result }
        defer { freeifaddrs(list) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = list
        while let entry = cursor {
            let name = String(cString: entry.pointee.ifa_name)
            if name != "lo0", let address = entry.pointee.ifa_addr {
                var item = result[name] ?? ("", [], false)
                if entry.pointee.ifa_flags & UInt32(IFF_UP) != 0 { item.up = true }
                switch Int32(address.pointee.sa_family) {
                case AF_LINK:
                    // sockaddr_dl 头 8 字节后是 sdl_data（先放接口名再放硬件地址）。
                    // 名字长的接口（如 bridge0）硬件地址会超出 20 字节结构体，
                    // 必须按 sa_len 边界从原始缓冲区读，不能拷贝结构体值。
                    let saLen = Int(address.pointee.sa_len)
                    if saLen >= 8 {
                        let raw = UnsafeRawPointer(address)
                        let nlen = Int(raw.load(fromByteOffset: 5, as: UInt8.self))
                        let alen = Int(raw.load(fromByteOffset: 6, as: UInt8.self))
                        let start = 8 + nlen
                        if alen > 0, start + alen <= saLen {
                            let bytes = (0..<alen).map { raw.load(fromByteOffset: start + $0, as: UInt8.self) }
                            item.mac = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                        }
                    }
                case AF_INET:
                    if let text = ipString(address) { item.ipv4.append(text) }
                default: break
                }
                result[name] = item
            }
            cursor = entry.pointee.ifa_next
        }
        return result
    }

    private static func ipString(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        var text = String(cString: host)
        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) } // 去掉 scope 后缀
        return text
    }

    /// CoreWLAN：接口名集合 + 每接口 WiFi 详情
    private func refreshWiFiDetails() {
        guard let interfaces = CWWiFiClient.shared().interfaces() else { return }
        var names = Set<String>()
        var infos: [String: WiFiInfo] = [:]
        for interface in interfaces {
            guard let name = interface.interfaceName else { continue }
            names.insert(name)

            // SSID：定位权限被拒时为 nil；ssidData 是同一信息的字节形式，顺带兜底
            let ssid = interface.ssid() ?? interface.ssidData().flatMap { String(data: $0, encoding: .utf8) }

            var channel = "不可用"
            if let ch = interface.wlanChannel() {
                let band: String
                switch ch.channelBand {
                case .band2GHz: band = "2.4 GHz"
                case .band5GHz: band = "5 GHz"
                case .band6GHz: band = "6 GHz"
                default: band = "未知"
                }
                let width: String
                switch ch.channelWidth {
                case .width20MHz: width = "20 MHz"
                case .width40MHz: width = "40 MHz"
                case .width80MHz: width = "80 MHz"
                case .width160MHz: width = "160 MHz"
                default: width = "未知"
                }
                channel = "\(ch.channelNumber) • \(band) • \(width)"
            }

            // CWSecurity 的 Swift 前缀剥离不稳定（kCWSecurityWEP 等），按原始值映射
            let security: String
            switch interface.security().rawValue {
            case 0: security = "开放"
            case 1: security = "WEP"
            case 2: security = "WPA 个人"
            case 3: security = "WPA 混合"
            case 4: security = "WPA2 个人"
            case 5: security = "WPA2/WPA3 个人"
            case 6: security = "动态 WEP"
            case 7: security = "WPA 企业"
            case 8: security = "WPA 企业混合"
            case 9: security = "WPA2 企业"
            case 10: security = "WPA2/WPA3 企业"
            case 11: security = "WPA3 个人"
            case 12: security = "WPA3 企业"
            case 13: security = "WPA2/WPA3 过渡"
            case 14: security = "OWE"
            case 15: security = "OWE 过渡"
            default: security = "未知"
            }

            infos[name] = WiFiInfo(
                ssid: ssid,
                channel: channel,
                transmitMbps: interface.transmitRate(),
                rssi: interface.rssiValue(),
                noise: interface.noiseMeasurement(),
                security: security
            )
        }
        wifiNames = names
        wifiCache = infos
    }
}
