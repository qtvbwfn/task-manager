import AppKit

final class SummaryPanelViewController: PanelBaseViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let cpuGauge = GaugeCardView(title: "CPU", kind: .cpu)
    private let tempGauge = GaugeCardView(title: "温度", kind: .thermal)
    private let gpuGauge = GaugeCardView(title: "GPU", kind: .gpu)

    private let overviewChart = ChartView()
    private let overviewTitle = NSTextField(labelWithString: "CPU 概览")
    private let overviewValue = NSTextField(labelWithString: "")
    private let overviewFooter = NSTextField(labelWithString: "")

    private let tableTitle = NSTextField(labelWithString: "Top CPU 进程")
    private let tableCountLabel = NSTextField(labelWithString: "")
    private let topTable = NSTableView()
    private var topProcesses: [ProcessInfo] = []

    private let memoryCard = MemorySummaryCardView()
    private let smallCards: [SmallStatCardView] = [
        SmallStatCardView(title: "磁盘", symbol: "internaldrive", kind: .disk),
        SmallStatCardView(title: "网络", symbol: "network", kind: .network),
        SmallStatCardView(title: "GPU", symbol: "display", kind: .gpu),
        SmallStatCardView(title: "系统压力", symbol: "speedometer", kind: .thermal),
    ]

    private var isVisiblePanel = false
    private var sampleCounter = 0
    /// Top 表可视行数（随窗口高度变化）：TOP N 排满即止、不滚动
    private var visibleRowCount = 0

    /// NSTableView 不会自动缩到 clip：名称列吃掉剩余宽度、表框贴齐 clip，
    /// 否则最后一列（内存）被裁掉、名称列右侧留一大块空白；行数按可视高度取 TOP N
    private func fitTableSize() {
        guard let scroll = topTable.enclosingScrollView else { return }
        let clip = scroll.contentView.bounds
        guard clip.width > 1, clip.height > 1 else { return }
        let headerHeight = topTable.headerView?.frame.height ?? 22
        visibleRowCount = max(3, Int((clip.height - headerHeight) / topTable.rowHeight))
        if let nameColumn = topTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name")) {
            let gap = topTable.intercellSpacing.width * CGFloat(topTable.tableColumns.count - 1)
            let fixed = topTable.tableColumns.filter { $0 != nameColumn }.reduce(0.0) { $0 + $1.width }
            nameColumn.width = max(140, clip.width - fixed - gap - 1)
        }
        let tableHeight = headerHeight + CGFloat(visibleRowCount) * topTable.rowHeight
        if abs(topTable.frame.width - clip.width) > 0.5 || abs(topTable.frame.height - tableHeight) > 0.5 {
            topTable.setFrameSize(NSSize(width: clip.width, height: tableHeight))
        }
    }

    init() { super.init(title: "系统概要") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
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
        cpuGauge.applyTheme()
        tempGauge.applyTheme()
        gpuGauge.applyTheme()
        memoryCard.applyTheme()
        smallCards.forEach { $0.applyTheme() }
        overviewTitle.textColor = Theme.shared.textSecondary
        overviewValue.textColor = Theme.shared.color(.cpu)
        overviewFooter.textColor = Theme.shared.textSecondary
        tableTitle.textColor = Theme.shared.textPrimary
        tableCountLabel.textColor = Theme.shared.textSecondary
        overviewChart.needsDisplay = true
        topTable.reloadData()
    }

    // MARK: - 布局

    private func buildLayout() {
        // 行 1：仪表 | CPU 概览 | Top 进程
        let gaugeStack = NSStackView(views: [cpuGauge, tempGauge, gpuGauge])
        gaugeStack.orientation = .horizontal
        gaugeStack.spacing = 6
        gaugeStack.distribution = .fillEqually
        gaugeStack.translatesAutoresizingMaskIntoConstraints = false

        let overviewPanel = PanelCardContainer()
        overviewTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        overviewTitle.translatesAutoresizingMaskIntoConstraints = false
        overviewValue.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        overviewValue.translatesAutoresizingMaskIntoConstraints = false
        overviewFooter.font = .systemFont(ofSize: 11)
        overviewFooter.translatesAutoresizingMaskIntoConstraints = false
        overviewChart.translatesAutoresizingMaskIntoConstraints = false
        // 双轴：左轴利用率 %，右轴温度 °C（温度按 110°C 满量程映射到同一绘图区）
        overviewChart.leftAxisLabels = [(1, "100%"), (0.5, "50%"), (0, "0%")]
        overviewChart.rightAxisLabels = [(90.0 / 110.0, "90°C"), (60.0 / 110.0, "60°C"), (30.0 / 110.0, "30°C")]
        overviewPanel.addSubview(overviewTitle)
        overviewPanel.addSubview(overviewValue)
        overviewPanel.addSubview(overviewChart)
        overviewPanel.addSubview(overviewFooter)
        overviewPanel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            overviewTitle.topAnchor.constraint(equalTo: overviewPanel.topAnchor, constant: 8),
            overviewTitle.leadingAnchor.constraint(equalTo: overviewPanel.leadingAnchor, constant: 10),
            overviewValue.centerYAnchor.constraint(equalTo: overviewTitle.centerYAnchor),
            overviewValue.trailingAnchor.constraint(equalTo: overviewPanel.trailingAnchor, constant: -10),
            overviewChart.topAnchor.constraint(equalTo: overviewTitle.bottomAnchor, constant: 4),
            overviewChart.leadingAnchor.constraint(equalTo: overviewPanel.leadingAnchor, constant: 10),
            overviewChart.trailingAnchor.constraint(equalTo: overviewPanel.trailingAnchor, constant: -10),
            overviewChart.bottomAnchor.constraint(equalTo: overviewFooter.topAnchor, constant: -4),
            overviewFooter.leadingAnchor.constraint(equalTo: overviewPanel.leadingAnchor, constant: 10),
            overviewFooter.bottomAnchor.constraint(equalTo: overviewPanel.bottomAnchor, constant: -6),
            overviewFooter.trailingAnchor.constraint(lessThanOrEqualTo: overviewPanel.trailingAnchor, constant: -10),
        ])

        // Top 进程表
        let tablePanel = PanelCardContainer()
        tablePanel.translatesAutoresizingMaskIntoConstraints = false
        tableTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        tableTitle.translatesAutoresizingMaskIntoConstraints = false
        tableCountLabel.font = .systemFont(ofSize: 11)
        tableCountLabel.alignment = .right
        tableCountLabel.translatesAutoresizingMaskIntoConstraints = false
        tablePanel.addSubview(tableTitle)
        tablePanel.addSubview(tableCountLabel)

        let columns: [(String, String, CGFloat, NSTextAlignment)] = [
            // 列宽按最宽内容实测（monospacedDigit 13pt）：PID 7 位 57pt、CPU "100.0%" 49pt、
            // 内存 "999.9 MB"/"999.99 GB" ≤67pt；名称列吃掉剩余宽度
            ("pid", "PID", 67, .right),
            ("name", "名称", 140, .left),
            ("cpu", "CPU", 59, .right),
            ("memory", "内存", 77, .right),
        ]
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableColumn.minWidth = column.2
            topTable.addTableColumn(tableColumn)
        }
        topTable.headerView = NSTableHeaderView()
        topTable.rowHeight = 23
        topTable.intercellSpacing = NSSize(width: 0, height: 0)
        topTable.dataSource = self
        topTable.delegate = self
        topTable.style = .fullWidth
        topTable.columnAutoresizingStyle = .noColumnAutoresizing
        topTable.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = topTable
        // TOP N 按可视高度排满即止，不需要滚动条
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        tablePanel.addSubview(scroll)

        NSLayoutConstraint.activate([
            tableTitle.topAnchor.constraint(equalTo: tablePanel.topAnchor, constant: 8),
            tableTitle.leadingAnchor.constraint(equalTo: tablePanel.leadingAnchor, constant: 10),
            tableCountLabel.centerYAnchor.constraint(equalTo: tableTitle.centerYAnchor),
            tableCountLabel.trailingAnchor.constraint(equalTo: tablePanel.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: tableTitle.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: tablePanel.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: tablePanel.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: tablePanel.bottomAnchor, constant: -6),
        ])

        let row1 = NSStackView(views: [gaugeStack, overviewPanel, tablePanel])
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.translatesAutoresizingMaskIntoConstraints = false
        row1.setContentHuggingPriority(.defaultLow, for: .vertical)
        gaugeStack.widthAnchor.constraint(equalToConstant: 168).isActive = true
        tablePanel.widthAnchor.constraint(equalToConstant: 416).isActive = true

        // 行 2：内存
        memoryCard.translatesAutoresizingMaskIntoConstraints = false

        // 行 3：小面板
        let row3 = NSStackView(views: smallCards)
        row3.orientation = .horizontal
        row3.spacing = 8
        row3.distribution = .fillEqually
        row3.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [row1, memoryCard, row3])
        rootStack.orientation = .vertical
        rootStack.spacing = 8
        rootStack.alignment = .width
        rootStack.distribution = .fill
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            row3.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])

        // 三段高度按 5:3:2 分配：上半部（仪表/概览/TOP N） : 内存 : 小卡片
        let row1Ratio = row1.heightAnchor.constraint(equalTo: row3.heightAnchor, multiplier: 2.5)
        row1Ratio.priority = NSLayoutConstraint.Priority(999)
        row1Ratio.isActive = true
        let memoryRatio = memoryCard.heightAnchor.constraint(equalTo: row3.heightAnchor, multiplier: 1.5)
        memoryRatio.priority = NSLayoutConstraint.Priority(999)
        memoryRatio.isActive = true
    }

    // MARK: - 数据刷新

    @objc private func samplerUpdated() {
        guard isVisiblePanel else { return }
        sampleCounter += 1
        // Top 表只剩可视的 N 行，reloadData 代价低：跟随 1 Hz 采样全量刷新
        refresh()
    }

    private func refresh() {
        fitTableSize()
        let history = Sampler.shared.historySnapshot
        let system = Sampler.shared.system
        let iokit = Sampler.shared.iokit
        let network = Sampler.shared.network
        let processes = Sampler.shared.processes

        let cpu = system?.cpuTotal ?? 0
        let temperature = iokit?.temperature
        let gpu = iokit?.gpuUtilization

        cpuGauge.update(value: Formats.percent(cpu), ratio: cpu / 100, subtitle: "\(StaticInfo.logicalCores) 核")
        tempGauge.update(
            value: temperature.map { String(format: "%.1f °C", $0) } ?? "不可用",
            ratio: (temperature ?? 0) / 110,
            subtitle: "SMC"
        )
        gpuGauge.update(
            value: gpu.map { Formats.percent($0) } ?? "不可用",
            ratio: (gpu ?? 0) / 100,
            subtitle: "核显"
        )

        overviewValue.stringValue = Formats.percent(cpu)
        overviewFooter.stringValue = "内核 \(Formats.percent(system?.kernelPercent ?? 0)) · \(StaticInfo.logicalCores) 逻辑处理器"
        overviewChart.yMin = 0
        overviewChart.yMax = 100
        let temperatureScaled = history.temperature.map { $0 / 110.0 * 100.0 }
        overviewChart.series = [
            .init(values: history.cpuTotal, color: Theme.shared.color(.cpu), fill: true),
            .init(values: temperatureScaled, color: Theme.shared.color(.thermal)),
            .init(values: history.kernel, color: NSColor(srgbRed: 0.95, green: 0.35, blue: 0.35, alpha: 1)),
        ]

        // Top CPU 表：按可视高度截取 TOP N，排满即止、不滚动
        let top = processes
            .filter { $0.pid != getpid() }
            .sorted { $0.cpuPercent > $1.cpuPercent }
        topProcesses = visibleRowCount > 0 ? Array(top.prefix(visibleRowCount)) : top
        tableCountLabel.stringValue = "共 \(processes.count) 个"
        topTable.reloadData()

        // 内存
        let total = StaticInfo.memorySize
        let used = system?.memoryUsed ?? 0
        memoryCard.update(
            used: used,
            total: total,
            available: system?.memoryAvailable ?? 0,
            cached: system?.memoryCached ?? 0,
            swapUsed: system?.swapUsed ?? 0,
            history: history.memoryUsed
        )

        // 小面板：磁盘/网络主数值为读+写（下+上）合计，副标题分别标注两个方向（对标 TMOG）
        let diskRead = iokit?.diskReadPerSecond ?? 0
        let diskWrite = iokit?.diskWritePerSecond ?? 0
        smallCards[0].update(
            value: Formats.rate(diskRead + diskWrite),
            subtitle: "读 \(Formats.rate(diskRead)) · 写 \(Formats.rate(diskWrite))",
            ratio: min(max(diskRead, diskWrite) / (200 * 1_048_576.0), 1)
        )
        let netIn = network?.bytesInPerSecond ?? 0
        let netOut = network?.bytesOutPerSecond ?? 0
        smallCards[1].update(
            value: Formats.rate(netIn + netOut),
            subtitle: "下行 \(Formats.rate(netIn)) · 上行 \(Formats.rate(netOut))",
            ratio: min(max(netIn, netOut) / 1_048_576.0, 1)
        )
        smallCards[2].update(
            value: gpu.map { Formats.percent($0) } ?? "不可用",
            subtitle: IOKitSampler.gpuModel,
            ratio: (gpu ?? 0) / 100
        )
        // 系统压力：热压力等级（对标 TMOG Thermals）+ 内存压力 + 温度
        let thermalState = Foundation.ProcessInfo.processInfo.thermalState
        smallCards[3].update(
            value: temperature.map { String(format: "%.1f °C", $0) } ?? thermalText(thermalState),
            subtitle: "内存压力 \(pressureText(system?.memoryPressure ?? -1)) · 热 \(thermalText(thermalState))",
            ratio: temperature.map { min($0 / 110, 1) } ?? thermalRatio(thermalState)
        )
    }

    private func thermalText(_ state: Foundation.ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "正常"
        case .fair: return "尚可"
        case .serious: return "较高"
        case .critical: return "严重"
        @unknown default: return "未知"
        }
    }

    private func thermalRatio(_ state: Foundation.ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal: return 0
        case .fair: return 0.34
        case .serious: return 0.67
        case .critical: return 1
        @unknown default: return 0
        }
    }

    private func pressureText(_ level: Int32) -> String {
        switch level {
        case 1: return "正常"
        case 2: return "警告"
        case 4: return "严重"
        default: return "不可用"
        }
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        topProcesses.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < topProcesses.count, let tableColumn else { return nil }
        let process = topProcesses[row]
        let theme = Theme.shared

        let identifier = NSUserInterfaceItemIdentifier("summary-" + tableColumn.identifier.rawValue)
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TextCellView) ?? TextCellView()
        cell.identifier = identifier

        switch tableColumn.identifier.rawValue {
        case "pid":
            cell.update(text: "\(process.pid)", alignment: .right, color: theme.textSecondary)
        case "name":
            cell.update(text: process.name, alignment: .left, color: theme.textPrimary)
        case "cpu":
            let color = process.cpuPercent >= 0.05 ? theme.color(.cpu) : theme.textSecondary
            cell.update(text: Formats.percent(process.cpuPercent), alignment: .right, color: color)
        case "memory":
            cell.update(text: Formats.memory(process.footprint), alignment: .right, color: theme.textPrimary)
        default:
            return nil
        }
        return cell
    }
}

