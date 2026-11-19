import Darwin
import Foundation

/// M2 起生效的自检：`TaskManager --selftest`，0 = 全部通过。
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: String) {
            print("\(condition ? "PASS" : "FAIL")  \(name)  \(detail)")
            if !condition { failures += 1 }
        }

        // 1. swap 结构体偏移解析
        let swap = SystemSampler.swapUsage()
        check(
            "swap 结构体解析",
            swap.pageSize == 4096,
            "total=\(swap.total) used=\(swap.used) pageSize=\(swap.pageSize) (期望 4096)"
        )

        // 2. SMC sp78 解码
        let decoded = SMCCodec.decodeSP78([0x3d, 0xc0])
        check("SMC sp78 解码", abs(decoded - 61.75) < 0.001, "[0x3d,0xc0] → \(decoded) (期望 61.75)")

        // 3. NET_RT_IFLIST2 mib 遍历（64 位计数器，至少 1 个非回环接口）
        let network = NetworkSampler().sample()
        check("NET_RT_IFLIST2/IFMIB 接口枚举", network.interfaces > 0, "interfaces=\(network.interfaces) totalIn=\(network.totalBytesIn) totalOut=\(network.totalBytesOut)")

        // 4. vm_statistics64 字段和
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        let totalPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.free_count)
        check("vm_statistics64", vmResult == KERN_SUCCESS && totalPages > 0, "active+wire+free=\(totalPages) 页")

        // 5. rusage 差分两次采样
        let sampler = ProcessSampler()
        _ = sampler.sample()
        usleep(200_000)
        let second = sampler.sample()
        let selfUsage = second.first(where: { $0.pid == getpid() })
        check(
            "rusage 差分",
            selfUsage != nil && (selfUsage?.cpuPercent ?? -1) >= 0,
            "self cpu=\(selfUsage.map { String(format: "%.2f%%", $0.cpuPercent) } ?? "nil")"
        )

        // 6. 磁盘标识（IOBlockStorageDevice→Driver→IOMedia + statfs 系统盘映射）
        let disk = DiskInfo.primary
        check(
            "磁盘标识",
            disk != nil && disk!.size > 0 && disk!.bsdName.hasPrefix("disk") && disk!.isSystemDisk,
            "model=\(disk?.model ?? "nil") bsd=\(disk?.bsdName ?? "nil") medium=\(disk?.medium ?? "nil") interconnect=\(disk?.interconnect ?? "nil") size=\(disk?.size ?? 0) system=\(disk.map { $0.isSystemDisk ? "yes" : "no" } ?? "nil") fs=\(disk?.fileSystem ?? "nil")"
        )

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures) 项)")
        return failures == 0 ? 0 : 1
    }
}
extension SelfTest {
    /// `--benchall`：分项测量采样器单次耗时（毫秒）
    static func benchAll() -> Int32 {
        let processSampler = ProcessSampler()
        let systemSampler = SystemSampler()
        let iokitSampler = IOKitSampler()
        let networkSampler = NetworkSampler()
        _ = processSampler.sample()
        _ = systemSampler.sample()
        _ = iokitSampler.sample()
        _ = networkSampler.sample()

        func measure(_ name: String, _ body: () -> Void) -> Double {
            let rounds = 50
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<rounds {
                body()
            }
            let per = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0 / Double(rounds)
            print(String(format: "  %-16@ avg=%.2f ms", name as NSString, per))
            return per
        }

        let process = measure("ProcessSampler") { _ = processSampler.sample() }
        let system = measure("SystemSampler") { _ = systemSampler.sample() }
        let iokit = measure("IOKitSampler") { _ = iokitSampler.sample() }
        let network = measure("NetworkSampler") { _ = networkSampler.sample() }
        let total = process + system + iokit + network
        print(String(format: "TOTAL avg=%.2f ms → 1 Hz 下约 %.2f%% 单核", total, total / 10.0))
        return total < 40 ? 0 : 1
    }

    /// `--bench`：测量进程采样器单次耗时（毫秒）
    static func bench() -> Int32 {
        let sampler = ProcessSampler()
        _ = sampler.sample() // 预热
        usleep(100_000)
        var total: Double = 0
        let rounds = 10
        for _ in 0..<rounds {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = sampler.sample()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            total += elapsed
            if result.isEmpty { print("WARN empty sample") }
            usleep(100_000)
        }
        let avg = total / Double(rounds)
        print(String(format: "ProcessSampler avg=%.2f ms (processes=%d)", avg, sampler.sample().count))
        return avg < 50 ? 0 : 1
    }
}
