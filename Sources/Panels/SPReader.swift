import Foundation

/// 通用 system_profiler JSON 读取器：按数据类型按需拉取、进程内缓存（对标 TMOG“系统信息”的数据源）。
/// 重型类型（字体 ~20s / 框架 ~3s / 扩展 ~1s）仅在该页首次打开时后台取数，取完即缓存；
/// 取数未完成前 `entries` 返回空数组，由调用方显示“正在读取…”。
enum SPReader {
    private static let lock = NSLock()
    private static var cache: [String: [[String: Any]]] = [:]
    private static var loaded: Set<String> = []
    private static var fetching: Set<String> = []
    private static var pendings: [String: [() -> Void]] = [:]
    private static let fetchQueue = DispatchQueue(label: "tm.spreader", qos: .userInitiated)

    /// 确保各数据类型已取回：未缓存的在后台一次批量拉取；完成后主线程回调。
    /// 并发请求同类型时挂起回调，取数完成统一触发。
    static func ensure(_ types: [String], completion: @escaping () -> Void) {
        lock.lock()
        var missing: [String] = []
        var allLoaded = true
        for type in types {
            if loaded.contains(type) { continue }
            allLoaded = false
            if fetching.contains(type) {
                pendings[type, default: []].append(completion)
            } else {
                fetching.insert(type)
                missing.append(type)
            }
        }
        lock.unlock()
        guard !allLoaded else { completion(); return }
        guard !missing.isEmpty else { return }  // 同类型取数进行中，完成时统一触发

        fetchQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = missing + ["-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var fetched: [String: [[String: Any]]] = [:]
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for type in missing where json[type] != nil {
                        fetched[type] = json[type] as? [[String: Any]] ?? []
                    }
                }
            } catch {}
            lock.lock()
            cache.merge(fetched) { _, new in new }
            var done: [() -> Void] = []
            for type in missing {
                loaded.insert(type)
                fetching.remove(type)
                done.append(contentsOf: pendings.removeValue(forKey: type) ?? [])
            }
            lock.unlock()
            DispatchQueue.main.async {
                completion()
                done.forEach { $0() }
            }
        }
    }

    /// 已取回（或取数为空）则返回数据；未取回返回 nil。
    static func entries(_ type: String) -> [[String: Any]]? {
        lock.lock(); defer { lock.unlock() }
        guard loaded.contains(type) else { return nil }
        return cache[type] ?? []
    }

    static func isLoaded(_ type: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return loaded.contains(type)
    }

    static func first(_ type: String) -> [String: Any]? {
        entries(type)?.first
    }

    /// 按 `_name` 在条目数组中查找（SPPowerDataType 等按名区分多条）。
    static func find(_ type: String, _ name: String) -> [String: Any]? {
        (entries(type) ?? []).first { (value($0, "_name") ?? "") == name }
    }

    /// 取值并转字符串；JSON 数字（解析为 NSNumber）统一处理。
    static func value(_ dict: [String: Any], _ key: String) -> String? {
        switch dict[key] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func array(_ dict: [String: Any], _ key: String) -> [[String: Any]] {
        dict[key] as? [[String: Any]] ?? []
    }
}

/// system_profiler 编码取值 → 中文映射
enum SPMap {
    static func yesNo(_ s: String?, yes: String = "是", no: String = "否") -> String {
        switch s?.lowercased() {
        case "yes", "spext_yes", "value_yes", "spdisplays_yes", "spaudio_yes", "spairport_caps_supported": return yes
        case "no", "spext_no", "value_no", "spdisplays_off", "spaudio_no", "spairport_caps_unsupported": return no
        case nil: return "不可用"
        default: return s ?? "不可用"
        }
    }

    static func onOff(_ s: String?) -> String {
        switch s?.lowercased() {
        case "attrib_on", "yes", "spext_yes", "value_yes", "spdisplays_yes", "spaudio_yes", "on": return "开启"
        case "attrib_off", "no", "spext_no", "value_no", "spdisplays_off", "spaudio_no", "off": return "关闭"
        case nil: return "不可用"
        default: return s ?? "不可用"
        }
    }

    static func spMetal(_ s: String) -> String {
        switch s {
        case "spdisplays_metal3": return "Metal 3"
        case "spdisplays_metal2": return "Metal 2"
        case "spdisplays_metal": return "Metal"
        default: return s
        }
    }

    static func spAudioTransport(_ s: String) -> String {
        switch s {
        case "coreaudio_device_type_builtin": return "内建"
        case "coreaudio_device_type_usb": return "USB"
        case "coreaudio_device_type_firewire": return "FireWire"
        case "coreaudio_device_type_network": return "网络"
        default: return s
        }
    }