// MARK: - 卡片容器

final class PanelCardContainer: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func applyTheme() {
        layer?.backgroundColor = Theme.shared.cardBackground.cgColor
        layer?.borderColor = Theme.shared.separator.withAlphaComponent(0.6).cgColor
    }
}

// MARK: - 垂直仪表卡片

final class GaugeCardView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedBarView()
    private let kind: SubsystemKind

    init(title: String, kind: SubsystemKind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        bar.orientation = .vertical
        bar.segmentCount = 26
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.lineBreakMode = .byTruncatingTail
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            bar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            bar.centerXAnchor.constraint(equalTo: centerXAnchor),
            bar.widthAnchor.constraint(equalToConstant: 22),
            bar.bottomAnchor.constraint(equalTo: valueLabel.topAnchor, constant: -4),

            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),

            subtitleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(value: String, ratio: Double, subtitle: String, updateLabels: Bool = true) {
        if updateLabels {
            valueLabel.stringValue = value
            subtitleLabel.stringValue = subtitle
        }
        bar.ratio = min(max(ratio, 0), 1)
    }

    func applyTheme() {
        let theme = Theme.shared
        let color = theme.color(kind)
        layer?.backgroundColor = theme.cardBackground.cgColor
        layer?.borderColor = color.withAlphaComponent(0.35).cgColor
        titleLabel.textColor = color
        valueLabel.textColor = color
        subtitleLabel.textColor = theme.textSecondary
        bar.color = color
    }
}

