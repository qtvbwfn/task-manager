import Darwin
import Foundation
import IOKit
import IOKit.ps

/// 单盘指标（按 bsdName）：速率 / 累计 / 活跃时间 / 平均响应
struct DiskMetrics {
    let readPerSecond: Double
    let writePerSecond: Double
    let totalReadBytes: UInt64
    let totalWriteBytes: UInt64
    let activeTimePercent: Double
    let avgResponseMs: Double?
}

struct IOKitSample {
    let temperature: Double?        // °C（CPU/SoC 热点，各 CPU 传感器最大值）
    let sensorTemperatures: [String: Double]  // SMC 传感器 key → °C
    let gpuUtilization: Double?     // %
    let diskReadPerSecond: Double
    let diskWritePerSecond: Double
    let perDisk: [String: DiskMetrics]   // 按 bsdName 的每盘指标（性能页多盘切换 / 系统信息页）
    let diskTotalReadBytes: UInt64      // 开机以来累计
    let diskTotalWriteBytes: UInt64
    let diskActiveTimePercent: Double   // Busy Time 差分 / 经过时间
    let diskAvgResponseMs: Double?      // (读耗时 + 写耗时) / 操作数
    let watts: Double?              // 实时功耗
    let batteryPercent: Int?        // 0–100
    let isCharging: Bool
    let powerSource: String         // 交流电源 / 电池
    let adapterWatts: Int?          // 适配器额定瓦数
    let batteryHealthPercent: Double?
    let cycleCount: Int?
    let hasBattery: Bool
}

/// 无文档私有接口全部隔离在本文件：SMC 温度 / IOAccelerator / 磁盘 IO / 电池。
/// 任一接口失败只影响对应字段（nil），不影响其他采样。
final class IOKitSampler {
    private let smc = SMCConnection()
    private var previousDisk: (stats: DiskStats, time: UInt64)?
    private var previousDiskByBSD: [String: DiskStats] = [:]

