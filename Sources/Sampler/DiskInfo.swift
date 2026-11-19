import Darwin
import Foundation
import IOKit

/// 物理盘标识（启动时读取一次）：性能页磁盘详情的大标题 / 副标题 / 静态指标。
struct DiskIdentity {
    let model: String
    let bsdName: String
    let medium: String        // IORegistry 原值："Solid State" / "Hard Disk Drive"
    let interconnect: String  // "NVMe" / "SATA"（PCI-Express + 固态硬盘映射为 NVMe，对标 TMOG）
    let size: UInt64
    let isSystemDisk: Bool
    let fileSystem: String    // "APFS"（仅系统盘有意义，其余为空）
}

enum DiskInfo {
    static let identities: [DiskIdentity] = load()

    /// 系统卷所在盘；找不到时退回首块盘
    static var primary: DiskIdentity? {
        identities.first(where: { $0.isSystemDisk }) ?? identities.first
    }

    private struct RootStatfs {
        var device = ""   // /dev/disk1s4s1
        var fstype = ""   // apfs
    }

    private static func rootStatfsStrings() -> RootStatfs {
        var st = statfs()
        var result = RootStatfs()
        guard statfs("/", &st) == 0 else { return result }
        result.device = withUnsafePointer(to: &st.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        result.fstype = withUnsafePointer(to: &st.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return result
    }

    /// "/" 所在基础盘名（diskN）：statfs 的 /dev/disk1s4s1 去掉分区后缀
    private static let systemBSD: String? = {
        let dev = rootStatfsStrings().device
        guard let start = dev.range(of: "disk")?.upperBound else { return nil }
        var digits = ""
        for ch in dev[start...] {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        return digits.isEmpty ? nil : "disk" + digits
    }()

    /// 系统卷所在物理盘 BSD 名：APFS 下 "/" 挂在容器逻辑盘（如 disk1），需沿 IORegistry 上溯到物理盘设备
    private static let systemPhysicalBSD: String? = {
        guard let base = systemBSD else { return nil }
        return physicalBSD(forLogical: base) ?? base
    }()

    /// "/" 的文件系统类型（大写，如 "APFS"）
    private static let systemFS: String = {
        rootStatfsStrings().fstype.uppercased()
    }()

    private static func physicalBSD(forLogical name: String) -> String? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var candidate = IOIteratorNext(iterator)
        while candidate != 0 {
            defer { IOObjectRelease(candidate); candidate = IOIteratorNext(iterator) }
            guard let unmanaged = IORegistryEntryCreateCFProperty(candidate, "BSD Name" as CFString, kCFAllocatorDefault, 0),
                  (unmanaged.takeRetainedValue() as? String) == name else { continue }

            var current = candidate
            IOObjectRetain(current)
            defer { IOObjectRelease(current) }
            while true {
                var parent: io_registry_entry_t = 0
                guard "IOService".withCString({ IORegistryEntryGetParentEntry(current, $0, &parent) }) == KERN_SUCCESS, parent != 0 else { break }
                if IOObjectConformsTo(parent, "IOBlockStorageDevice") != 0 {
                    var result: String?
                    if let media = mediaEntry(of: parent) {
                        defer { IOObjectRelease(media) }
                        if let value = IORegistryEntryCreateCFProperty(media, "BSD Name" as CFString, kCFAllocatorDefault, 0) {
                            result = value.takeRetainedValue() as? String
                        }
                    }
                    IOObjectRelease(parent)
                    if let result { return result }
                    break
                }
                IOObjectRelease(current)
                current = parent
            }
        }
        return nil
    }

    private static func mediaEntry(of device: io_registry_entry_t) -> io_registry_entry_t? {
        var driver: io_registry_entry_t = 0
        guard "IOService".withCString({ IORegistryEntryGetChildEntry(device, $0, &driver) }) == KERN_SUCCESS, driver != 0 else {
            return nil
        }
        var media: io_registry_entry_t = 0
        let result = "IOService".withCString { IORegistryEntryGetChildEntry(driver, $0, &media) }
        IOObjectRelease(driver)
        guard result == KERN_SUCCESS, media != 0 else { return nil }
        return media
    }

    private static func load() -> [DiskIdentity] {
        var results: [DiskIdentity] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }

            func property(_ name: String, of target: io_registry_entry_t) -> Any? {
                guard let unmanaged = IORegistryEntryCreateCFProperty(target, name as CFString, kCFAllocatorDefault, 0) else {
                    return nil
                }
                return unmanaged.takeRetainedValue()
            }

            guard let characteristics = property("Device Characteristics", of: entry) as? [String: Any],
                  let rawModel = characteristics["Product Name"] as? String else { continue }
            let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))

            var bsdName = ""
            var size: UInt64 = 0
            if let media = mediaEntry(of: entry) {
                defer { IOObjectRelease(media) }
                bsdName = property("BSD Name", of: media) as? String ?? ""
                size = (property("Size", of: media) as? NSNumber)?.uint64Value ?? 0
            }

            let medium = characteristics["Medium Type"] as? String ?? "不可用"
            let protocolCharacteristics = property("Protocol Characteristics", of: entry) as? [String: Any]
            let rawInterconnect = protocolCharacteristics?["Physical Interconnect"] as? String ?? "不可用"
            // 对标 TMOG：PCI-Express + 固态硬盘即 NVMe
            let interconnect = rawInterconnect == "PCI-Express" && medium == "Solid State" ? "NVMe" : rawInterconnect
            let isSystem = !bsdName.isEmpty && bsdName == systemPhysicalBSD

            results.append(DiskIdentity(
                model: model.isEmpty ? "不可用" : model,
                bsdName: bsdName.isEmpty ? "不可用" : bsdName,
                medium: medium,
                interconnect: interconnect,
                size: size,
                isSystemDisk: isSystem,
                fileSystem: isSystem ? systemFS : ""
            ))
        }
        // 系统盘排最前，保证 primary 退化路径也取到它
        return results.sorted { $0.isSystemDisk && !$1.isSystemDisk }
    }
}
