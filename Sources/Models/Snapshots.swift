import Foundation

struct ProcessInfo: Sendable {
    let pid: pid_t
    let ppid: pid_t
    let uid: uid_t
    let userName: String
    let name: String
    let executablePath: String
    let appBundlePath: String?
    let status: Int32
    let cpuPercent: Double
    let cpuTimeNanos: UInt64
    let footprint: UInt64
    let resident: UInt64
    let threads: Int32
    let faults: UInt64
    let priority: Int32
    let policy: Int32
    let startTime: Date
    let diskBytesRead: UInt64
    let diskBytesWritten: UInt64
    let diskReadPerSecond: Double
    let diskWritePerSecond: Double

    var statusName: String {
        switch status {
        case 1: return "空闲"
        case 2: return "运行中"
        case 3: return "睡眠"
        case 4: return "已停止"
        case 5: return "僵尸"
        default: return "未知"
        }
    }

    var uptime: TimeInterval {
        max(0, Date().timeIntervalSince(startTime))
    }
}

struct ProcessDetail: Sendable {
    let footprint: UInt64
    let resident: UInt64
    let diskBytesRead: UInt64
    let diskBytesWritten: UInt64
    let diskReadPerSecond: Double
    let diskWritePerSecond: Double
}

struct SystemSnapshot: Sendable {
    let timestamp: Date
    let cpuTotal: Double
    let perCore: [Double]
    let kernelPercent: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let memoryAvailable: UInt64
    let memoryCached: UInt64
    let memoryCompressed: UInt64
    let memoryWired: UInt64
    let swapUsed: UInt64
    let swapTotal: UInt64
    let memoryPressure: Int32
    let pageIns: UInt64
    let pageOuts: UInt64
    let uptime: TimeInterval
}

extension Notification.Name {
    static let samplerDidUpdate = Notification.Name("tm.samplerDidUpdate")
}

enum Formats {
    /// 内存：< 1024 MB 显示 MB（1 位小数），≥ 1024 MB 显示 GB（2 位小数）
    static func memory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        return String(format: "%.2f GB", mb / 1024.0)
    }

    /// 速率：KB/s 或 MB/s
    static func rate(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB/s", kb)
        }
        return String(format: "%.2f MB/s", kb / 1024.0)
    }

    /// 网口连接速率：bits/s → Gb/s / Mb/s
    static func baudrate(_ bps: UInt64) -> String {
        let gbps = Double(bps) / 1_000_000_000.0
        if gbps >= 1 {
            return String(format: "%.2f Gb/s", gbps)
        }
        return String(format: "%.0f Mb/s", Double(bps) / 1_000_000.0)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    static func cpuTime(_ nanos: UInt64) -> String {
        let totalSeconds = Double(nanos) / 1_000_000_000.0
        let h = Int(totalSeconds) / 3600
        let m = (Int(totalSeconds) % 3600) / 60
        let s = Int(totalSeconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if d > 0 {
            return String(format: "%d天 %d:%02d:%02d", d, h, m, s)
        }
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}