    private static let batteryInfo: (hasBattery: Bool, design: Int, rawMax: Int, cycles: Int) = {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator) == KERN_SUCCESS else {
            return (false, 0, 0, 0)
        }
        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return (false, 0, 0, 0) }
        defer { IOObjectRelease(entry) }

        func intProperty(_ name: String) -> Int {
            guard let unmanaged = IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0) else { return 0 }
            let value = unmanaged.takeRetainedValue()
            return (value as? NSNumber)?.intValue ?? 0
        }
        let design = intProperty("DesignCapacity")
        let rawMax = intProperty("AppleRawMaxCapacity")
        let cycles = intProperty("CycleCount")
        return (design > 0, design, rawMax, cycles)
    }()

    private static let gpuName: String = {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPCIDevice"), &iterator) == KERN_SUCCESS else { return "不可用" }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            guard let unmanaged = IORegistryEntryCreateCFProperty(entry, "model" as CFString, kCFAllocatorDefault, 0) else { continue }
            let value = unmanaged.takeRetainedValue()
            if let data = value as? Data, let name = String(data: data, encoding: .ascii) {
                return name.trimmingCharacters(in: .controlCharacters)
            }
        }
        return "不可用"
    }()

    static var gpuModel: String { gpuName }

    func sample() -> IOKitSample {
        // 温度传感器：TMOG 温度页展示的 CPU core/PECI/proximity + 电池
        let sensorKeys = ["TC0E", "TC0F", "TCXC", "TC0P", "TB0T"]
        let sensorTemperatures = smc.temperatures(for: sensorKeys)
        let hotspot = ["TC0E", "TC0F", "TCXC", "TC0P"]
            .compactMap { sensorTemperatures[$0] }
            .max()
        let temperature = hotspot ?? smc.temperature()
        let gpu = gpuUtilization()
        let disk = diskRates()
        let power = powerState()

        // 实时功耗优先取 SMC 系统总功耗（PSTR）；失败时退回电池瞬时电流×电压
        let watts: Double?
        if let systemWatts = smc.powerWatts() {
            watts = systemWatts
        } else if let battery = smartBattery() {
            watts = abs(Double(battery.voltage) * Double(battery.amperage)) / 1_000_000.0
        } else {
            watts = nil
        }

        let health: Double?
        if Self.batteryInfo.hasBattery && Self.batteryInfo.design > 0 {
            health = Double(Self.batteryInfo.rawMax) / Double(Self.batteryInfo.design) * 100.0
        } else {
            health = nil
        }

        return IOKitSample(
            temperature: temperature,
            sensorTemperatures: sensorTemperatures,
            gpuUtilization: gpu,
            diskReadPerSecond: disk.read,
            diskWritePerSecond: disk.write,
            perDisk: disk.perDisk,
            diskTotalReadBytes: disk.totals.readBytes,
            diskTotalWriteBytes: disk.totals.writeBytes,
            diskActiveTimePercent: disk.activePercent,
            diskAvgResponseMs: disk.avgResponseMs,
            watts: watts,
            batteryPercent: power.percent,
            isCharging: power.charging,
            powerSource: power.source,
            adapterWatts: Self.adapterWatts(),
            batteryHealthPercent: health,
            cycleCount: Self.batteryInfo.hasBattery ? Self.batteryInfo.cycles : nil,
            hasBattery: Self.batteryInfo.hasBattery
        )
    }

    // MARK: - GPU

    private func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var result: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if result == nil,
               let unmanaged = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
               let dict = unmanaged.takeRetainedValue() as? [String: Any] {
                if let value = dict["Device Unit 0 Utilization %"] as? Int {
                    result = Double(value)
                } else if let value = dict["Device Unit 0 Utilization %"] as? Double {
                    result = value
                } else if let value = dict["Device Utilization % at cur p-state"] as? Int {
                    result = Double(value)
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return result
    }

    // MARK: - 磁盘 IO

    private struct DiskStats {
        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0
        var ops: UInt64 = 0
        var timeMs: UInt64 = 0
        var busyMs: UInt64 = 0
    }

    private func diskRates() -> (read: Double, write: Double, perDisk: [String: DiskMetrics], totals: DiskStats, activePercent: Double, avgResponseMs: Double?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return (0, 0, [:], DiskStats(), 0, nil)
        }
        defer { IOObjectRelease(iterator) }

        var totals = DiskStats()
        var current: [String: DiskStats] = [:]
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let bsdName = Self.bsdName(ofStorageDriver: entry) ?? "unknown"
            if let unmanaged = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0),
               let dict = unmanaged.takeRetainedValue() as? [String: Any] {
                func counter(_ key: String) -> UInt64 {
                    (dict[key] as? NSNumber)?.uint64Value ?? 0
                }
                var disk = DiskStats()
                disk.readBytes = counter("Bytes (Read)")
                disk.writeBytes = counter("Bytes (Write)")
                disk.ops = counter("Operations (Read)") + counter("Operations (Write)")
                disk.timeMs = counter("Read Time (ms)") + counter("Write Time (ms)")
                disk.busyMs = counter("Busy Time (ms)")
                current[bsdName] = disk
                totals.readBytes += disk.readBytes
                totals.writeBytes += disk.writeBytes
                totals.ops += disk.ops
                totals.timeMs += disk.timeMs
                totals.busyMs += disk.busyMs
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let previous = previousDisk
        let elapsed = previous.map { Double(now &- $0.time) / 1_000_000_000.0 } ?? 0
        previousDisk = (totals, now)

        var readRate: Double = 0
        var writeRate: Double = 0
        var activePercent: Double = 0
        var avgResponseMs: Double?
        if let previous, elapsed > 0 {
            readRate = totals.readBytes >= previous.stats.readBytes ? Double(totals.readBytes - previous.stats.readBytes) / elapsed : 0
            writeRate = totals.writeBytes >= previous.stats.writeBytes ? Double(totals.writeBytes - previous.stats.writeBytes) / elapsed : 0
            let deltaBusyMs = totals.busyMs >= previous.stats.busyMs ? totals.busyMs - previous.stats.busyMs : 0
            activePercent = min(100, Double(deltaBusyMs) / (elapsed * 1000) * 100)
            let deltaOps = totals.ops >= previous.stats.ops ? totals.ops - previous.stats.ops : 0
            let deltaTimeMs = totals.timeMs >= previous.stats.timeMs ? totals.timeMs - previous.stats.timeMs : 0
            if deltaOps > 0 {
                avgResponseMs = Double(deltaTimeMs) / Double(deltaOps)
            }
        }

        // 每盘独立差分：首帧或该盘刚出现时无历史 → 零值占位
        var perDisk: [String: DiskMetrics] = [:]
        for (name, disk) in current {
            var diskRead = 0.0
            var diskWrite = 0.0
            var active = 0.0
            var response: Double?
            if let old = previousDiskByBSD[name], elapsed > 0 {
                diskRead = disk.readBytes >= old.readBytes ? Double(disk.readBytes - old.readBytes) / elapsed : 0
                diskWrite = disk.writeBytes >= old.writeBytes ? Double(disk.writeBytes - old.writeBytes) / elapsed : 0
                let deltaBusyMs = disk.busyMs >= old.busyMs ? disk.busyMs - old.busyMs : 0
                active = min(100, Double(deltaBusyMs) / (elapsed * 1000) * 100)
                let deltaOps = disk.ops >= old.ops ? disk.ops - old.ops : 0
                let deltaTimeMs = disk.timeMs >= old.timeMs ? disk.timeMs - old.timeMs : 0
                if deltaOps > 0 {
                    response = Double(deltaTimeMs) / Double(deltaOps)
                }
            }
            perDisk[name] = DiskMetrics(
                readPerSecond: diskRead,
                writePerSecond: diskWrite,
                totalReadBytes: disk.readBytes,
                totalWriteBytes: disk.writeBytes,
                activeTimePercent: active,
                avgResponseMs: response
            )
        }
        previousDiskByBSD = current
        return (readRate, writeRate, perDisk, totals, activePercent, avgResponseMs)
    }

    /// IOBlockStorageDriver 的 BSD 名在子节点 IOMedia 上（方案 §0：盘名经 IOMedia 子对象）
    private static func bsdName(ofStorageDriver entry: io_registry_entry_t) -> String? {
        var child: io_registry_entry_t = 0
        let result = "IOService".withCString { plane in
            IORegistryEntryGetChildEntry(entry, plane, &child)
        }
        guard result == KERN_SUCCESS, child != 0 else { return nil }
        defer { IOObjectRelease(child) }
        guard let unmanaged = IORegistryEntryCreateCFProperty(child, "BSD Name" as CFString, kCFAllocatorDefault, 0) else { return nil }
        return unmanaged.takeRetainedValue() as? String
    }

    // MARK: - 电源

    private func powerState() -> (percent: Int?, charging: Bool, source: String) {
        var percent: Int?
        var charging = false
        var source = "交流电源"

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for sourceRef in list {
                guard let unmanaged = IOPSGetPowerSourceDescription(blob, sourceRef) else { continue }
                // IOPSGetPowerSourceDescription 返回 +0（不持有），必须 unretained
                guard let dict = unmanaged.takeUnretainedValue() as? [String: Any] else { continue }
                if let state = dict[kIOPSPowerSourceStateKey] as? String {
                    source = state == kIOPSACPowerValue ? "交流电源" : "电池"
                }
                if let current = dict[kIOPSCurrentCapacityKey] as? Int,
                   let maximum = dict[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                    percent = current * 100 / maximum
                }
                if let value = dict[kIOPSIsChargingKey] as? Bool {
                    charging = value
                }
            }
        }
        return (percent, charging, source)
    }

    private func smartBattery() -> (voltage: Int, amperage: Int)? {
        guard Self.batteryInfo.hasBattery else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        func intProperty(_ name: String) -> Int? {
            guard let unmanaged = IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0) else { return nil }
            return (unmanaged.takeRetainedValue() as? NSNumber)?.intValue
        }
        guard let voltage = intProperty("Voltage"), let amperage = intProperty("InstantAmperage") else { return nil }
        return (voltage, amperage)
    }

    private static func adapterWatts() -> Int? {
        guard let unmanaged = IOPSCopyExternalPowerAdapterDetails() else { return nil }
        guard let details = unmanaged.takeRetainedValue() as? [String: Any] else { return nil }
        return details["Watts"] as? Int
    }
}

