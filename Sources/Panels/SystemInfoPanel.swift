import AppKit
import Darwin
import IOKit

// MARK: - 分类（与 TMOG“系统信息”菜单一一对应：硬件 12 / 网络 6 / 软件 13）

enum InfoCategory: Int, CaseIterable {
    // 硬件
    case hardware, memory, audio, bluetooth, camera, graphics, controller, nvme, applePay, smartCard, thunderbolt, power
    // 网络
    case wifi, ethernet, network, location, volume, firewall
    // 软件
    case software, extensions, framework, fonts, install, prefPane, startupItem, localization, diagnostics, logs, printers, printerSoftware, accessibility

    var title: String {
        switch self {
        case .hardware: return "硬件"
        case .memory: return "内存"
        case .audio: return "音频"
        case .bluetooth: return "蓝牙"
        case .camera: return "相机"
        case .graphics: return "图形卡/显示器"
        case .controller: return "控制器"
        case .nvme: return "NVMExpress"
        case .applePay: return "Apple Pay"
        case .smartCard: return "智能卡"
        case .thunderbolt: return "雷电/USB4"
        case .power: return "电源"
        case .wifi: return "Wi-Fi"
        case .ethernet: return "以太网"
        case .network: return "网络"
        case .location: return "位置"
        case .volume: return "宗卷"
        case .firewall: return "防火墙"
        case .software: return "软件"
        case .extensions: return "扩展"
        case .framework: return "Framework"
        case .fonts: return "字体"
        case .install: return "安装"
        case .prefPane: return "偏好设置面板"
        case .startupItem: return "启动项"
        case .localization: return "语言与地区"
        case .diagnostics: return "诊断"
        case .logs: return "日志"
        case .printers: return "打印机"
        case .printerSoftware: return "打印机软件"
        case .accessibility: return "辅助功能"
        }
    }

    var symbol: String {
        switch self {
        case .hardware: return "desktopcomputer"
        case .memory: return "memorychip"
        case .audio: return "speaker.wave.2"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .camera: return "camera"
        case .graphics: return "display"
        case .controller: return "gamecontroller"
        case .nvme: return "internaldrive"
        case .applePay: return "creditcard"
        case .smartCard: return "creditcard.fill"
        case .thunderbolt: return "bolt.fill"
        case .power: return "power"
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .network: return "network"
        case .location: return "location"
        case .volume: return "externaldrive"
        case .firewall: return "shield.lefthalf.filled"
        case .software: return "gearshape"
        case .extensions: return "puzzlepiece.extension"
        case .framework: return "square.stack.3d.up"
        case .fonts: return "textformat"
        case .install: return "shippingbox"
        case .prefPane: return "slider.horizontal.3"
        case .startupItem: return "power.circle"
        case .localization: return "globe"
        case .diagnostics: return "stethoscope"
        case .logs: return "list.bullet.rectangle"
        case .printers: return "printer"
        case .printerSoftware: return "printer.fill"
        case .accessibility: return "figure.accessibility"
        }
    }

    /// 左侧列表分组：0 硬件 / 1 网络 / 2 软件
    var group: Int {
        switch self {
        case .hardware, .memory, .audio, .bluetooth, .camera, .graphics, .controller, .nvme, .applePay, .smartCard, .thunderbolt, .power:
            return 0
        case .wifi, .ethernet, .network, .location, .volume, .firewall:
            return 1
        default:
            return 2
        }
    }