// MARK: - 内存利用率卡

final class MemorySummaryCardView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "内存利用率")
    private let usedLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedBarView()
    private let percentLabel = NSTextField(labelWithString: "")
    private let chart = ChartView()
    private let footerLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        usedLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        usedLabel.alignment = .right
        usedLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(usedLabel)

        bar.orientation = .vertical
        bar.segmentCount = 26
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(percentLabel)

        chart.showsGrid = true
        chart.yMin = 0
        chart.yMax = 1
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            usedLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            usedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            bar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            bar.widthAnchor.constraint(equalToConstant: 28),
            bar.bottomAnchor.constraint(equalTo: percentLabel.topAnchor, constant: -3),

            percentLabel.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            percentLabel.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -4),

            chart.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            chart.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chart.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -4),

            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(used: UInt64, total: UInt64, available: UInt64, cached: UInt64, swapUsed: UInt64, history: [Double], updateLabels: Bool = true) {
        let ratio = total > 0 ? Double(used) / Double(total) : 0
        if updateLabels {
            usedLabel.stringValue = "\(Formats.memory(used)) / \(Formats.memory(total))"
            percentLabel.stringValue = Formats.percent(ratio * 100)
            footerLabel.stringValue = "可用 \(Formats.memory(available))   缓存 \(Formats.memory(cached))   交换 \(Formats.memory(swapUsed))"
        }
        bar.ratio = ratio
        chart.yMax = Double(max(total, 1))
        chart.series = [.init(values: history, color: Theme.shared.color(.memory), fill: true)]
    }

    func applyTheme() {
        let theme = Theme.shared
        let color = theme.color(.memory)
        layer?.backgroundColor = theme.cardBackground.cgColor
        layer?.borderColor = color.withAlphaComponent(0.35).cgColor
        titleLabel.textColor = theme.textPrimary
        usedLabel.textColor = theme.textPrimary
        percentLabel.textColor = color
        footerLabel.textColor = theme.textSecondary
        bar.color = color
        chart.needsDisplay = true
    }
}