// MARK: - SMC

/// AppleSMC 用户客户端（协议常量移植自 exelban/stats，直调 IOConnectCallStructMethod）。
final class SMCConnection {
    private struct KeyData {
        struct Vers { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct LimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
        struct KeyInfo { var dataSize: IOByteCount32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Selector {
        static let kernelIndex: UInt32 = 2
        static let readBytes: UInt8 = 5
        static let readKeyInfo: UInt8 = 9
    }

    private var connection: io_connect_t = 0
    private var opened = false
    private var failed = false

    deinit {
        if opened, connection != 0 {
            IOServiceClose(connection)
        }
    }

    func temperature() -> Double? {
        guard ensureOpen(),
              let key = readKey("TC0P"), key.type == "sp78", key.size >= 2 else { return nil }
        return SMCCodec.decodeSP78(Array(key.bytes.prefix(2)))
    }

    /// 批量读取 SMC 温度传感器（sp78，°C）
    func temperatures(for keys: [String]) -> [String: Double] {
        guard ensureOpen() else { return [:] }
        var result: [String: Double] = [:]
        for key in keys {
            guard let value = readKey(key), value.type == "sp78", value.size >= 2 else { continue }
            let temperature = SMCCodec.decodeSP78(Array(value.bytes.prefix(2)))
            if temperature.isFinite, temperature > -20, temperature < 150 {
                result[key] = temperature
            }
        }
        return result
    }

