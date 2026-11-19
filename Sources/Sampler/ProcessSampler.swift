import Darwin
import Foundation

/// libproc 封装：一次遍历拿全量进程快照，CPU% 用 rusage 差分。
final class ProcessSampler {
    private var previous: [pid_t: UInt64] = [:]
    private var detailPrevious: (pid: pid_t, read: UInt64, write: UInt64, time: UInt64)?
    private var pathCache: [pid_t: (startTime: UInt64, path: String)] = [:]
    private var userNames: [uid_t: String] = [:]
    private var lastSampleTime: UInt64 = 0

    func sample() -> [ProcessInfo] {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        let capacity = Int(count)
        let buffer = UnsafeMutablePointer<pid_t>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        count = proc_listallpids(buffer, Int32(capacity * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastSampleTime == 0 ? 0 : now - lastSampleTime
        lastSampleTime = now

        var result: [ProcessInfo] = []
        result.reserveCapacity(Int(count))
        var alivePids = Set<pid_t>(minimumCapacity: Int(count))

        for index in 0..<Int(count) {
            let pid = buffer[index]
            guard pid > 0 else { continue }

            // 一次 PROC_PIDTASKALLINFO 同时拿 BSD + TASK 信息（比两次 proc_pidinfo 便宜）
            var taskAll = proc_taskallinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &taskAll, Int32(MemoryLayout<proc_taskallinfo>.size)) > 0 else { continue }
            let bsd = taskAll.pbsd
            let task = taskAll.ptinfo

            alivePids.insert(pid)

            let cpuTime = task.pti_total_user + task.pti_total_system

            var cpuPercent: Double = 0
            if let previous = previous[pid], elapsed > 0, cpuTime >= previous {
                cpuPercent = Double(cpuTime - previous) / Double(elapsed) * 100.0
            }
            previous[pid] = cpuTime

            let startKey = UInt64(bsd.pbi_start_tvsec)
            let path: String
            if let cached = pathCache[pid], cached.startTime == startKey {
                path = cached.path
            } else {
                var pathBuffer = [CChar](repeating: 0, count: 1024)
                var resolved = ""
                if proc_pidpath(pid, &pathBuffer, 1024) > 0 {
                    resolved = String(cString: pathBuffer)
                }
                pathCache[pid] = (startKey, resolved)
                path = resolved
            }

            let uid = bsd.pbi_uid
            let userName: String
            if let cached = userNames[uid] {
                userName = cached
            } else {
                var name = "未知"
                if let passwd = getpwuid(uid) {
                    name = String(cString: passwd.pointee.pw_name)
                }
                userNames[uid] = name
                userName = name
            }

            let appBundle = Self.appBundlePath(from: path)
            let fallbackName = withUnsafeBytes(of: bsd.pbi_comm) { raw in
                String(bytes: raw.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "未知"
            }
            let name = Self.displayName(path: path, fallback: fallbackName, appBundlePath: appBundle)

            // 列表用 resident 近似内存占用；Footprint / 磁盘 IO 在详情按需用 rusage 取
            let resident = task.pti_resident_size
            let footprint = resident
            let threads = task.pti_threadnum
            let faults = UInt64(task.pti_faults)
            let priority = task.pti_priority
            let policy = task.pti_policy

            let startTime = Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000.0)

            result.append(ProcessInfo(
                pid: pid,
                ppid: pid_t(bsd.pbi_ppid),
                uid: uid,
                userName: userName,
                name: name,
                executablePath: path,
                appBundlePath: appBundle,
                status: Int32(bsd.pbi_status),
                cpuPercent: cpuPercent,
                cpuTimeNanos: cpuTime,
                footprint: footprint,
                resident: resident,
                threads: threads,
                faults: faults,
                priority: priority,
                policy: policy,
                startTime: startTime,
                diskBytesRead: 0,
                diskBytesWritten: 0,
                diskReadPerSecond: 0,
                diskWritePerSecond: 0
            ))
        }

        previous = previous.filter { alivePids.contains($0.key) }
        pathCache = pathCache.filter { alivePids.contains($0.key) }

        return result
    }

    /// 详情按需采样：只对当前选中的 PID 调 rusage（Footprint + 磁盘 IO 差分）。
    func detail(pid: pid_t) -> ProcessDetail? {
        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) { pointer in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: UnsafeMutableRawPointer?.self))
        } == 0
        guard ok else { return nil }

        let now = DispatchTime.now().uptimeNanoseconds
        let read = usage.ri_diskio_bytesread
        let write = usage.ri_diskio_byteswritten
        var readRate: Double = 0
        var writeRate: Double = 0
        if let previous = detailPrevious, previous.pid == pid, now > previous.time {
            let elapsed = Double(now - previous.time) / 1_000_000_000.0
            if read >= previous.read { readRate = Double(read - previous.read) / elapsed }
            if write >= previous.write { writeRate = Double(write - previous.write) / elapsed }
        }
        detailPrevious = (pid, read, write, now)

        return ProcessDetail(
            footprint: usage.ri_phys_footprint,
            resident: usage.ri_resident_size,
            diskBytesRead: read,
            diskBytesWritten: write,
            diskReadPerSecond: readRate,
            diskWritePerSecond: writeRate
        )
    }

    static func appBundlePath(from path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.upperBound].dropLast())
    }

    static func displayName(path: String, fallback: String, appBundlePath: String?) -> String {
        if let bundle = appBundlePath {
            let last = (bundle as NSString).lastPathComponent
            return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
        }
        let base = (path as NSString).lastPathComponent
        return base.isEmpty ? fallback : base
    }
}