// MARK: - 小面板卡片

final class SmallStatCardView: NSView, ThemeAware {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedBarView()
    private let kind: SubsystemKind

    init(title: String, symbol: String, kind: SubsystemKind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        // TMOG 式细密刻度条：细段 × 全宽，占满卡片底部
        bar.segmentCount = 40

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -6),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            // 卡片随 5:3:2 拉高时，多余空间落在副标题与刻度条之间
            bar.topAnchor.constraint(greaterThanOrEqualTo: subtitleLabel.bottomAnchor, constant: 5),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            bar.heightAnchor.constraint(equalToConstant: 12),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(value: String, subtitle: String, ratio: Double, updateLabels: Bool = true) {
        if updateLabels {
            valueLabel.stringValue = value
            subtitleLabel.stringValue = subtitle
        }
        bar.ratio = min(max(ratio, 0), 1)
    }

    func applyTheme() {
        let theme = Theme.shared
        let color = theme.color(kind)
        layer?.backgroundColor = theme.cardBackground.cgColor
        layer?.borderColor = color.withAlphaComponent(0.35).cgColor
        iconView.contentTintColor = color
        titleLabel.textColor = color
        valueLabel.textColor = color
        subtitleLabel.textColor = theme.textSecondary
        bar.color = color
    }
}
