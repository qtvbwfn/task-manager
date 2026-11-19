import AppKit
import Darwin
import IOKit

// MARK: - 分类

private enum InfoCategory: Int, CaseIterable {
    case overview, processor, memory, graphics, storage, battery, network, software

    var title: String {
        switch self {
        case .overview: return "概述"
        case .processor: return "处理器"
        case .memory: return "内存"
        case .graphics: return "图形卡"
        case .storage: return "存储"
        case .battery: return "电池"
        case .network: return "网络"
        case .software: return "软件"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "desktopcomputer"
        case .processor: return "cpu"
        case .memory: return "memorychip"
        case .graphics: return "display"
        case .storage: return "internaldrive"
        case .battery: return "battery.75"
        case .network: return "network"
        case .software: return "gearshape"
        }
    }

    /// 左侧列表分组：0 硬件 / 1 网络 / 2 软件
    var group: Int {
        switch self {
        case .overview, .processor, .memory, .graphics, .storage, .battery: return 0
        case .network: return 1
        case .software: return 2
        }
    }
}

private let infoGroupTitles = ["硬件", "网络", "软件"]

private enum InfoRowSpec {
    case field(String, String)
    case section(String)
}

private struct SystemDiskInfo {
    let bsdName: String
    let model: String
    let size: UInt64
    let used: UInt64
    let available: UInt64
    let medium: String
    let interconnect: String
}

private struct NetworkInterfaceInfo {
    let name: String
    let ipv4: String?
    let ipv6: String?
    let mac: String?
    let isUp: Bool
    let isRunning: Bool
}

private struct LoadedSystemInfo {
    let serialNumber: String
    let hardwareUUID: String
    let firmwareVersion: String
    let osLoaderVersion: String
    let activationLock: String
    let osBuild: String
    let gpuVRAMMB: Int?
    let interfaces: [NetworkInterfaceInfo]
    let disks: [SystemDiskInfo]
    let system: SystemSnapshot
    let iokit: IOKitSample
    let network: NetworkSampler.Sample
}

private struct HardwareExtras {
    var firmwareVersion = ""
    var osLoaderVersion = ""
    var activationLock = ""
}

// MARK: - 面板

final class SystemInfoPanelViewController: PanelBaseViewController {
    private let categoryStack = NSStackView()
    private var categoryRows: [InfoCategoryRowView] = []

    private let detailCard = NSView()
    private let headerIcon = NSImageView()
    private let categoryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let reloadButton = NSButton(title: "重新载入", target: nil, action: nil)
    private let headerSeparator = NSView()

    private let rowsStack = NSStackView()
    private var rowsScroll: NSScrollView!

    private var selectedCategory: InfoCategory = .overview
    private var activeSpecs: [InfoRowSpec] = []
    private var isLoading = false

    private var serialNumber = ""
    private var hardwareUUID = ""
    private var firmwareVersion = ""
    private var osLoaderVersion = ""
    private var activationLock = ""
    private var osBuild = ""
    private var gpuVRAMMB: Int?
    private var interfaces: [NetworkInterfaceInfo] = []
    private var disks: [SystemDiskInfo] = []
    private var systemInfo: SystemSnapshot?
    private var iokit: IOKitSample?
    private var networkSample: NetworkSampler.Sample?