    /// 该页对应的 system_profiler 数据类型（SPReader 按需取数并缓存）
    var spType: String? {
        switch self {
        case .hardware: return "SPHardwareDataType"
        case .memory: return "SPMemoryDataType"
        case .audio: return "SPAudioDataType"
        case .bluetooth: return "SPBluetoothDataType"
        case .camera: return "SPCameraDataType"
        case .graphics: return "SPDisplaysDataType"
        case .controller: return "SPiBridgeDataType"
        case .nvme: return "SPNVMeDataType"
        case .applePay: return "SPSecureElementDataType"
        case .smartCard: return "SPSmartCardsDataType"
        case .thunderbolt: return "SPThunderboltDataType"
        case .power: return "SPPowerDataType"
        case .wifi: return "SPAirPortDataType"
        case .ethernet: return "SPEthernetDataType"
        case .network: return "SPNetworkDataType"
        case .location: return "SPNetworkLocationDataType"
        case .volume: return "SPNetworkVolumeDataType"
        case .firewall: return "SPFirewallDataType"
        case .software: return "SPSoftwareDataType"
        case .extensions: return "SPExtensionsDataType"
        case .framework: return "SPFrameworksDataType"
        case .fonts: return "SPFontsDataType"
        case .install: return "SPInstallHistoryDataType"
        case .prefPane: return "SPPrefPaneDataType"
        case .startupItem: return "SPStartupItemDataType"
        case .localization: return "SPInternationalDataType"
        case .diagnostics: return "SPDiagnosticsDataType"
        case .logs: return "SPLogsDataType"
        case .printers: return "SPPrintersDataType"
        case .printerSoftware: return "SPPrintersSoftwareDataType"
        case .accessibility: return "SPUniversalAccessDataType"
        }
    }
}

let infoGroupTitles = ["硬件", "网络", "软件"]

/// 大列表页只显示前 N 条（NSStackView 承载不了数千行）
let infoListCap = 150

enum InfoRowSpec {
    case field(String, String)
    case section(String)
    case subSection(String)
    case note(String)
}

struct SystemDiskInfo {
    let bsdName: String
    let model: String
    let size: UInt64
    let used: UInt64
    let available: UInt64
    let medium: String
    let interconnect: String
}

struct NetworkInterfaceInfo {
    let name: String
    let ipv4: String?
    let ipv6: String?
    let mac: String?
    let isUp: Bool
    let isRunning: Bool
}

/// 每次刷新采回的活数据（磁盘/网络速率需两次采样求差）
struct LiveSample {
    let gpuVRAMMB: Int?
    let interfaces: [NetworkInterfaceInfo]
    let disks: [SystemDiskInfo]
    let system: SystemSnapshot
    let iokit: IOKitSample
    let network: NetworkSampler.Sample
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

    var selectedCategory: InfoCategory = .hardware
    private var activeSpecs: [InfoRowSpec] = []
    var isLoading = false

    var gpuVRAMMB: Int?
    var interfaces: [NetworkInterfaceInfo] = []
    var disks: [SystemDiskInfo] = []
    var systemInfo: SystemSnapshot?
    var iokit: IOKitSample?
    var networkSample: NetworkSampler.Sample?

    init() { super.init(title: "系统信息") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        select(Self.initialCategory())
        refresh()
    }

