import AppKit

final class PerformancePanelViewController: PanelBaseViewController {
    enum Subsystem: Int, CaseIterable {
        case cpu, memory, gpu, disk, network, power, thermal

        var title: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "内存"
            case .gpu: return "GPU"
            case .disk: return "磁盘"
            case .network: return "网络"
            case .power: return "能耗"
            case .thermal: return "温度"
            }
        }

        var symbol: String {
            switch self {
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .gpu: return "display"
            case .disk: return "internaldrive"
            case .network: return "network"
            case .power: return "bolt"
            case .thermal: return "thermometer"
            }
        }

        var kind: SubsystemKind {
            switch self {
            case .cpu: return .cpu
            case .memory: return .memory
            case .gpu: return .gpu
            case .disk: return .disk
            case .network: return .network
            case .power: return .power
            case .thermal: return .thermal
            }
        }
    }

    private var selectedSubsystem: Subsystem = .cpu
    private var cards: [SubsystemCardView] = []
    private let cardColumn = NSStackView()
    private let detailContainer = NSView()

    private var detailViews: [Subsystem: NSView] = [:]
    private var cpuDetail: CPUDetailView?
    private var memoryDetail: MemoryDetailView?
    private var powerDetail: PowerDetailView?
    private var thermalDetail: TemperatureDetailView?
    private var diskDetail: DiskDetailView?
    private var isVisiblePanel = false
    /// --disk 调试参数：磁盘详情预置选中的盘
    private var preferredDisk: String?

    init() { super.init(title: "性能") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// TMOG 式布局：左侧资源卡列表，右侧详情自带大标题，顶部不再重复"性能"
    override var showsPanelTitle: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        select(.cpu)
        // 多盘验证用：--disk diskN 预置磁盘详情选中的盘（须在 select() 之前解析）
        if let index = CommandLine.arguments.firstIndex(of: "--disk"), index + 1 < CommandLine.arguments.count {
            preferredDisk = CommandLine.arguments[index + 1]
        }
        // 截图验证用：--subsystem disk 直接选中性能页某子系统
        if let index = CommandLine.arguments.firstIndex(of: "--subsystem"),
           index + 1 < CommandLine.arguments.count {
            let names = ["cpu", "memory", "gpu", "disk", "network", "power", "thermal"]
            if let i = names.firstIndex(of: CommandLine.arguments[index + 1]), let sub = Subsystem(rawValue: i) {
                select(sub)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(samplerUpdated), name: .samplerDidUpdate, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isVisiblePanel = true
        refresh()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        isVisiblePanel = false
    }

    override func applyTheme() {
        super.applyTheme()
        cards.forEach { $0.applyTheme() }
        detailViews.values.forEach { view in
            (view as? ThemeAware)?.applyTheme()
        }
        refresh()
    }

    private func buildLayout() {
        cardColumn.orientation = .vertical
        cardColumn.spacing = 4
        cardColumn.alignment = .width
        cardColumn.distribution = .fill
        cardColumn.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(cardColumn)

        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(detailContainer)

        for subsystem in Subsystem.allCases {
            let card = SubsystemCardView(subsystem: subsystem)
            card.onClick = { [weak self] in self?.select(subsystem) }
            // 磁盘卡对标 TMOG：大标题直接显示盘型号
            if subsystem == .disk, let identity = DiskInfo.primary {
                card.setTitle(identity.model)
            }
            cards.append(card)
            cardColumn.addArrangedSubview(card)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        cardColumn.addArrangedSubview(spacer)

        NSLayoutConstraint.activate([
            cardColumn.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            cardColumn.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            cardColumn.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            cardColumn.widthAnchor.constraint(equalToConstant: 240),

            detailContainer.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: cardColumn.trailingAnchor, constant: 12),
            detailContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func select(_ subsystem: Subsystem) {
        selectedSubsystem = subsystem
        cards.forEach { $0.setSelected($0.subsystem == subsystem) }

        let detail: NSView
        if let cached = detailViews[subsystem] {
            detail = cached
        } else {
            switch subsystem {
            case .cpu:
                let view = CPUDetailView(color: Theme.shared.color(.cpu))
                cpuDetail = view
                detail = view
            case .memory:
                let view = MemoryDetailView(color: Theme.shared.color(.memory))
                memoryDetail = view
                detail = view
            case .disk:
                let view = DiskDetailView()
                diskDetail = view
                preferredDisk.map { view.select(bsdName: $0) }
                detail = view
            case .power:
                let view = PowerDetailView(color: Theme.shared.color(.power))
                powerDetail = view
                detail = view
            case .thermal:
                let view = TemperatureDetailView(color: Theme.shared.color(.thermal))
                thermalDetail = view
                detail = view
            case .network:
                let view = NetworkDetailView()
                // 截图验证用：--netif en0 直接选中某接口
                if let index = CommandLine.arguments.firstIndex(of: "--netif"),
                   index + 1 < CommandLine.arguments.count {
                    view.select(interfaceName: CommandLine.arguments[index + 1])
                }
                detail = view
            default:
                detail = GenericDetailView()
            }
            detailViews[subsystem] = detail
        }

        detailContainer.subviews.forEach { $0.removeFromSuperview() }
        detail.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detail)
        NSLayoutConstraint.activate([
            detail.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detail.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detail.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
        ])
        refresh()
    }

    @objc private func samplerUpdated() {
        guard isVisiblePanel else { return }
        refresh()
    }

    private func refresh() {
        let history = Sampler.shared.historySnapshot
        let system = Sampler.shared.system
        let iokit = Sampler.shared.iokit
        let network = Sampler.shared.network
        let processes = Sampler.shared.processes

        let memoryTotal = StaticInfo.memorySize
        let memoryUsed = system?.memoryUsed ?? 0
        let memoryPercent = memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) * 100.0 : 0
        let threadCount = processes.reduce(0) { $0 + Int($1.threads) }

        for card in cards {
            let color = card.subsystem.kind
            switch card.subsystem {
            case .cpu:
                card.update(
                    line1: Formats.percent(system?.cpuTotal ?? 0),
                    line2: "\(StaticInfo.logicalCores) 逻辑处理器",
                    values: history.cpuTotal,
                    color: Theme.shared.color(color)
                )
            case .memory:
                card.update(
                    line1: Formats.memory(memoryUsed),
                    line2: "\(Formats.percent(memoryPercent)) · \(Formats.memory(memoryTotal))",
                    values: history.memoryUsed,
                    color: Theme.shared.color(color)
                )
            case .gpu:
                card.update(
                    line1: iokit?.gpuUtilization.map { Formats.percent($0) } ?? "不可用",
                    line2: IOKitSampler.gpuModel,
                    values: history.gpuUtilization,
                    color: Theme.shared.color(color)
                )
            case .disk:
                let primary = DiskInfo.primary
                let subtitle = primary.map { "\($0.medium) · \($0.bsdName)" } ?? "磁盘"
                // 磁盘卡跟随主盘（每盘数据，非全局合计）
                let active = primary.flatMap { iokit?.perDisk[$0.bsdName]?.activeTimePercent } ?? 0
                card.update(
                    line1: subtitle,
                    line2: Formats.percent(active),
                    values: primary.map { history.diskActiveByDisk[$0.bsdName] ?? [] } ?? [],
                    color: Theme.shared.color(color)
                )
            case .network:
                card.update(
                    line1: "下行 " + Formats.rate(network?.bytesInPerSecond ?? 0),
                    line2: "上行 " + Formats.rate(network?.bytesOutPerSecond ?? 0),
                    values: history.networkIn,
                    color: Theme.shared.color(color)
                )
            case .power:
                card.update(
                    line1: iokit?.watts.map { String(format: "%.1f W", $0) } ?? "不可用",
                    line2: powerSubtitle(iokit: iokit),
                    values: history.watts,
                    color: Theme.shared.color(color)
                )
            case .thermal:
                card.update(
                    line1: iokit?.temperature.map { String(format: "%.1f °C", $0) } ?? "不可用",
                    line2: "热压力 " + thermalText(Foundation.ProcessInfo.processInfo.thermalState),
                    values: history.temperature,
                    color: Theme.shared.color(color)
                )
            }
        }

        switch selectedSubsystem {
        case .cpu:
            cpuDetail?.update(history: history, system: system, processes: processes, threads: threadCount)
        case .memory:
            memoryDetail?.update(history: history, system: system)
        case .gpu:
            (detailViews[.gpu] as? GenericDetailView)?.update(
                title: "GPU",
                value: iokit?.gpuUtilization.map { Formats.percent($0) } ?? "不可用",
                subtitle: IOKitSampler.gpuModel,
                chartValues: history.gpuUtilization,
                chartTitle: "GPU 利用率",
                color: Theme.shared.color(.gpu),
                metrics: [
                    ("利用率", iokit?.gpuUtilization.map { Formats.percent($0) } ?? "不可用"),
                    ("型号", IOKitSampler.gpuModel),
                ]
            )
        case .disk:
            diskDetail?.update(identities: DiskInfo.identities, iokit: iokit, history: history)
        case .network:
            (detailViews[.network] as? NetworkDetailView)?.update(sample: network, history: history)
        case .power:
            powerDetail?.update(history: history, iokit: iokit)
        case .thermal:
            thermalDetail?.update(history: history, iokit: iokit)
        }
    }

    private func powerSubtitle(iokit: IOKitSample?) -> String {
        guard let iokit else { return "不可用" }
        var parts = [iokit.powerSource]
        if let percent = iokit.batteryPercent { parts.append("\(percent)%") }
        if let adapter = iokit.adapterWatts { parts.append("\(adapter)W") }
        return parts.joined(separator: " · ")
    }

    private func thermalText(_ state: Foundation.ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "正常"
        case .fair: return "温度偏高"
        case .serious: return "温度较高"
        case .critical: return "温度过高"
        @unknown default: return "未知"
        }
    }

    private func pressureName(_ level: Int32) -> String {
        switch level {
        case 1: return "内存压力 正常"
        case 2: return "内存压力 警告"
        case 4: return "内存压力 严重"
        default: return "内存压力 不可用"
        }
    }
}