    init() { super.init(title: "系统信息") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        select(.overview)
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    override func applyTheme() {
        super.applyTheme()
        let theme = Theme.shared
        detailCard.layer?.backgroundColor = theme.cardBackground.cgColor
        detailCard.layer?.borderColor = theme.separator.withAlphaComponent(0.6).cgColor
        headerSeparator.layer?.backgroundColor = theme.separator.withAlphaComponent(0.7).cgColor
        categoryRows.forEach { $0.applyTheme() }
        (categoryStack.arrangedSubviews.compactMap { $0 as? InfoGroupHeaderView }).forEach { $0.applyTheme() }
        rowsStack.arrangedSubviews.forEach { ($0 as? ThemeAware)?.applyTheme() }
        headerIcon.contentTintColor = theme.textSecondary
    }

    // MARK: - 布局

    private func buildLayout() {
        buildCategoryPane()
        buildDetailCard()
    }

    private func buildCategoryPane() {
        categoryStack.orientation = .vertical
        categoryStack.alignment = .width
        categoryStack.spacing = 1
        categoryStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 12, right: 0)

        var lastGroup = -1
        for category in InfoCategory.allCases {
            if category.group != lastGroup {
                if let previous = categoryStack.arrangedSubviews.last {
                    categoryStack.setCustomSpacing(10, after: previous)
                }
                categoryStack.addArrangedSubview(InfoGroupHeaderView(title: infoGroupTitles[category.group]))
                lastGroup = category.group
            }
            let row = InfoCategoryRowView(category: category)
            row.onClick = { [weak self] in self?.select(category) }
            categoryRows.append(row)
            categoryStack.addArrangedSubview(row)
        }

        let scroll = Self.makeScrolledStack(categoryStack)
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            scroll.widthAnchor.constraint(equalToConstant: 168),
        ])
        categoryScrollView = scroll
    }

    private weak var categoryScrollView: NSScrollView?

    private func buildDetailCard() {
        detailCard.wantsLayer = true
        detailCard.layer?.cornerRadius = 8
        detailCard.layer?.borderWidth = 1
        detailCard.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(detailCard)

        headerIcon.imageScaling = .scaleProportionallyDown
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(headerIcon)

        categoryPopup.font = .systemFont(ofSize: 13)
        categoryPopup.isBordered = false
        categoryPopup.focusRingType = .none
        categoryPopup.addItems(withTitles: InfoCategory.allCases.map(\.title))
        categoryPopup.target = self
        categoryPopup.action = #selector(categoryPopupChanged)
        categoryPopup.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(categoryPopup)

        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.font = .systemFont(ofSize: 12)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(copyButton)

        reloadButton.target = self
        reloadButton.action = #selector(reloadTapped)
        reloadButton.bezelStyle = .rounded
        reloadButton.controlSize = .small
        reloadButton.font = .systemFont(ofSize: 12)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(reloadButton)

        headerSeparator.wantsLayer = true
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(headerSeparator)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 0
        rowsStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 10, right: 0)
        let scroll = Self.makeScrolledStack(rowsStack)
        detailCard.addSubview(scroll)
        rowsScroll = scroll

        NSLayoutConstraint.activate([
            detailCard.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            detailCard.leadingAnchor.constraint(equalTo: categoryScrollView!.trailingAnchor, constant: 10),
            detailCard.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            detailCard.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            headerIcon.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor, constant: 12),
            headerIcon.centerYAnchor.constraint(equalTo: categoryPopup.centerYAnchor),
            headerIcon.widthAnchor.constraint(equalToConstant: 15),
            headerIcon.heightAnchor.constraint(equalToConstant: 15),

            categoryPopup.topAnchor.constraint(equalTo: detailCard.topAnchor, constant: 6),
            categoryPopup.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 6),

            copyButton.centerYAnchor.constraint(equalTo: categoryPopup.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor, constant: -10),

            reloadButton.centerYAnchor.constraint(equalTo: categoryPopup.centerYAnchor),
            reloadButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -6),
            categoryPopup.trailingAnchor.constraint(lessThanOrEqualTo: reloadButton.leadingAnchor, constant: -8),

            headerSeparator.topAnchor.constraint(equalTo: categoryPopup.bottomAnchor, constant: 6),
            headerSeparator.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: detailCard.bottomAnchor),
        ])
    }

    private static func makeScrolledStack(_ stack: NSStackView) -> NSScrollView {
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = InfoScrollDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    // MARK: - 选择 / 刷新

    @objc private func categoryPopupChanged() {
        let index = categoryPopup.indexOfSelectedItem
        guard index >= 0, index < InfoCategory.allCases.count else { return }
        select(InfoCategory.allCases[index])
    }

    private func select(_ category: InfoCategory) {
        selectedCategory = category
        categoryPopup.selectItem(at: category.rawValue)
        headerIcon.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.title)
        categoryRows.forEach { $0.setSelected($0.category == category) }
        rebuildRows()
    }

    @objc private func reloadTapped() {
        refresh()
    }

    @objc private func copyTapped() {
        var lines: [String] = []
        for spec in activeSpecs {
            switch spec {
            case .field(let key, let value):
                lines.append("\(key): \(value)")
            case .section(let title):
                if !lines.isEmpty { lines.append("") }
                lines.append("[\(title)]")
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func refresh() {
        guard !isLoading else { return }
        isLoading = true
        reloadButton.isEnabled = false
        rebuildRows()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            let serialNumber = Self.platformString("IOPlatformSerialNumber")
            let hardwareUUID = Self.platformString("IOPlatformUUID")
            let extras = Self.cachedHardwareExtras
            let osBuild = StaticInfo.sysctlString("kern.osversion")
            let gpuVRAMMB = Self.loadGPUVram()
            let interfaces = Self.loadNetworkInterfaces()
            let disks = Self.loadDisks()
            let system = SystemSampler().sample()

            // IOKit 磁盘速率 / 网络速率都需要两次采样求差
            let iokitSampler = IOKitSampler()
            let networkSampler = NetworkSampler()
            _ = iokitSampler.sample()
            _ = networkSampler.sample()
            usleep(350_000)
            let loaded = LoadedSystemInfo(
                serialNumber: serialNumber,
                hardwareUUID: hardwareUUID,
                firmwareVersion: extras.firmwareVersion,
                osLoaderVersion: extras.osLoaderVersion,
                activationLock: extras.activationLock,
                osBuild: osBuild,
                gpuVRAMMB: gpuVRAMMB,
                interfaces: interfaces,
                disks: disks,
                system: system,
                iokit: iokitSampler.sample(),
                network: networkSampler.sample()
            )

            DispatchQueue.main.async {
                guard let self else { return }
                self.serialNumber = loaded.serialNumber
                self.hardwareUUID = loaded.hardwareUUID
                self.firmwareVersion = loaded.firmwareVersion
                self.osLoaderVersion = loaded.osLoaderVersion
                self.activationLock = loaded.activationLock
                self.osBuild = loaded.osBuild
                self.gpuVRAMMB = loaded.gpuVRAMMB
                self.interfaces = loaded.interfaces
                self.disks = loaded.disks
                self.systemInfo = loaded.system
                self.iokit = loaded.iokit
                self.networkSample = loaded.network
                self.isLoading = false
                self.reloadButton.isEnabled = true
                self.rebuildRows()
            }
        }
    }

    // MARK: - 行构建

    private func rebuildRows() {
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        activeSpecs = buildRows(for: selectedCategory)
        for spec in activeSpecs {
            switch spec {
            case .field(let key, let value):
                rowsStack.addArrangedSubview(InfoPropertyRowView(key: key, value: value))
            case .section(let title):
                rowsStack.addArrangedSubview(InfoSectionRowView(title: title))
            }
        }
        rowsStack.layoutSubtreeIfNeeded()
        rowsScroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        rowsScroll.reflectScrolledClipView(rowsScroll.contentView)
        applyTheme()
    }

    private func buildRows(for category: InfoCategory) -> [InfoRowSpec] {
        switch category {
        case .overview: return overviewRows()
        case .processor: return processorRows()
        case .memory: return memoryRows()
        case .graphics: return graphicsRows()
        case .storage: return storageRows()
        case .battery: return batteryRows()
        case .network: return networkRows()
        case .software: return softwareRows()
        }
    }

    private func overviewRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = [
            .field("型号名称", Self.familyName),
            .field("型号标识符", StaticInfo.model),
            .field("处理器名称", StaticInfo.cpuBrand),
            .field("处理器速度", StaticInfo.frequency(StaticInfo.baseFrequency)),
            .field("核心总数", "\(StaticInfo.logicalCores)（\(StaticInfo.physicalCores) 物理核心）"),
            .field("内存", Formats.memory(StaticInfo.memorySize)),
            .field("序列号", pending(serialNumber)),
            .field("硬件 UUID", pending(hardwareUUID)),
            .field("激活锁状态", pending(activationLock)),
            .field("系统版本", StaticInfo.osVersion),
            .field("系统固件版本", pending(firmwareVersion)),
            .field("操作系统加载程序版本", pending(osLoaderVersion)),
            .field("主机名", StaticInfo.hostName),
        ]
        if let systemInfo {
            rows.append(.field("运行时长", Formats.uptime(systemInfo.uptime)))
        } else if isLoading {
            rows.append(.field("运行时长", "正在读取…"))
        }
        return rows
    }

    private func processorRows() -> [InfoRowSpec] {
        let logical = StaticInfo.logicalCores
        let physical = StaticInfo.physicalCores
        var rows: [InfoRowSpec] = [
            .field("处理器名称", StaticInfo.cpuBrand),
            .field("处理器架构", StaticInfo.machine),
            .field("处理器数目", "\(StaticInfo.sysctlInt("hw.packages"))"),
            .field("物理核心", "\(physical)"),
            .field("逻辑核心", "\(logical)"),
            .field("超线程技术", logical > physical ? "已启用" : "不可用"),
            .field("处理器速度", StaticInfo.frequency(StaticInfo.baseFrequency)),
            .field("L2 缓存", StaticInfo.cacheSize(StaticInfo.l2Cache)),
            .field("L3 缓存", StaticInfo.cacheSize(StaticInfo.l3Cache)),
            .field("64 位支持", StaticInfo.sysctlInt("hw.cpu64bit_capable") != 0 ? "是" : "否"),
            .field("虚拟化支持", StaticInfo.sysctlInt("kern.hv_support") != 0 ? "是" : "否"),
        ]
        if let systemInfo {
            rows.append(.field("当前利用率", Formats.percent(systemInfo.cpuTotal)))
            rows.append(.field("内核占用", Formats.percent(systemInfo.kernelPercent)))
        } else if isLoading {
            rows.append(.field("当前利用率", "正在读取…"))
        }
        return rows
    }

    private func memoryRows() -> [InfoRowSpec] {
        guard let systemInfo else {
            return [.field("状态", isLoading ? "正在读取…" : "不可用")]
        }
        let total = systemInfo.memoryTotal
        let used = systemInfo.memoryUsed
        let percent = total > 0 ? Double(used) / Double(total) * 100.0 : 0
        return [
            .field("物理内存总量", Formats.memory(total)),
            .field("已使用", "\(Formats.memory(used))（\(Formats.percent(percent))）"),
            .field("可用", Formats.memory(systemInfo.memoryAvailable)),
            .field("缓存文件", Formats.memory(systemInfo.memoryCached)),
            .field("已压缩", Formats.memory(systemInfo.memoryCompressed)),
            .field("常驻内存", Formats.memory(systemInfo.memoryWired)),
            .field("交换空间已用", Formats.memory(systemInfo.swapUsed)),
            .field("交换空间总量", Formats.memory(systemInfo.swapTotal)),
            .field("内存压力", Self.pressureName(systemInfo.memoryPressure)),
            .field("换入 / 换出", "\(Self.grouped(systemInfo.pageIns)) / \(Self.grouped(systemInfo.pageOuts))"),
            .field("页面大小", Self.cacheLikeSize(StaticInfo.sysctlInt("hw.pagesize"))),
        ]
    }

    private func graphicsRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = [.field("图形处理器", IOKitSampler.gpuModel)]
        if let gpuVRAMMB {
            rows.append(.field("显存", "\(gpuVRAMMB) MB"))
        }
        if let iokit {
            rows.append(.field("当前利用率", iokit.gpuUtilization.map { Formats.percent($0) } ?? "不可用"))
        } else if isLoading {
            rows.append(.field("当前利用率", "正在读取…"))
        }
        let screens = NSScreen.screens
        rows.append(.field("显示器数量", "\(screens.count)"))
        if let main = screens.first {
            let scale = main.backingScaleFactor
            let width = Int(main.frame.width * scale)
            let height = Int(main.frame.height * scale)
            rows.append(.field("主显示器", main.localizedName))
            rows.append(.field("主显示器分辨率", "\(width) × \(height)（\(Int(scale))x）"))
            if let hz = screens.map(\.maximumFramesPerSecond).max(), hz > 0 {
                rows.append(.field("最大刷新率", "\(hz) Hz"))
            }
        }
        return rows
    }

    private func storageRows() -> [InfoRowSpec] {
        guard !disks.isEmpty else {
            return [.field("状态", isLoading ? "正在读取…" : "未检测到物理磁盘")]
        }
        var rows: [InfoRowSpec] = []
        for (index, disk) in disks.enumerated() {
            if index > 0 { rows.append(.section("")) }
            let header = disk.bsdName == "未知" ? disk.model : "\(disk.bsdName) · \(disk.model)"
            rows.append(.section(header))
            rows.append(.field("型号", disk.model))
            rows.append(.field("介质类型", disk.medium))
            rows.append(.field("总线", disk.interconnect))
            rows.append(.field("容量", Formats.memory(disk.size)))
            if disk.size > 0, disk.used > 0 {
                let percent = Double(disk.used) / Double(disk.size) * 100.0
                rows.append(.field("已使用", "\(Formats.memory(disk.used))（\(Formats.percent(percent))）"))
            } else {
                rows.append(.field("已使用", "不可用"))
            }
            rows.append(.field("可用", disk.available > 0 ? Formats.memory(disk.available) : "不可用"))
            if let iokit, let rate = iokit.perDisk[disk.bsdName] {
                rows.append(.field("读取速率", Formats.rate(rate.readPerSecond)))
                rows.append(.field("写入速率", Formats.rate(rate.writePerSecond)))
            }
        }
        return rows
    }

    private func batteryRows() -> [InfoRowSpec] {
        guard let iokit else {
            return [.field("状态", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        if iokit.hasBattery {
            rows.append(.field("当前电量", iokit.batteryPercent.map { "\($0)%" } ?? "不可用"))
            rows.append(.field("充电状态", iokit.isCharging ? "充电中" : "未充电"))
            rows.append(.field("电源来源", iokit.powerSource))
            rows.append(.field("实时功耗", iokit.watts.map { String(format: "%.1f W", $0) } ?? "不可用"))
            rows.append(.field("适配器", iokit.adapterWatts.map { "\($0) W" } ?? "不可用"))
            rows.append(.field("循环次数", iokit.cycleCount.map { "\($0)" } ?? "不可用"))
            rows.append(.field("健康度", iokit.batteryHealthPercent.map { String(format: "%.1f%%", $0) } ?? "不可用"))
        } else {
            rows.append(.field("电池", "未检测到电池"))
            rows.append(.field("电源来源", iokit.powerSource))
            rows.append(.field("适配器", iokit.adapterWatts.map { "\($0) W" } ?? "不可用"))
            rows.append(.field("实时功耗", iokit.watts.map { String(format: "%.1f W", $0) } ?? "不可用"))
        }
        return rows
    }

    private func networkRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = [
            .field("主机名", StaticInfo.hostName),
        ]
        if let primary = interfaces.first(where: { $0.ipv4 != nil }), let ipv4 = primary.ipv4 {
            rows.append(.field("主 IP 地址", ipv4))
        }
        if let networkSample {
            rows.append(.field("网络接口数", "\(networkSample.interfaces)"))
            rows.append(.field("下行速率", Formats.rate(networkSample.bytesInPerSecond)))
            rows.append(.field("上行速率", Formats.rate(networkSample.bytesOutPerSecond)))
            rows.append(.field("累计接收", Formats.memory(networkSample.totalBytesIn)))
            rows.append(.field("累计发送", Formats.memory(networkSample.totalBytesOut)))
        } else if isLoading {
            rows.append(.field("网络接口数", "正在读取…"))
        }

        for interface in interfaces {
            rows.append(.section(interface.name))
            let hasRoutableAddress = interface.ipv4 != nil || (interface.ipv6.map { !$0.hasPrefix("fe80") } ?? false)
            let status: String
            if interface.isRunning && hasRoutableAddress {
                status = "已连接"
            } else if interface.isUp {
                status = "已启用"
            } else {
                status = "未启用"
            }
            rows.append(.field("状态", status))
            rows.append(.field("IPv4 地址", interface.ipv4 ?? "不可用"))
            rows.append(.field("IPv6 地址", interface.ipv6 ?? "不可用"))
            rows.append(.field("MAC 地址", interface.mac ?? "不可用"))
        }
        if interfaces.isEmpty && !isLoading {
            rows.append(.field("网络接口", "未检测到活动接口"))
        }
        return rows
    }

    private func softwareRows() -> [InfoRowSpec] {
        [
            .field("macOS 版本", StaticInfo.osVersion),
            .field("构建版本", pending(osBuild)),
            .field("内核版本", "Darwin \(StaticInfo.sysctlString("kern.osrelease"))"),
            .field("系统固件版本", pending(firmwareVersion)),
            .field("操作系统加载程序版本", pending(osLoaderVersion)),
            .field("主机名", StaticInfo.hostName),
            .field("架构", StaticInfo.machine),
            .field("启动时间", Formats.date(StaticInfo.bootDate)),
            .field("运行时长", Formats.uptime(Foundation.ProcessInfo.processInfo.systemUptime)),
            .field("当前用户", NSUserName()),
            .field("系统语言", Locale.current.identifier),
            .field("时区", TimeZone.current.identifier),
        ]
    }

    private func pending(_ value: String) -> String {
        value.isEmpty ? (isLoading ? "正在读取…" : "不可用") : value
    }

    // MARK: - 静态信息读取

    private static var familyName: String {
        let model = StaticInfo.model
        if model.hasPrefix("MacBookPro") { return "MacBook Pro" }
        if model.hasPrefix("MacBookAir") { return "MacBook Air" }
        if model.hasPrefix("MacBook") { return "MacBook" }
        if model.hasPrefix("Macmini") { return "Mac mini" }
        if model.hasPrefix("MacPro") { return "Mac Pro" }
        if model.hasPrefix("iMacPro") { return "iMac Pro" }
        if model.hasPrefix("iMac") { return "iMac" }
        if model.hasPrefix("Mac") { return "Mac" }
        return "不可用"
    }

    private static let groupingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private static func grouped(_ value: UInt64) -> String {
        groupingFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func pressureName(_ level: Int32) -> String {
        switch level {
        case 1: return "正常"
        case 2: return "警告"
        case 4: return "严重"
        default: return "不可用"
        }
    }

    private static func cacheLikeSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "不可用" }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024.0)
    }

    private static let cachedHardwareExtras = loadHardwareExtras()

    /// 固件版本 / 启动器版本 / 激活锁只能经 system_profiler 读取（公开 sysctl 与 IORegistry 未暴露）。
    /// 仅在打开系统信息页时调用一次，耗时约 0.2s。
    private static func loadHardwareExtras() -> HardwareExtras {
        var extras = HardwareExtras()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return extras
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["SPHardwareDataType"] as? [[String: Any]],
              let info = rows.first else {
            return extras
        }
        extras.firmwareVersion = info["boot_rom_version"] as? String ?? ""
        extras.osLoaderVersion = info["os_loader_version"] as? String ?? ""
        switch info["activation_lock_status"] as? String {
        case "activation_lock_enabled": extras.activationLock = "已启用"
        case "activation_lock_disabled": extras.activationLock = "未启用"
        default: extras.activationLock = ""
        }
        return extras
    }

    private static func platformString(_ key: String) -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "" }
        defer { IOObjectRelease(service) }
        guard let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return ""
        }
        let value = unmanaged.takeRetainedValue()
        if let string = value as? String {
            return string.trimmingCharacters(in: .controlCharacters)
        }
        if let data = value as? Data {
            return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .controlCharacters)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private static func loadGPUVram() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            guard let unmanaged = IORegistryEntryCreateCFProperty(entry, "VRAM,totalMB" as CFString, kCFAllocatorDefault, 0) else {
                continue
            }
            let value = unmanaged.takeRetainedValue()
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let data = value as? Data, data.count >= 4 {
                var raw: UInt32 = 0
                _ = withUnsafeMutableBytes(of: &raw) { destination in
                    data.copyBytes(to: destination, count: 4)
                }
                return Int(raw)
            }
        }
        return nil
    }

    // MARK: - 磁盘

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

    private static func loadDisks() -> [SystemDiskInfo] {
        var results: [SystemDiskInfo] = []
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
                  let model = characteristics["Product Name"] as? String else { continue }

            var bsdName = "未知"
            var size: UInt64 = 0
            if let media = Self.mediaEntry(of: entry) {
                defer { IOObjectRelease(media) }
                if let value = property("BSD Name", of: media) as? String {
                    bsdName = value
                }
                if let number = property("Size", of: media) as? NSNumber {
                    size = number.uint64Value
                }
            }

            let mediumRaw = characteristics["Medium Type"] as? String
            let medium: String
            switch mediumRaw {
            case "Solid State": medium = "固态硬盘"
            case "Rotational": medium = "机械硬盘"
            case "Optical": medium = "光盘"
            default: medium = mediumRaw ?? "不可用"
            }
            let protocolCharacteristics = property("Protocol Characteristics", of: entry) as? [String: Any]
            let interconnect = (protocolCharacteristics?["Physical Interconnect"] as? String) ?? "不可用"

            var used: UInt64 = 0
            var available: UInt64 = 0
            if let volumes = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey],
                options: [.skipHiddenVolumes]
            ) {
                for volume in volumes {
                    guard let values = try? volume.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
                          let total = values.volumeTotalCapacity,
                          let free = values.volumeAvailableCapacity, total > 0 else { continue }
                    if size > 0, abs(Int64(total) - Int64(size)) < Int64(size / 10) {
                        used += UInt64(total - free)
                        available += UInt64(free)
                        break
                    }
                }
            }

            results.append(SystemDiskInfo(
                bsdName: bsdName,
                model: model,
                size: size,
                used: used,
                available: available,
                medium: medium,
                interconnect: interconnect
            ))
        }
        return results
    }

    // MARK: - 网络接口

    private static func loadNetworkInterfaces() -> [NetworkInterfaceInfo] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        struct Accumulator {
            var ipv4: String?
            var ipv6: String?
            var mac: String?
            var flags: Int32 = 0
        }
        var table: [String: Accumulator] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip"), let address = current.pointee.ifa_addr else { continue }

            var entry = table[name] ?? Accumulator()
            entry.flags = Int32(bitPattern: current.pointee.ifa_flags)

            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                entry.ipv4 = hostString(address, length: socklen_t(address.pointee.sa_len))
            case AF_INET6:
                let value = hostString(address, length: socklen_t(address.pointee.sa_len))
                if let value, !value.hasPrefix("fe80") || entry.ipv6 == nil {
                    entry.ipv6 = value
                }
            case AF_LINK:
                if entry.mac == nil {
                    entry.mac = macString(address)
                }
            default:
                break
            }
            table[name] = entry
        }

        let list = table.keys.sorted().compactMap { name -> NetworkInterfaceInfo? in
            guard let entry = table[name] else { return nil }
            return NetworkInterfaceInfo(
                name: name,
                ipv4: entry.ipv4,
                ipv6: entry.ipv6,
                mac: entry.mac,
                isUp: (entry.flags & IFF_UP) != 0,
                isRunning: (entry.flags & IFF_RUNNING) != 0
            )
        }
        // 未分配地址的 en* 接口是雷雳/扩展坞的空端口，全部列出只会淹没真正在用的接口。
        let active = list.filter { interface in
            if interface.ipv4 != nil { return true }
            guard let ipv6 = interface.ipv6 else { return false }
            return !ipv6.hasPrefix("fe80")
        }
        return active.isEmpty ? Array(list.prefix(1)) : active
    }

    private static func hostString(_ address: UnsafeMutablePointer<sockaddr>, length: socklen_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }

    private static func macString(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        let link = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_dl.self).pointee
        let count = Int(link.sdl_alen)
        guard count > 0 else { return nil }
        let offset = (MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) ?? 8) + Int(link.sdl_nlen)
        let raw = UnsafeRawPointer(address).advanced(by: offset)
        let bytes = (0..<count).map { String(format: "%02x", raw.load(fromByteOffset: $0, as: UInt8.self)) }
        return bytes.joined(separator: ":")
    }
}