    /// 调试：`--info-category <名称|序号>` 指定首次打开的子项，便于逐页截图验证。
    private static func initialCategory() -> InfoCategory {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--info-category"), index + 1 < args.count {
            let name = args[index + 1]
            if let match = InfoCategory.allCases.first(where: { String(describing: $0) == name }) {
                return match
            }
            if let order = Int(name), order >= 0, order < InfoCategory.allCases.count {
                return InfoCategory.allCases[order]
            }
        }
        return .hardware
    }

    /// 切换子项：先按现有数据重建（未取回的 SP 页显示“正在读取…”），再按需后台取数完成后重建。
    func select(_ category: InfoCategory) {
        selectedCategory = category
        categoryPopup.selectItem(at: category.rawValue)
        headerIcon.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.title)
        categoryRows.forEach { $0.setSelected($0.category == category) }
        rebuildRows()
        ensureSPData(for: category)
    }

    private func ensureSPData(for category: InfoCategory) {
        guard let type = category.spType, !SPReader.isLoaded(type) else { return }
        SPReader.ensure([type]) { [weak self] in
            guard let self, self.selectedCategory == category else { return }
            self.rebuildRows()
        }
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

    @objc private func reloadTapped() {
        refresh()
    }

    @objc private func copyTapped() {
        var lines: [String] = []
        for spec in activeSpecs {
            switch spec {
            case .field(let key, let value):
                lines.append("\(key): \(value)")
            case .section(let title), .subSection(let title):
                if title.isEmpty { continue }
                if !lines.isEmpty { lines.append("") }
                lines.append("[\(title)]")
            case .note(let text):
                lines.append(text)
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
            let sample = LiveSample(
                gpuVRAMMB: gpuVRAMMB,
                interfaces: interfaces,
                disks: disks,
                system: system,
                iokit: iokitSampler.sample(),
                network: networkSampler.sample()
            )

            DispatchQueue.main.async {
                guard let self else { return }
                self.gpuVRAMMB = sample.gpuVRAMMB
                self.interfaces = sample.interfaces
                self.disks = sample.disks
                self.systemInfo = sample.system
                self.iokit = sample.iokit
                self.networkSample = sample.network
                self.isLoading = false
                self.reloadButton.isEnabled = true
                self.rebuildRows()
            }
        }
        ensureSPData(for: selectedCategory)
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
                rowsStack.addArrangedSubview(InfoSectionRowView(title: title, indent: false))
            case .subSection(let title):
                rowsStack.addArrangedSubview(InfoSectionRowView(title: title, indent: true))
            case .note(let text):
                rowsStack.addArrangedSubview(InfoNoteRowView(text: text))
            }
        }
        rowsStack.layoutSubtreeIfNeeded()
        rowsScroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        rowsScroll.reflectScrolledClipView(rowsScroll.contentView)
        applyTheme()
    }

    private func buildRows(for category: InfoCategory) -> [InfoRowSpec] {
        switch category {
        case .hardware: return hardwareRows()
        case .memory: return memoryRows()
        case .audio: return audioRows()
        case .bluetooth: return bluetoothRows()
        case .camera: return cameraRows()
        case .graphics: return graphicsRows()
        case .controller: return controllerRows()
        case .nvme: return nvmeRows()
        case .applePay: return applePayRows()
        case .smartCard: return smartCardRows()
        case .thunderbolt: return thunderboltRows()
        case .power: return powerRows()
        case .wifi: return wifiRows()
        case .ethernet: return ethernetRows()
        case .network: return networkRows()
        case .location: return locationRows()
        case .volume: return volumeRows()
        case .firewall: return firewallRows()
        case .software: return softwareRows()
        case .extensions: return extensionsRows()
        case .framework: return frameworkRows()
        case .fonts: return fontsRows()
        case .install: return installRows()
        case .prefPane: return prefPaneRows()
        case .startupItem: return startupItemRows()
        case .localization: return localizationRows()
        case .diagnostics: return diagnosticsRows()
        case .logs: return logsRows()
        case .printers: return printersRows()
        case .printerSoftware: return printerSoftwareRows()
        case .accessibility: return accessibilityRows()
        }
    }

    /// 硬件：SPHardwareDataType 概览 + 处理器细节（sysctl）+ 实时利用率
    private func hardwareRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = []
        if let hw = SPReader.first("SPHardwareDataType") {
            rows.append(contentsOf: [
                .field("机型名称", SPReader.value(hw, "machine_name") ?? "不可用"),
                .field("机型标识符", SPReader.value(hw, "machine_model") ?? "不可用"),
            ])
            if let chip = SPReader.value(hw, "cpu_type") {
                rows.append(.field("芯片", chip))
            }
            if let speed = SPReader.value(hw, "current_processor_speed") {
                rows.append(.field("当前处理器速度", speed))
            }
            if let cores = SPReader.value(hw, "number_processors") {
                let logical = StaticInfo.logicalCores
                let physical = StaticInfo.physicalCores
                rows.append(.field("核心总数", "\(logical)（\(physical) 物理核心）"))
                if let htt = SPReader.value(hw, "platform_cpu_htt") {
                    rows.append(.field("超线程技术", htt == "htt_enabled" ? "已启用" : "不可用"))
                }
                _ = cores
            }
            rows.append(contentsOf: [
                .field("处理器架构", StaticInfo.machine),
                .field("L2 缓存 / 核心", SPReader.value(hw, "l2_cache_core") ?? "不可用"),
                .field("L3 缓存", SPReader.value(hw, "l3_cache") ?? "不可用"),
                .field("64 位支持", StaticInfo.sysctlInt("hw.cpu64bit_capable") != 0 ? "是" : "否"),
                .field("虚拟化支持", StaticInfo.sysctlInt("kern.hv_support") != 0 ? "是" : "否"),
            ])
            if let mem = SPReader.value(hw, "physical_memory") {
                rows.append(.field("内存", mem))
            }
            if let serial = SPReader.value(hw, "serial_number") {
                rows.append(.field("序列号", serial))
            }
            if let uuid = SPReader.value(hw, "platform_UUID") {
                rows.append(.field("硬件 UUID", uuid))
            }
            if let lock = SPReader.value(hw, "activation_lock_status") {
                rows.append(.field("激活锁状态", lock == "activation_lock_enabled" ? "已启用" : "未启用"))
            }
            if let rom = SPReader.value(hw, "boot_rom_version") {
                rows.append(.field("系统固件版本", rom))
            }
            if let loader = SPReader.value(hw, "os_loader_version") {
                rows.append(.field("操作系统加载程序版本", loader))
            }
        } else {
            rows.append(.field("机型名称", isLoading ? "正在读取…" : "不可用"))
        }
        rows.append(contentsOf: [
            .field("系统版本", StaticInfo.osVersion),
            .field("主机名", StaticInfo.hostName),
        ])
        if let systemInfo {
            rows.append(.field("运行时长", Formats.uptime(systemInfo.uptime)))
            rows.append(.field("当前利用率", Formats.percent(systemInfo.cpuTotal)))
            rows.append(.field("内核占用", Formats.percent(systemInfo.kernelPercent)))
        } else if isLoading {
            rows.append(.field("运行时长", "正在读取…"))
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
        var rows: [InfoRowSpec] = [
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

        // 硬件插槽（SPMemoryDataType，对标 TMOG 内存页）
        if let mem = SPReader.first("SPMemoryDataType") {
            let slots = mem["_items"] as? [[String: Any]] ?? []
            if !slots.isEmpty {
                rows.append(.section("内存插槽"))
                for slot in slots {
                    rows.append(.subSection(SPReader.value(slot, "_name") ?? "插槽"))
                    rows.append(.field("生产企业", SPReader.value(slot, "dimm_manufacturer") ?? "不可用"))
                    rows.append(.field("部件号", SPReader.value(slot, "dimm_part_number") ?? "不可用"))
                    rows.append(.field("序列号", SPReader.value(slot, "dimm_serial_number") ?? "不可用"))
                    rows.append(.field("大小", SPReader.value(slot, "dimm_size") ?? "不可用"))
                    rows.append(.field("速度", SPReader.value(slot, "dimm_speed") ?? "不可用"))
                    rows.append(.field("状态", SPReader.value(slot, "dimm_status") ?? "不可用"))
                    rows.append(.field("类型", SPReader.value(slot, "dimm_type") ?? "不可用"))
                }
            }
            if let ecc = SPReader.value(mem, "global_ecc_state") {
                rows.append(.field("ECC", ecc == "ecc_enabled" ? "已启用" : "已停用"))
            }
            if let upgradeable = SPReader.value(mem, "is_memory_upgradeable") {
                rows.append(.field("可升级内存", upgradeable == "yes" ? "是" : "否"))
            }
        } else if isLoading {
            rows.append(.field("内存插槽", "正在读取…"))
        }
        return rows
    }

    private func graphicsRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = [.field("图形处理器", IOKitSampler.gpuModel)]
        var vramAdded = false
        if let disp = SPReader.first("SPDisplaysDataType") {
            if let chipset = SPReader.value(disp, "sppci_model") {
                rows.append(.field("芯片型号", chipset))
            }
            if let vendor = SPReader.value(disp, "spdisplays_vendor") {
                rows.append(.field("制造商", vendor))
            }
            if let metal = SPReader.value(disp, "spdisplays_mtlgpufamilysupport") {
                rows.append(.field("Metal 支持", SPMap.spMetal(metal)))
            }
            if let vram = SPReader.value(disp, "_spdisplays_vram") {
                rows.append(.field("显存", vram))
                vramAdded = true
            }
        }
        if !vramAdded, let gpuVRAMMB {
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

    /// 控制器：SPiBridgeDataType（Apple T2 等安全芯片）
    private func controllerRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = []
        if let entry = SPReader.first("SPiBridgeDataType"),
           let model = SPReader.value(entry, "ibridge_model_name") {
            rows.append(.section(model))
            if let fw = SPReader.value(entry, "ibridge_build") {
                rows.append(.field("固件版本", fw))
            }
            if let uuid = SPReader.value(entry, "ibridge_boot_uuid") {
                rows.append(.field("启动 UUID", uuid))
            }
        } else if isLoading {
            rows.append(.field("控制器", "正在读取…"))
        }
        if rows.isEmpty {
            rows.append(.field("控制器", "未检测到安全控制器"))
        }
        return rows
    }

    /// NVMExpress：SPNVMeDataType 设备/宗卷/链路 + IOKit 实时读写速率
    private func nvmeRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = []
        for entry in SPReader.entries("SPNVMeDataType") ?? [] {
            let controller = SPReader.value(entry, "_name") ?? "NVMe 控制器"
            for device in SPReader.array(entry, "_items") {
                let name = SPReader.value(device, "device_model") ?? "NVMe 设备"
                let bsd = SPReader.value(device, "bsd_name") ?? ""
                rows.append(.section(bsd.isEmpty ? name : "\(bsd) · \(name)"))
                rows.append(.field("序列号", SPReader.value(device, "device_serial") ?? "不可用"))
                if let revision = SPReader.value(device, "device_revision") {
                    rows.append(.field("修订", revision))
                }
                if let size = SPReader.value(device, "size") {
                    rows.append(.field("容量", size))
                }
                if let smart = SPReader.value(device, "smart_status") {
                    rows.append(.field("S.M.A.R.T.", smart))
                }
                if let trim = SPReader.value(device, "spnvme_trim_support") {
                    rows.append(.field("TRIM", SPMap.yesNo(trim, yes: "支持", no: "不支持")))
                }
                if let speed = SPReader.value(device, "spnvme_linkspeed") {
                    if let width = SPReader.value(device, "spnvme_linkwidth") {
                        rows.append(.field("链路速率", "\(width) @ \(speed)"))
                    } else {
                        rows.append(.field("链路速率", speed))
                    }
                }
                if let removable = SPReader.value(device, "removable_media") {
                    rows.append(.field("可移动介质", SPMap.yesNo(removable)))
                }
                // 宗卷
                let volumes = SPReader.array(device, "volumes")
                for vol in volumes {
                    let volName = SPReader.value(vol, "_name") ?? "宗卷"
                    rows.append(.subSection("\(SPReader.value(vol, "bsd_name") ?? "") \(volName)"))
                    if let fs = SPReader.value(vol, "file_system") {
                        rows.append(.field("文件系统", fs))
                    }
                    if let size = SPReader.value(vol, "size") {
                        rows.append(.field("容量", size))
                    }
                    if let uuid = SPReader.value(vol, "volume_uuid") {
                        rows.append(.field("宗卷 UUID", uuid))
                    }
                }
                // 实时读写速率（IOKit）
                if !bsd.isEmpty, let iokit, let rate = iokit.perDisk[bsd] {
                    rows.append(.field("读取速率", Formats.rate(rate.readPerSecond)))
                    rows.append(.field("写入速率", Formats.rate(rate.writePerSecond)))
                }
                _ = controller
            }
        }
        if rows.isEmpty {
            rows.append(.field("NVMExpress", isLoading ? "正在读取…" : "未检测到 NVMe 设备"))
        }
        return rows
    }

    /// Apple Pay：SPSecureElementDataType（安全元件）
    private func applePayRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = []
        if let se = SPReader.first("SPSecureElementDataType") {
            if let plt = SPReader.value(se, "se_plt") {
                rows.append(.field("平台 ID", plt))
            }
            if let seid = SPReader.value(se, "se_id") {
                rows.append(.field("SEID", seid))
            }
            if let device = SPReader.value(se, "se_device") {
                rows.append(.field("设备", device))
            }
            if let prod = SPReader.value(se, "se_prod_signed") {
                rows.append(.field("生产签名", SPMap.yesNo(prod)))
            }
            if let restricted = SPReader.value(se, "se_in_restricted_mode") {
                rows.append(.field("限制模式", SPMap.yesNo(restricted)))
            }
            if let jcop = SPReader.value(se, "se_os_version") {
                rows.append(.field("JCOP 系统", jcop.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            if let hw = SPReader.value(se, "ctl_hw") {
                var text = hw.trimmingCharacters(in: .whitespaces)
                while text.hasSuffix("()") { text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces) }
                rows.append(.field("控制器硬件", text.isEmpty ? "不可用" : text))
            }
            if let fw = SPReader.value(se, "ctl_fw") {
                rows.append(.field("控制器固件", fw))
            }
            if let mw = SPReader.value(se, "ctl_mw") {
                rows.append(.field("中间件", mw))
            }
        } else if isLoading {
            rows.append(.field("Apple Pay", "正在读取…"))
        }
        if rows.isEmpty {
            rows.append(.field("Apple Pay", "未检测到安全元件"))
        }
        return rows
    }

    /// 智能卡：SPSmartCardsDataType（读卡器/驱动/令牌）
    private func smartCardRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPSmartCardsDataType") else {
            return [.field("智能卡", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries {
            switch SPReader.value(entry, "_name") ?? "" {
            case "READERS":
                let readers = SPReader.array(entry, "_items")
                rows.append(.section("读卡器"))
                rows.append(.field("数量", readers.isEmpty ? "未检测到" : "\(readers.count)"))
            case "READERS_DRIVERS", "SMARTCARDS_DRIVERS":
                let title = SPReader.value(entry, "_name") == "READERS_DRIVERS" ? "读卡器驱动" : "智能卡驱动"
                // 值形如 "com.apple.CryptoTokenKit.pivtoken:1.0 (/System/...)"：按首个冒号拆 标识 与 详情
                let driverItems = entry.filter { $0.key.hasPrefix("#") && $0.value is String }.sorted { $0.key < $1.key }
                rows.append(.section(title))
                if driverItems.isEmpty {
                    rows.append(.field("状态", "未检测到"))
                } else {
                    for (key, value) in driverItems {
                        let text = value as! String
                        if let colon = text.firstIndex(of: ":") {
                            rows.append(.field(String(text[..<colon]), String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
                        } else {
                            rows.append(.field(key, text))
                        }
                    }
                }
            case "AVAIL_SMARTCARDS_KEYCHAIN", "AVAIL_SMARTCARDS_TOKEN":
                let title = SPReader.value(entry, "_name") == "AVAIL_SMARTCARDS_KEYCHAIN" ? "钥匙串令牌" : "可用令牌"
                let items = SPReader.array(entry, "_items")
                rows.append(.section(title))
                if items.isEmpty {
                    rows.append(.field("状态", "不可用"))
                } else {
                    for item in items {
                        if let name = SPReader.value(item, "_name") {
                            rows.append(.field("令牌", name))
                        }
                    }
                }
            default:
                continue
            }
        }
        if rows.isEmpty {
            rows.append(.field("智能卡", "未检测到智能卡相关组件"))
        }
        return rows
    }

    private func powerRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = []
        if let iokit {
            if iokit.hasBattery {
                rows.append(.field("当前电量", iokit.batteryPercent.map { "\($0)%" } ?? "不可用"))
                rows.append(.field("充电状态", iokit.isCharging ? "充电中" : "未充电"))
                rows.append(.field("循环次数", iokit.cycleCount.map { "\($0)" } ?? "不可用"))
                rows.append(.field("健康度", iokit.batteryHealthPercent.map { String(format: "%.1f%%", $0) } ?? "不可用"))
            } else {
                rows.append(.field("电池", "未检测到电池"))
            }
            rows.append(.field("电源来源", iokit.powerSource))
            rows.append(.field("实时功耗", iokit.watts.map { String(format: "%.1f W", $0) } ?? "不可用"))
            rows.append(.field("适配器", iokit.adapterWatts.map { "\($0) W" } ?? "不可用"))
        } else if isLoading {
            rows.append(.field("当前电量", "正在读取…"))
        }

        // 电池型号 / 健康 / 电源设置（SPPowerDataType）
        if let battery = SPReader.find("SPPowerDataType", "spbattery_information") {
            if let model = battery["sppower_battery_model_info"] as? [String: Any] {
                var modelRows: [InfoRowSpec] = []
                if let sn = SPReader.value(model, "sppower_battery_serial_number") {
                    modelRows.append(.field("序列号", sn))
                }
                if let mfr = SPReader.value(model, "sppower_battery_manufacturer") {
                    modelRows.append(.field("制造商", mfr))
                }
                if let dev = SPReader.value(model, "sppower_battery_device_name") {
                    modelRows.append(.field("设备名称", dev))
                }
                if !modelRows.isEmpty {
                    rows.append(.section("电池型号"))
                    rows.append(contentsOf: modelRows)
                }
            }
            if let charge = battery["sppower_battery_charge_info"] as? [String: Any],
               let maxCap = SPReader.value(charge, "sppower_battery_max_capacity") {
                rows.append(.field("设计容量", "\(maxCap) mAh"))
            }
        }
        if let settings = SPReader.find("SPPowerDataType", "sppower_information"),
           let ac = settings["AC Power"] as? [String: Any] {
            rows.append(.section("系统电源设置 · 交流电源"))
            if let sys = SPReader.value(ac, "System Sleep Timer") {
                rows.append(.field("系统睡眠", SPMap.timerText(sys)))
            }
            if let disp = SPReader.value(ac, "Display Sleep Timer") {
                rows.append(.field("显示器睡眠", SPMap.timerText(disp)))
            }
            if let disk = SPReader.value(ac, "Disk Sleep Timer") {
                rows.append(.field("磁盘睡眠", SPMap.timerText(disk)))
            }
        }
        if rows.isEmpty, isLoading {
            rows.append(.field("状态", "正在读取…"))
        }
        return rows
    }

    // MARK: - 音频 / 蓝牙 / 相机 / 雷电（SPPower/SPAudio/SPBluetooth/SPCamera/SPThunderbolt）

    private func audioRows() -> [InfoRowSpec] {
        if SPReader.entries("SPAudioDataType") == nil {
            return [.field("设备", isLoading ? "正在读取…" : "不可用")]
        }
        let items = SPReader.first("SPAudioDataType")?["_items"] as? [[String: Any]] ?? []
        if items.isEmpty {
            return [.field("设备", "未检测到音频设备")]
        }
        var rows: [InfoRowSpec] = []
        for item in items {
            rows.append(.section(SPReader.value(item, "_name") ?? "设备"))
            let isInput = item["coreaudio_device_input"] != nil
            if let ch = SPReader.value(item, isInput ? "coreaudio_device_input" : "coreaudio_device_output") {
                rows.append(.field(isInput ? "输入通道" : "输出通道", ch))
            }
            if let srate = SPReader.value(item, "coreaudio_device_srate") {
                rows.append(.field("采样率", "\(srate) Hz"))
            }
            if let mfr = SPReader.value(item, "coreaudio_device_manufacturer") {
                rows.append(.field("制造商", mfr))
            }
            if let transport = SPReader.value(item, "coreaudio_device_transport") {
                rows.append(.field("传输", SPMap.spAudioTransport(transport)))
            }
            if isInput {
                if let src = SPReader.value(item, "coreaudio_input_source") {
                    rows.append(.field("输入来源", src))
                }
                rows.append(.field("默认输入", item["coreaudio_default_audio_input_device"] != nil ? "是" : "否"))
            } else {
                rows.append(.field("默认输出", item["coreaudio_default_audio_output_device"] != nil ? "是" : "否"))
                rows.append(.field("默认系统输出", item["coreaudio_default_audio_system_device"] != nil ? "是" : "否"))
            }
        }
        return rows
    }

    private func bluetoothRows() -> [InfoRowSpec] {
        if SPReader.entries("SPBluetoothDataType") == nil {
            return [.field("状态", isLoading ? "正在读取…" : "不可用")]
        }
        guard let bt = SPReader.first("SPBluetoothDataType"), let ctrl = bt["controller_properties"] as? [String: Any] else {
            return [.field("蓝牙", "未检测到控制器")]
        }
        var rows: [InfoRowSpec] = [
            .field("状态", SPMap.onOff(ctrl["controller_state"] as? String)),
            .field("地址", SPReader.value(ctrl, "controller_address") ?? "不可用"),
            .field("芯片组", SPReader.value(ctrl, "controller_chipset") ?? "不可用"),
        ]
        if let fw = SPReader.value(ctrl, "controller_firmwareVersion") {
            rows.append(.field("固件版本", fw))
        }
        if let disc = SPReader.value(ctrl, "controller_discoverable") {
            rows.append(.field("可被发现", SPMap.onOff(disc)))
        }
        if let vendor = SPReader.value(ctrl, "controller_vendorID") {
            rows.append(.field("供应商", vendor))
        }
        if let transport = SPReader.value(ctrl, "controller_transport") {
            rows.append(.field("传输", transport))
        }
        if let services = SPReader.value(ctrl, "controller_supportedServices") {
            rows.append(.field("支持服务", services))
        }
        return rows
    }

    private func cameraRows() -> [InfoRowSpec] {
        if SPReader.entries("SPCameraDataType") == nil {
            return [.field("相机", isLoading ? "正在读取…" : "不可用")]
        }
        let items = SPReader.entries("SPCameraDataType") ?? []
        if items.isEmpty {
            return [.field("相机", "未检测到相机")]
        }
        var rows: [InfoRowSpec] = []
        for item in items {
            rows.append(.section(SPReader.value(item, "_name") ?? "相机"))
            if let model = SPReader.value(item, "spcamera_model-id") {
                rows.append(.field("型号", model))
            }
            if let uid = SPReader.value(item, "spcamera_unique-id") {
                rows.append(.field("唯一 ID", uid))
            }
        }
        return rows
    }

    private func thunderboltRows() -> [InfoRowSpec] {
        if SPReader.entries("SPThunderboltDataType") == nil {
            return [.field("雷电/USB4", isLoading ? "正在读取…" : "不可用")]
        }
        let items = SPReader.entries("SPThunderboltDataType") ?? []
        if items.isEmpty {
            return [.field("雷电/USB4", "未检测到雷电控制器")]
        }
        var rows: [InfoRowSpec] = []
        for bus in items {
            let rawName = SPReader.value(bus, "_name") ?? "总线"
            rows.append(.section(rawName.replacingOccurrences(of: "thunderbolt_bus_", with: "雷电总线 ")))
            if let dev = SPReader.value(bus, "device_name_key") {
                rows.append(.field("设备", dev))
            }
            if let vendor = SPReader.value(bus, "vendor_name_key") {
                rows.append(.field("供应商", vendor))
            }
            if let fw = SPReader.value(bus, "switch_version_key") {
                rows.append(.field("固件版本", fw))
            }
            if let uid = SPReader.value(bus, "switch_uid_key") {
                rows.append(.field("UID", uid))
            }
            for i in 1...4 {
                guard let port = bus["receptacle_\(i)_tag"] as? [String: Any] else { continue }
                let receptacle = SPReader.value(port, "receptacle_id_key") ?? "\(i)"
                let connected = (SPReader.value(port, "receptacle_status_key") ?? "") != "receptacle_no_devices_connected"
                rows.append(.subSection("端口 \(receptacle)"))
                rows.append(.field("状态", connected ? "已连接" : "未连接设备"))
                if let speed = SPReader.value(port, "current_speed_key") {
                    rows.append(.field("速度", speed))
                }
                if let lc = SPReader.value(port, "lc_version_key") {
                    rows.append(.field("链路控制器固件", lc))
                }
            }
        }
        return rows
    }

    // 网络组 / 软件组页面 builder 见 SystemInfoRowsNetwork.swift / SystemInfoRowsSoftware.swift


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

    init(title: String, indent: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        if !title.isEmpty {
            heightAnchor.constraint(equalToConstant: indent ? 26 : 30).isActive = true
        } else {
            heightAnchor.constraint(equalToConstant: 8).isActive = true
        }

        label.stringValue = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent ? 28 : 12),
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

private final class InfoNoteRowView: NSView, ThemeAware {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true

        label.stringValue = text
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
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
