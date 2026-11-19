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
            case .power: return "电源"
            case .thermal: return "热状态"
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
    private var isVisiblePanel = false

    init() { super.init(title: "性能") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        select(.cpu)
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
                card.update(
                    line1: "读 " + Formats.rate(iokit?.diskReadPerSecond ?? 0),
                    line2: "写 " + Formats.rate(iokit?.diskWritePerSecond ?? 0),
                    values: history.diskRead,
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
                    line2: pressureName(system?.memoryPressure ?? -1),
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
            (detailViews[.disk] as? GenericDetailView)?.update(
                title: "磁盘",
                value: Formats.rate(iokit?.diskReadPerSecond ?? 0),
                subtitle: "读 " + Formats.rate(iokit?.diskReadPerSecond ?? 0) + " · 写 " + Formats.rate(iokit?.diskWritePerSecond ?? 0),
                chartValues: history.diskRead,
                chartTitle: "读取速率（蓝）· 写入速率（橙）",
                color: Theme.shared.color(.disk),
                metrics: [
                    ("读取", Formats.rate(iokit?.diskReadPerSecond ?? 0)),
                    ("写入", Formats.rate(iokit?.diskWritePerSecond ?? 0)),
                ],
                secondSeries: history.diskWrite,
                secondColor: Theme.shared.color(.thermal)
            )
        case .network:
            (detailViews[.network] as? GenericDetailView)?.update(
                title: "网络",
                value: Formats.rate(network?.bytesInPerSecond ?? 0),
                subtitle: "下行 " + Formats.rate(network?.bytesInPerSecond ?? 0) + " · 上行 " + Formats.rate(network?.bytesOutPerSecond ?? 0),
                chartValues: history.networkIn,
                chartTitle: "接收（蓝）· 发送（绿）",
                color: Theme.shared.color(.network),
                metrics: [
                    ("下行", Formats.rate(network?.bytesInPerSecond ?? 0)),
                    ("上行", Formats.rate(network?.bytesOutPerSecond ?? 0)),
                    ("累计接收", Formats.memory(network?.totalBytesIn ?? 0)),
                    ("累计发送", Formats.memory(network?.totalBytesOut ?? 0)),
                    ("接口数", "\(network?.interfaces ?? 0)"),
                ],
                secondSeries: history.networkOut,
                secondColor: Theme.shared.color(.cpu)
            )
        case .power:
            (detailViews[.power] as? GenericDetailView)?.update(
                title: "电源",
                value: iokit?.watts.map { String(format: "%.1f W", $0) } ?? "不可用",
                subtitle: powerSubtitle(iokit: iokit),
                chartValues: history.watts,
                chartTitle: "实时功耗",
                color: Theme.shared.color(.power),
                metrics: [
                    ("实时功耗", iokit?.watts.map { String(format: "%.1f W", $0) } ?? "不可用"),
                    ("电源状态", iokit?.powerSource ?? "不可用"),
                    ("电池电量", iokit?.batteryPercent.map { "\($0)%" } ?? "不可用"),
                    ("充电状态", iokit?.isCharging == true ? "充电中" : (iokit?.hasBattery == true ? "未充电" : "不可用")),
                    ("适配器", iokit?.adapterWatts.map { "\($0) W" } ?? "不可用"),
                    ("电池健康", iokit?.batteryHealthPercent.map { String(format: "%.0f%%", $0) } ?? "不可用"),
                    ("循环次数", iokit?.cycleCount.map { "\($0)" } ?? "不可用"),
                ]
            )
        case .thermal:
            (detailViews[.thermal] as? GenericDetailView)?.update(
                title: "热状态",
                value: iokit?.temperature.map { String(format: "%.1f °C", $0) } ?? "不可用",
                subtitle: pressureName(system?.memoryPressure ?? -1),
                chartValues: history.temperature,
                chartTitle: "CPU 温度（SMC TC0P）",
                color: Theme.shared.color(.thermal),
                metrics: [
                    ("温度", iokit?.temperature.map { String(format: "%.1f °C", $0) } ?? "不可用"),
                    ("内存压力", pressureName(system?.memoryPressure ?? -1)),
                ]
            )
        }
    }

    private func powerSubtitle(iokit: IOKitSample?) -> String {
        guard let iokit else { return "不可用" }
        var parts = [iokit.powerSource]
        if let percent = iokit.batteryPercent { parts.append("\(percent)%") }
        if let adapter = iokit.adapterWatts { parts.append("\(adapter)W") }
        return parts.joined(separator: " · ")
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

// MARK: - 子系统卡片

protocol ThemeAware: AnyObject {
    func applyTheme()
}

final class SubsystemCardView: NSView {
    let subsystem: PerformancePanelViewController.Subsystem
    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let line1Label = NSTextField(labelWithString: "")
    private let line2Label = NSTextField(labelWithString: "")
    private let sparkline = SparklineView()
    private var selected = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(subsystem: PerformancePanelViewController.Subsystem) {
        self.subsystem = subsystem
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 58).isActive = true

        titleLabel.stringValue = subsystem.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        line1Label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        line1Label.lineBreakMode = .byTruncatingTail
        line1Label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line1Label)

        line2Label.font = .systemFont(ofSize: 11)
        line2Label.lineBreakMode = .byTruncatingTail
        line2Label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line2Label)

        iconView.image = NSImage(systemSymbolName: subsystem.symbol, accessibilityDescription: subsystem.title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        sparkline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sparkline)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            line1Label.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            line1Label.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            line1Label.trailingAnchor.constraint(lessThanOrEqualTo: sparkline.leadingAnchor, constant: -5),

            line2Label.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            line2Label.topAnchor.constraint(equalTo: line1Label.bottomAnchor, constant: 1),
            line2Label.trailingAnchor.constraint(lessThanOrEqualTo: sparkline.leadingAnchor, constant: -5),

            sparkline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sparkline.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            sparkline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            sparkline.widthAnchor.constraint(equalToConstant: 60),
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

    override func mouseEntered(with event: NSEvent) { hovered = true; refreshBackground() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshBackground() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        refreshBackground()
    }

    func update(line1: String, line2: String, values: [Double], color: NSColor) {
        line1Label.stringValue = line1
        line2Label.stringValue = line2
        sparkline.values = values
        sparkline.color = color
        iconView.contentTintColor = color
    }

    func applyTheme() {
        let theme = Theme.shared
        titleLabel.textColor = theme.textPrimary
        line1Label.textColor = theme.textPrimary
        line2Label.textColor = theme.textSecondary
        iconView.contentTintColor = theme.color(subsystem.kind)
        refreshBackground()
    }

    private func refreshBackground() {
        let theme = Theme.shared
        let color = theme.color(subsystem.kind)
        if selected || hovered {
            layer?.backgroundColor = theme.cardBackground.cgColor
            layer?.borderColor = color.withAlphaComponent(selected ? 0.9 : 0.4).cgColor
        } else {
            layer?.backgroundColor = theme.cardBackground.withAlphaComponent(0.55).cgColor
            layer?.borderColor = theme.separator.withAlphaComponent(0.6).cgColor
        }
    }
}