// MARK: - 左栏

private final class InfoCategoryRowView: NSView {
    let category: InfoCategory
    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var selected = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(category: InfoCategory) {
        self.category = category
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.title)
        addSubview(iconView)

        label.stringValue = category.title
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        refreshBackground()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        refreshBackground()
    }

    func applyTheme() {
        refreshBackground()
    }

    private func refreshBackground() {
        let theme = Theme.shared
        layer?.cornerRadius = 6
        layer?.backgroundColor = (selected ? theme.sidebarSelectionBg : (hovered ? theme.sidebarHoverBg : .clear)).cgColor
        let color = selected ? theme.sidebarSelectionText : theme.textPrimary
        label.textColor = color
        label.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        iconView.contentTintColor = color
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: selected ? .semibold : .regular)
    }
}

private final class InfoGroupHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true

        label.stringValue = title
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyTheme() {
        label.textColor = Theme.shared.textSecondary
    }
}

// MARK: - 右栏行

private final class InfoPropertyRowView: NSView, ThemeAware {
    private let keyLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let separator = NSView()

    init(key: String, value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        keyLabel.stringValue = key
        keyLabel.font = .systemFont(ofSize: 13)
        keyLabel.lineBreakMode = .byTruncatingTail
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyLabel)

        valueLabel.stringValue = value
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.isSelectable = true
        valueLabel.toolTip = value
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        separator.wantsLayer = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyLabel.widthAnchor.constraint(equalToConstant: 164),

            valueLabel.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyTheme() {
        let theme = Theme.shared
        keyLabel.textColor = theme.textSecondary
        valueLabel.textColor = theme.textPrimary
        separator.layer?.backgroundColor = theme.separator.withAlphaComponent(0.55).cgColor
    }
}

private final class InfoSectionRowView: NSView, ThemeAware {
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        if !title.isEmpty {
            heightAnchor.constraint(equalToConstant: 30).isActive = true
        } else {
            heightAnchor.constraint(equalToConstant: 8).isActive = true
        }

        label.stringValue = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyTheme() {
        label.textColor = Theme.shared.textSecondary
    }
}

private final class InfoScrollDocumentView: NSView {
    override var isFlipped: Bool { true }
}
