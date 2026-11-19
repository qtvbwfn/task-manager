import Darwin
import Foundation

/// 系统级采样：逐核 CPU（tick 差分）、内存（host_statistics64）、swap、压力。
final class SystemSampler {
    private var previousTicks: [(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64)] = []

    func sample() -> SystemSnapshot {
        let now = Date()

        let (perCore, total, kernel) = sampleCPU()
        var memoryUsed: UInt64 = 0
        var memoryAvailable: UInt64 = 0
        var memoryCached: UInt64 = 0
        var memoryCompressed: UInt64 = 0
        var memoryWired: UInt64 = 0
        var pageIns: UInt64 = 0
        var pageOuts: UInt64 = 0
        let (swapUsed, swapTotal) = Self.sampleSwap()
        let pressure = Self.samplePressure()

        var stats = vm_statistics64_data_t()
        var statsCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(statsCount)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &statsCount)
            }
        }
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let active = UInt64(stats.active_count)
            let wired = UInt64(stats.wire_count)
            let compressed = UInt64(stats.compressor_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            let free = UInt64(stats.free_count)
            let inactive = UInt64(stats.inactive_count)

            let usedPages = active + wired + compressed
            memoryUsed = usedPages > purgeable ? (usedPages - purgeable) * pageSize : usedPages * pageSize
            memoryAvailable = (free + inactive) * pageSize
            memoryCached = purgeable * pageSize
            memoryCompressed = compressed * pageSize
            memoryWired = wired * pageSize
            pageIns = stats.pageins
            pageOuts = stats.pageouts
        }

        var memTotal: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memTotal, &size, nil, 0)

        return SystemSnapshot(
            timestamp: now,
            cpuTotal: total,
            perCore: perCore,
            kernelPercent: kernel,
            memoryUsed: memoryUsed,
            memoryTotal: memTotal,
            memoryAvailable: memoryAvailable,
            memoryCached: memoryCached,
            memoryCompressed: memoryCompressed,
            memoryWired: memoryWired,
            swapUsed: swapUsed,
            swapTotal: swapTotal,
            memoryPressure: pressure,
            pageIns: pageIns,
            pageOuts: pageOuts,
            uptime: Foundation.ProcessInfo.processInfo.systemUptime
        )
    }

    private func sampleCPU() -> (perCore: [Double], total: Double, kernel: Double) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t? = nil
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return ([], 0, 0) }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        var current: [(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64)] = []
        current.reserveCapacity(Int(cpuCount))
        for index in 0..<Int(cpuCount) {
            let base = UnsafeRawPointer(info).advanced(by: index * MemoryLayout<processor_cpu_load_info>.stride)
            let core = base.assumingMemoryBound(to: processor_cpu_load_info.self).pointee
            current.append((
                user: UInt64(core.cpu_ticks.0),
                system: UInt64(core.cpu_ticks.1),
                nice: UInt64(core.cpu_ticks.3),
                idle: UInt64(core.cpu_ticks.2)
            ))
        }

        defer { previousTicks = current }
        guard previousTicks.count == current.count else { return (Array(repeating: 0, count: current.count), 0, 0) }

        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        var totalBusy: UInt64 = 0
        var totalAll: UInt64 = 0
        var totalSystem: UInt64 = 0

        for index in 0..<current.count {
            let now = current[index]
            let prev = previousTicks[index]
            let busy = (now.user - prev.user) + (now.system - prev.system) + (now.nice - prev.nice)
            let idle = now.idle - prev.idle
            let all = busy + idle
            perCore.append(all > 0 ? Double(busy) / Double(all) * 100.0 : 0)
            totalBusy += busy
            totalAll += all
            totalSystem += now.system - prev.system
        }

        let total = totalAll > 0 ? Double(totalBusy) / Double(totalAll) * 100.0 : 0
        let kernel = totalAll > 0 ? Double(totalSystem) / Double(totalAll) * 100.0 : 0
        return (perCore, total, kernel)
    }

    static func swapUsage() -> (used: UInt64, total: UInt64, pageSize: UInt32) {
        var buffer = [UInt8](repeating: 0, count: 32)
        var size = buffer.count
        let result = sysctlbyname("vm.swapusage", &buffer, &size, nil, 0)
        guard result == 0, size >= 32 else { return (0, 0, 0) }
        let total = buffer.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self) }
        let used = buffer.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }
        let pageSize = buffer.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self) }
        return (used, total, pageSize)
    }

    private static func sampleSwap() -> (used: UInt64, total: UInt64) {
        let usage = swapUsage()
        return (usage.used, usage.total)
    }

    private static func samplePressure() -> Int32 {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0)
        return result == 0 ? value : -1
    }
}