    /// 系统总功耗（SMC PSTR，flt 小端 Float，单位 W）
    func powerWatts() -> Double? {
        guard ensureOpen(),
              let key = readKey("PSTR"), key.type == "flt ", key.size >= 4 else { return nil }
        let bytes = key.bytes
        let bits = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
        let watts = Double(Float(bitPattern: bits))
        guard watts.isFinite, watts >= 0, watts < 1_000 else { return nil }
        return watts
    }

    private func ensureOpen() -> Bool {
        guard !failed else { return false }
        if !opened {
            opened = open()
            if !opened {
                failed = true
                return false
            }
        }
        return true
    }

    private func open() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        let device = IOIteratorNext(iterator)
        guard device != 0 else { return false }
        defer { IOObjectRelease(device) }
        return IOServiceOpen(device, mach_task_self_, 0, &connection) == KERN_SUCCESS
    }

    private func call(_ input: inout KeyData, _ output: inout KeyData) -> kern_return_t {
        var outputSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(connection, Selector.kernelIndex, &input, MemoryLayout<KeyData>.stride, &output, &outputSize)
    }

    private func readKey(_ name: String) -> (type: String, size: UInt32, bytes: [UInt8])? {
        var fourCC: UInt32 = 0
        for byte in name.utf8 { fourCC = fourCC << 8 | UInt32(byte) }

        var input = KeyData()
        var output = KeyData()
        input.key = fourCC
        input.data8 = Selector.readKeyInfo
        guard call(&input, &output) == KERN_SUCCESS, output.result == 0 else { return nil }

        let size = UInt32(output.keyInfo.dataSize)
        let typeValue = output.keyInfo.dataType
        let type = String(
            bytes: [typeValue >> 24 & 0xff, typeValue >> 16 & 0xff, typeValue >> 8 & 0xff, typeValue & 0xff].map { UInt8($0) },
            encoding: .ascii
        ) ?? "?"

        input = KeyData()
        output = KeyData()
        input.key = fourCC
        input.keyInfo.dataSize = IOByteCount32(size)
        input.data8 = Selector.readBytes
        guard call(&input, &output) == KERN_SUCCESS, output.result == 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: 32)
        withUnsafeBytes(of: &output.bytes) { raw in
            if let base = raw.baseAddress { memcpy(&bytes, base, 32) }
        }
        return (type, size, bytes)
    }
}