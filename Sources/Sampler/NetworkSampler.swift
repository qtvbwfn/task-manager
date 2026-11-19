import Darwin
import Foundation

/// 网络速率：NET_RT_IFLIST2 枚举接口（方案 §0 的 6 元素 mib），再用 net.link.generic.ifdata
/// 读取 64 位计数器。实测 macOS 15 对普通进程只往 if_msghdr2 里写低 32 位，IFMIB 才返回完整
/// 64 位累计值；差分求速率时按接口聚合，排除回环。
final class NetworkSampler {
    private var previous: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var lastSampleTime: UInt64 = 0

    struct Sample {
        let interfaces: Int
        let bytesInPerSecond: Double
        let bytesOutPerSecond: Double
        let totalBytesIn: UInt64
        let totalBytesOut: UInt64
    }

    func sample() -> Sample {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
            return Sample(interfaces: 0, bytesInPerSecond: 0, bytesOutPerSecond: 0, totalBytesIn: 0, totalBytesOut: 0)
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else {
            return Sample(interfaces: 0, bytesInPerSecond: 0, bytesOutPerSecond: 0, totalBytesIn: 0, totalBytesOut: 0)
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
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        for item in discovered {
            let counters: (UInt64, UInt64)
            if item.fallbackIn == 0 && item.fallbackOut == 0 {
                // 无流量的虚拟接口不必逐条查 IFMIB（实测可省 ~2/3 的系统调用）
                counters = (0, 0)
            } else {
                counters = Self.counters64(ifIndex: item.index) ?? (item.fallbackIn, item.fallbackOut)
            }
            interfaces += 1
            current[item.name] = counters
            totalIn &+= counters.0
            totalOut &+= counters.1
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastSampleTime == 0 ? 0 : Double(now - lastSampleTime) / 1_000_000_000.0
        lastSampleTime = now

        var deltaIn: UInt64 = 0
        var deltaOut: UInt64 = 0
        for (name, counters) in current {
            guard let old = previous[name] else { continue }
            if counters.bytesIn >= old.bytesIn { deltaIn &+= counters.bytesIn - old.bytesIn }
            if counters.bytesOut >= old.bytesOut { deltaOut &+= counters.bytesOut - old.bytesOut }
        }
        previous = current

        guard elapsed > 0 else {
            return Sample(interfaces: interfaces, bytesInPerSecond: 0, bytesOutPerSecond: 0, totalBytesIn: totalIn, totalBytesOut: totalOut)
        }
        return Sample(
            interfaces: interfaces,
            bytesInPerSecond: Double(deltaIn) / elapsed,
            bytesOutPerSecond: Double(deltaOut) / elapsed,
            totalBytesIn: totalIn,
            totalBytesOut: totalOut
        )
    }

    /// net.link.generic.ifdata.<ifindex>.general → ifmibdata（内含 if_data64）
    private static func counters64(ifIndex: UInt16) -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(ifIndex), IFDATA_GENERAL]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, 6, &data, &size, nil, 0) == 0 else { return nil }
        return (data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes)
    }
}