    /// 睡眠计时（分钟）：0 = 从不
    static func timerText(_ minutes: String) -> String {
        if let n = Int(minutes), n == 0 { return "从不" }
        return "\(minutes) 分钟"
    }

    static func securityMode(_ s: String) -> String {
        switch s {
        case "spairport_security_mode_wpa2_personal": return "WPA2 个人"
        case "spairport_security_mode_wpa2_personal_mixed": return "WPA2 个人（混合）"
        case "spairport_security_mode_wpa2_enterprise": return "WPA2 企业"
        case "spairport_security_mode_wpa3_personal": return "WPA3 个人"
        case "spairport_security_mode_wpa3_transition", "pairport_security_mode_wpa3_transition", "spairport_security_mode_wpa3_personal_mixed": return "WPA3 过渡"
        case "spairport_security_mode_wpa2_wpa3_personal": return "WPA2/WPA3 个人"
        case "spairport_security_mode_wpa3_enterprise": return "WPA3 企业"
        case "spairport_security_mode_wpa": return "WPA"
        case "spairport_security_mode_wep": return "WEP"
        case "spairport_security_mode_none": return "无加密"
        case "spairport_security_mode_8021x": return "802.1X"
        default: return s
        }
    }

    static func airportStatus(_ s: String) -> String {
        switch s {
        case "spairport_status_connected": return "已连接"
        case "spairport_status_associating": return "正在关联"
        case "spairport_status_unassociated": return "未关联"
        case "spairport_status_offline": return "离线"
        case "spairport_status_on": return "开启"
        case "spairport_status_off": return "关闭"
        default: return s
        }
    }

    static func firewallState(_ s: String) -> String {
        switch s {
        case "spfirewall_globalstate_allow_all": return "允许所有传入连接"
        case "spfirewall_globalstate_allow_user": return "仅允许用户加入的程序"
        case "spfirewall_globalstate_block_all": return "阻止所有传入连接"
        case "spfirewall_globalstate_block_incoming_only": return "仅阻止未请求的连接"
        default: return s
        }
    }

    static func firewallAllow(_ s: String) -> String {
        switch s {
        case "spfirewall_allow_all": return "允许所有连接"
        case "spfirewall_allow_incoming": return "允许传入连接"
        case "spfirewall_block_incoming": return "阻止传入连接"
        default: return s
        }
    }

    static func prefPaneKind(_ s: String) -> String {
        switch s {
        case "spprefpane_i32_i64": return "32/64 位"
        case "spprefpane_i64": return "64 位"
        case "spprefpane_i32": return "32 位"
        default: return s
        }
    }

    static func prefPaneSupport(_ s: String) -> String {
        switch s {
        case "spprefpane_support_3rdParty": return "第三方"
        case "spprefpane_support_Apple": return "Apple"
        default: return s
        }
    }

    static func packageSource(_ s: String) -> String {
        switch s {
        case "package_source_apple": return "Apple"
        case "package_source_developer": return "开发者"
        case "package_source_other": return "其他"
        case "package_source_app_store": return "App Store"
        default: return s
        }
    }

    static func diagnosticResult(_ s: String) -> String {
        switch s {
        case "spdiags_passed_value": return "通过"
        case "spdiags_failed_value": return "失败"
        default: return s
        }
    }

    static func ethernetBus(_ s: String) -> String {
        switch s {
        case "spethernet_usb_device": return "USB"
        case "spethernet_thunderbolt_device": return "雷电"
        case "spethernet_pcidevice": return "PCI-Express"
        default: return s
        }
    }

    static func ethernetMaxSpeed(_ s: String) -> String {
        switch s {
        case "ethernet_speed_10000": return "10 Gb/s"
        case "ethernet_speed_5000": return "5 Gb/s"
        case "ethernet_speed_2500": return "2.5 Gb/s"
        case "ethernet_speed_1000": return "1 Gb/s"
        case "ethernet_speed_100": return "100 Mb/s"
        case "ethernet_speed_10": return "10 Mb/s"
        default: return s
        }
    }

    static func batteryHealth(_ s: String) -> String {
        switch s {
        case "Good": return "正常"
        case "Fair": return "一般"
        case "Poor": return "差"
        case "Service": return "需维修"
        default: return s
        }
    }

    static func isoDate(_ s: String) -> String {
        guard let date = iso8601.date(from: s) else { return s }
        return chineseFormatter.string(from: date)
    }

    private static let iso8601: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    private static let chineseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
