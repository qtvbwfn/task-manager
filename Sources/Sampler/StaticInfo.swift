import Darwin
import Foundation

/// 启动时读取一次的静态系统信息（sysctl 两阶段查询）。
enum StaticInfo {
    static let cpuBrand: String = sysctlString("machdep.cpu.brand_string")
    static let model: String = sysctlString("hw.model")
    static let machine: String = sysctlString("hw.machine")
    static let physicalCores: Int = sysctlInt("hw.physicalcpu")
    static let logicalCores: Int = sysctlInt("hw.logicalcpu")
    static let l2Cache: Int = sysctlInt("hw.l2cachesize")
    static let l3Cache: Int = sysctlInt("hw.l3cachesize")
    static let baseFrequency: Int = sysctlInt("hw.cpufrequency")
    static let memorySize: UInt64 = UInt64(max(0, sysctlInt64("hw.memsize")))
    static let osVersion: String = {
        let version = Foundation.ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }()
    static let hostName: String = Foundation.ProcessInfo.processInfo.hostName
    static let bootDate: Date = {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &bootTime, &size, nil, 0)
        return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1_000_000.0)
    }()

    static func sysctlString(_ name: String) -> String {
        var length = 0
        guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0 else { return "不可用" }
        var buffer = [CChar](repeating: 0, count: length)
        guard sysctlbyname(name, &buffer, &length, nil, 0) == 0 else { return "不可用" }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }

    static func sysctlInt64(_ name: String) -> Int64 {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return value
    }

    /// 频率格式化（GHz）
    static func frequency(_ hertz: Int) -> String {
        hertz > 0 ? String(format: "%.2f GHz", Double(hertz) / 1_000_000_000.0) : "不可用"
    }

    static func cacheSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "不可用" }
        if bytes >= 1_048_576 {
            return String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024.0)
    }
}