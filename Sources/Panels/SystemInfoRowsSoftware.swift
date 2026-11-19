import Foundation

/// 系统信息 · 软件组页面 builder（软件 / 扩展 / Framework / 字体 / 安装 / 偏好设置面板 /
/// 启动项 / 语言与地区 / 诊断 / 日志 / 打印机 / 打印机软件 / 辅助功能）
extension SystemInfoPanelViewController {

    /// 软件：SPSoftwareDataType（操作系统概览）
    func softwareRows() -> [InfoRowSpec] {
        guard let entry = SPReader.first("SPSoftwareDataType") else {
            return [.field("软件", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        if let os = SPReader.value(entry, "os_version") {
            rows.append(.field("系统版本", os))
        }
        if let kernel = SPReader.value(entry, "kernel_version") {
            rows.append(.field("内核版本", kernel))
        }
        if let bootMode = SPReader.value(entry, "boot_mode") {
            rows.append(.field("启动模式", bootMode == "normal_boot" ? "正常" : bootMode))
        }
        if let bootVolume = SPReader.value(entry, "boot_volume") {
            rows.append(.field("启动宗卷", bootVolume))
        }
        if let integrity = SPReader.value(entry, "system_integrity") {
            rows.append(.field("系统完整性保护", integrity == "integrity_enabled" ? "已启用" : "未启用"))
        }
        if let secureVM = SPReader.value(entry, "secure_vm") {
            rows.append(.field("安全虚拟内存", secureVM == "secure_vm_enabled" ? "已启用" : "未启用"))
        }
        if let uptime = SPReader.value(entry, "uptime") {
            rows.append(.field("运行时长", uptime.replacingOccurrences(of: "up ", with: "")))
        }
        if let user = SPReader.value(entry, "user_name") {
            rows.append(.field("当前用户", user))
        }
        if let host = SPReader.value(entry, "local_host_name") {
            rows.append(.field("本地主机名", host))
        }
        return rows.isEmpty ? [.field("软件", "不可用")] : rows
    }

    /// 扩展：SPExtensionsDataType（内核扩展/驱动，大列表截断）
    func extensionsRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPExtensionsDataType") else {
            return [.field("扩展", isLoading ? "正在读取…" : "不可用")]
        }
        if entries.isEmpty {
            return [.field("扩展", "未检测到已加载扩展")]
        }
        var rows: [InfoRowSpec] = [.note("共 \(entries.count) 项，仅显示前 \(min(entries.count, infoListCap)) 项")]
        for entry in entries.prefix(infoListCap) {
            rows.append(.subSection(SPReader.value(entry, "_name") ?? "扩展"))
            if let version = SPReader.value(entry, "spext_version") ?? SPReader.value(entry, "Version") {
                rows.append(.field("版本", version))
            }
            if let loaded = SPReader.value(entry, "spext_loaded") {
                rows.append(.field("已加载", loaded == "spext_yes" ? "是" : "否"))
            }
            if let path = SPReader.value(entry, "spext_path") {
                rows.append(.field("位置", path))
            }
        }
        return rows
    }

    /// Framework：SPFrameworksDataType（大列表截断）
    func frameworkRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPFrameworksDataType") else {
            return [.field("Framework", isLoading ? "正在读取…" : "不可用")]
        }
        if entries.isEmpty {
            return [.field("Framework", "未检测到 Framework")]
        }
        var rows: [InfoRowSpec] = [.note("共 \(entries.count) 项，仅显示前 \(min(entries.count, infoListCap)) 项")]
        for entry in entries.prefix(infoListCap) {
            rows.append(.subSection(SPReader.value(entry, "_name") ?? "Framework"))
            if let version = SPReader.value(entry, "version") {
                rows.append(.field("版本", version))
            }
            if let priv = SPReader.value(entry, "private_framework") {
                rows.append(.field("私有", SPMap.yesNo(priv)))
            }
            if let path = SPReader.value(entry, "path") {
                rows.append(.field("位置", path))
            }
        }
        return rows
    }

    /// 字体：SPFontsDataType（按字体系族分组，大列表截断）
    func fontsRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPFontsDataType") else {
            return [.field("字体", isLoading ? "正在读取…" : "不可用（首次加载约 20 秒）")]
        }
        if entries.isEmpty {
            return [.field("字体", "未检测到字体")]
        }
        // 按字体系族分组（保序）
        var families: [String: [String: Any]] = [:]
        var familyOrder: [String] = []
        var totalTypefaces = 0
        for entry in entries {
            let typefaces = SPReader.array(entry, "typefaces")
            let family = typefaces.first.flatMap { SPReader.value($0, "family") }
                ?? SPReader.value(entry, "_name") ?? "未知"
            if families[family] == nil {
                familyOrder.append(family)
            }
            var info = families[family] ?? [String: Any]()
            let count = (info["count"] as? Int) ?? 0
            info["count"] = count + typefaces.count
            if info["path"] == nil, let path = SPReader.value(entry, "path") {
                info["path"] = path
            }
            if info["enabled"] == nil, let enabled = SPReader.value(entry, "enabled") {
                info["enabled"] = enabled
            }
            families[family] = info
            totalTypefaces += max(typefaces.count, 1)
        }
        var rows: [InfoRowSpec] = [.note("共 \(entries.count) 个字体文件（\(totalTypefaces) 个字型），\(familyOrder.count) 个字体系族，仅显示前 \(min(familyOrder.count, infoListCap)) 个体系族")]
        for family in familyOrder.prefix(infoListCap) {
            guard let info = families[family] else { continue }
            rows.append(.subSection(family))
            rows.append(.field("字型数", "\(info["count"] ?? 0)"))
            if let path = info["path"] as? String {
                rows.append(.field("位置", path))
            }
            if let enabled = info["enabled"] as? String {
                rows.append(.field("启用", SPMap.yesNo(enabled)))
            }
        }
        return rows
    }

    /// 安装：SPInstallHistoryDataType（安装历史）
    func installRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPInstallHistoryDataType") else {
            return [.field("安装", isLoading ? "正在读取…" : "不可用")]
        }
        if entries.isEmpty {
            return [.field("安装", "无安装记录")]
        }
        var rows: [InfoRowSpec] = [.note("共 \(entries.count) 条记录，仅显示前 \(min(entries.count, infoListCap)) 条")]
        for entry in entries.prefix(infoListCap) {
            var title = SPReader.value(entry, "_name") ?? "安装项"
            if let version = SPReader.value(entry, "install_version"), !title.contains(version) {
                title += " \(version)"
            }
            rows.append(.subSection(title))
            if let date = SPReader.value(entry, "install_date") {
                rows.append(.field("安装时间", SPMap.isoDate(date)))
            }
            if let source = SPReader.value(entry, "package_source") {
                rows.append(.field("来源", SPMap.packageSource(source)))
            }
        }
        return rows
    }

    /// 偏好设置面板：SPPrefPaneDataType
    func prefPaneRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPPrefPaneDataType") else {
            return [.field("偏好设置面板", isLoading ? "正在读取…" : "不可用")]
        }
        if entries.isEmpty {
            return [.field("偏好设置面板", "未安装第三方偏好设置面板")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries {
            rows.append(.section(SPReader.value(entry, "_name") ?? "偏好设置面板"))
            if let path = SPReader.value(entry, "spprefpane_bundlePath") {
                rows.append(.field("位置", path))
            }
            if let id = SPReader.value(entry, "spprefpane_identifier") {
                rows.append(.field("标识符", id))
            }
            if let visible = SPReader.value(entry, "spprefpane_isVisible") {
                rows.append(.field("可见", SPMap.yesNo(visible)))
            }
            if let kind = SPReader.value(entry, "spprefpane_kind") {
                rows.append(.field("种类", SPMap.prefPaneKind(kind)))
            }
            if let support = SPReader.value(entry, "spprefpane_support") {
                rows.append(.field("支持厂商", SPMap.prefPaneSupport(support)))
            }
            if let version = SPReader.value(entry, "spprefpane_version") {
                rows.append(.field("版本", version))
            }
        }
        return rows
    }

    /// 启动项：SPStartupItemDataType
    func startupItemRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPStartupItemDataType") else {
            return [.field("启动项", isLoading ? "正在读取…" : "不可用")]
        }
        if entries.isEmpty {
            return [.field("启动项", "未检测到启动项")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries {
            rows.append(.section(SPReader.value(entry, "_name") ?? "启动项"))
            if let description = SPReader.value(entry, "Description") {
                rows.append(.field("说明", description))
            }
            if let enabled = SPReader.value(entry, "spstartupitem_enabled") {
                rows.append(.field("启用", SPMap.yesNo(enabled)))
            }
            if let location = SPReader.value(entry, "spstartupitem_location") {
                rows.append(.field("位置", location))
            }
            if let uses = (entry["Uses"] as? [String])?.joined(separator: "、"), !uses.isEmpty {
                rows.append(.field("依赖", uses))
            }
        }
        return rows
    }

    /// 语言与地区：SPInternationalDataType
    func localizationRows() -> [InfoRowSpec] {
        guard SPReader.entries("SPInternationalDataType") != nil else {
            return [.field("语言与地区", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        if let user = SPReader.find("SPInternationalDataType", "user_settings") {
            rows.append(.section("用户设置"))
            if let locale = SPReader.value(user, "user_locale") {
                rows.append(.field("区域设置", locale))
            }
            if let languages = (user["user_preferred_interface_languages"] as? [String])?.joined(separator: "、"), !languages.isEmpty {
                rows.append(.field("首选界面语言", languages))
            }
            if let country = SPReader.value(user, "user_country_code") {
                rows.append(.field("国家/地区", country))
            }
            if let calendar = SPReader.value(user, "user_calendar") {
                var text = calendar == "gregorian" ? "公历" : calendar
                if let overlay = SPReader.value(user, "user_calendar_overlay") {
                    text += "（\(overlay == "chinese" ? "中文历法叠加" : overlay)）"
                }
                rows.append(.field("日历", text))
            }
            if let metric = SPReader.value(user, "user_uses_metric_system") {
                rows.append(.field("度量衡制", metric == "value_yes" ? "米制" : "英制"))
            }
            if let input = SPReader.value(user, "user_current_input_source") {
                rows.append(.field("当前输入法", input))
            }
            if let assistant = SPReader.value(user, "user_assistant_language") {
                rows.append(.field("助手语言", assistant))
            }
        }
        if let system = SPReader.find("SPInternationalDataType", "system_settings") {
            rows.append(.section("系统设置"))
            if let country = SPReader.value(system, "system_country") {
                rows.append(.field("国家/地区", country))
            }
            let languages = (system["system_interface_languages"] as? [String] ?? []).joined(separator: "、")
            if !languages.isEmpty {
                rows.append(.field("界面语言", languages))
            }
        }
        if rows.isEmpty {
            rows.append(.field("语言与地区", "不可用"))
        }
        return rows
    }

    /// 诊断：SPDiagnosticsDataType（POST / Apple 诊断）
    func diagnosticsRows() -> [InfoRowSpec] {
        guard SPReader.entries("SPDiagnosticsDataType") != nil else {
            return [.field("诊断", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        if let post = SPReader.find("SPDiagnosticsDataType", "spdiags_post_value") {
            rows.append(.section("开机自检（POST）"))
            if let run = SPReader.value(post, "spdiags_last_run_key") {
                rows.append(.field("上次运行", SPMap.isoDate(run)))
            }
            if let result = SPReader.value(post, "spdiags_result_key") {
                rows.append(.field("结果", SPMap.diagnosticResult(result)))
            }
        }
        if let aht = SPReader.find("SPDiagnosticsDataType", "spdiags_aht_value") {
            rows.append(.section("Apple 诊断工具"))
            if let run = SPReader.value(aht, "spdiags_last_run_key") {
                rows.append(.field("上次运行", SPMap.isoDate(run)))
            }
            if let version = SPReader.value(aht, "spdiags_version_key") {
                rows.append(.field("版本", version))
            }
            if let code = SPReader.value(aht, "spdiags_reference_code_key") {
                rows.append(.field("参考代码", code))
            }
        }
        if rows.isEmpty {
            rows.append(.field("诊断", "无诊断记录"))
        }
        return rows
    }

    /// 日志：SPLogsDataType（系统日志文件摘要）
    func logsRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPLogsDataType") else {
            return [.field("日志", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries {
            let rawName = SPReader.value(entry, "_name") ?? "日志"
            let name = rawName.replacingOccurrences(of: "_description", with: "")
            rows.append(.subSection(name))
            if let source = SPReader.value(entry, "source") {
                rows.append(.field("来源", source))
            }
            if let size = entry["byteSize"] as? NSNumber {
                rows.append(.field("大小", Self.byteSizeText(size.uint64Value)))
            }
            if let modified = SPReader.value(entry, "lastModified") {
                rows.append(.field("最后修改", modified))
            }
            if let contents = SPReader.value(entry, "contents") {
                let lastLine = contents.split(separator: "\n").last.map(String.init) ?? contents
                if lastLine.hasPrefix("...") {
                    // 取最后一条实际日志
                    let lines = contents.split(separator: "\n")
                    if lines.count > 1, let last = lines.last {
                        rows.append(.field("末尾", String(last)))
                    }
                } else if !lastLine.isEmpty {
                    rows.append(.field("末尾", lastLine))
                }
            }
        }
        if rows.isEmpty {
            rows.append(.field("日志", "不可用"))
        }
        return rows
    }

    /// 打印机：SPPrintersDataType
    func printersRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPPrintersDataType") else {
            return [.field("打印机", isLoading ? "正在读取…" : "不可用")]
        }
        if entries.isEmpty {
            return [.field("打印机", "未检测到打印机")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries {
            rows.append(.section(SPReader.value(entry, "_name") ?? "打印机"))
            if let status = SPReader.value(entry, "status") {
                rows.append(.field("状态", status == "idle" ? "空闲" : (status == "offline" ? "离线" : status)))
            }
            if let defaultFlag = SPReader.value(entry, "default") {
                rows.append(.field("默认打印机", SPMap.yesNo(defaultFlag)))
            }
            if let ppd = SPReader.value(entry, "ppd") {
                rows.append(.field("驱动程序", ppd))
            }
            if let version = SPReader.value(entry, "driverversion") {
                rows.append(.field("驱动版本", version))
            }
            if let uri = SPReader.value(entry, "uri") {
                rows.append(.field("URI", uri))
            }
            if let scanner = SPReader.value(entry, "scanner") {
                rows.append(.field("扫描仪", SPMap.yesNo(scanner)))
            }
            if let sharing = SPReader.value(entry, "printersharing") {
                rows.append(.field("共享", SPMap.yesNo(sharing)))
            }
        }
        return rows
    }

    /// 打印机软件：SPPrintersSoftwareDataType（PPD/图像捕捉支持）
    func printerSoftwareRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPPrintersSoftwareDataType") else {
            return [.field("打印机软件", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries {
            let rawName = SPReader.value(entry, "_name") ?? "打印机软件"
            switch rawName {
            case "ppds":
                let ppds = SPReader.array(entry, "ppds")
                rows.append(.section("PPD 驱动"))
                if ppds.isEmpty {
                    rows.append(.field("状态", "未安装 PPD"))
                } else {
                    for ppd in ppds {
                        rows.append(.subSection(SPReader.value(ppd, "_name") ?? "PPD"))
                    }
                }
            case "image capture support":
                let items = SPReader.array(entry, "image capture support")
                rows.append(.section("图像捕捉支持"))
                if items.isEmpty {
                    rows.append(.field("状态", "不可用"))
                } else {
                    for item in items {
                        if let path = SPReader.value(item, "info path") {
                            rows.append(.field("路径", path))
                        }
                        if let version = SPReader.value(item, "info version") {
                            rows.append(.field("版本", version))
                        }
                    }
                }
            default:
                break
            }
        }
        if rows.isEmpty {
            rows.append(.field("打印机软件", "未检测到打印机软件"))
        }
        return rows
    }

    /// 辅助功能：SPUniversalAccessDataType
    func accessibilityRows() -> [InfoRowSpec] {
        guard let entry = SPReader.first("SPUniversalAccessDataType") else {
            return [.field("辅助功能", isLoading ? "正在读取…" : "不可用")]
        }
        let onOff: [(String, String)] = [
            ("voiceover", "VoiceOver"),
            ("mouse_keys", "鼠标键"),
            ("slow_keys", "慢速键"),
            ("sticky_keys", "粘滞键"),
            ("flash_screen", "屏幕闪烁"),
            ("keyboardZoom", "键盘缩放"),
            ("scrollZoom", "滚动缩放"),
        ]
        var rows: [InfoRowSpec] = []
        for (field, label) in onOff {
            if let value = SPReader.value(entry, field) {
                rows.append(.field(label, SPMap.onOff(value)))
            }
        }
        if let zoom = SPReader.value(entry, "zoomMode") {
            rows.append(.field("缩放模式", zoom == "zoom_full_screen" ? "全屏" : (zoom == "off" ? "关闭" : zoom)))
        }
        if let display = SPReader.value(entry, "display") {
            rows.append(.field("显示", display == "black_on_white" ? "黑底白字" : display == "white_on_black" ? "白底黑字" : "默认"))
        }
        if let cursorMag = SPReader.value(entry, "cursor_mag") {
            rows.append(.field("指针放大", SPMap.onOff(cursorMag)))
        }
        if let contrast = SPReader.value(entry, "contrast"), !contrast.isEmpty, contrast != "0" {
            rows.append(.field("对比度", contrast))
        }
        return rows.isEmpty ? [.field("辅助功能", "无已启用项")] : rows
    }

    // MARK: - 辅助

    static func byteSizeText(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.2f GB", Double(bytes) / 1_073_741_824.0)
        }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        }
        if bytes >= 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024.0)
        }
        return "\(bytes) B"
    }
}
