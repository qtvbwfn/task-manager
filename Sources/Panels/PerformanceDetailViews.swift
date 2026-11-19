import AppKit

// MARK: - 指标网格

final class MetricGridView: NSView {
    private var grid: NSGridView?
    private var valueLabels: [(label: NSTextField, value: NSTextField)] = []

    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(items: [(String, String)], columns: Int = 4) {
        grid?.removeFromSuperview()
        valueLabels.removeAll()

        var rows: [[NSView]] = []
        var currentRow: [NSView] = []

        for (label, value) in items {
            let labelView = NSTextField(labelWithString: label)
            labelView.font = .systemFont(ofSize: 11)
            labelView.textColor = Theme.shared.textSecondary
            labelView.setContentHuggingPriority(.required, for: .horizontal)

            let valueView = NSTextField(labelWithString: value)
            valueView.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
            valueView.textColor = Theme.shared.textPrimary
            valueView.lineBreakMode = .byTruncatingTail
            valueView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let column = NSStackView(views: [labelView, valueView])
            column.orientation = .vertical
            column.spacing = 1
            column.alignment = .leading
            currentRow.append(column)
            valueLabels.append((labelView, valueView))

            if currentRow.count == columns {
                rows.append(currentRow)
                currentRow = []
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        let newGrid = NSGridView(views: rows)
        newGrid.rowSpacing = 8
        newGrid.columnSpacing = 18
        newGrid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newGrid)
        // 列摊满整宽：多余宽度均分到所有 .fill 列，避免数据挤在左侧（对标 TMOG）
        for index in 0..<newGrid.numberOfColumns { newGrid.column(at: index).xPlacement = .fill }
        NSLayoutConstraint.activate([
            newGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            newGrid.trailingAnchor.constraint(equalTo: trailingAnchor),
            newGrid.topAnchor.constraint(equalTo: topAnchor),
            newGrid.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        grid = newGrid
    }

    func applyTheme() {
        for pair in valueLabels {
            pair.label.textColor = Theme.shared.textSecondary
            pair.value.textColor = Theme.shared.textPrimary
        }
    }
}

// MARK: - 等宽指标列（滚动历史）

final class StatColumnsView: NSView, ThemeAware {
    private let stack = NSStackView()
    private var cells: [(label: NSTextField, value: NSTextField)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(items: [(String, String)]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        cells.removeAll()

        for (title, value) in items {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11)
            label.textColor = Theme.shared.textSecondary

            let valueLabel = NSTextField(labelWithString: value)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
            valueLabel.textColor = Theme.shared.textPrimary
            valueLabel.lineBreakMode = .byTruncatingTail
            valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let column = NSStackView(views: [label, valueLabel])
            column.orientation = .vertical
            column.spacing = 2
            column.alignment = .leading
            stack.addArrangedSubview(column)
            cells.append((label, valueLabel))
        }
    }

    func update(values: [String]) {
        guard values.count == cells.count else { return }
        for (index, value) in values.enumerated() {
            cells[index].value.stringValue = value
        }
    }

    func applyTheme() {
        for cell in cells {
            cell.label.textColor = Theme.shared.textSecondary
            cell.value.textColor = Theme.shared.textPrimary
        }
    }
}

// MARK: - 双栏键值表（CPU 规格）

final class KeyValueColumnsView: NSView, ThemeAware {
    private let stack = NSStackView()
    private var pairs: [(label: NSTextField, value: NSTextField)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 每栏一组 (标签, 值)，两栏并排且行高固定，保证左右两栏逐行对齐
    func configure(columns: [[(String, String)]]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        pairs.removeAll()

        for items in columns where !items.isEmpty {
            var rows: [[NSView]] = []
            for (title, value) in items {
                let label = NSTextField(labelWithString: title)
                label.font = .systemFont(ofSize: 11)
                label.textColor = Theme.shared.textSecondary
                label.setContentHuggingPriority(.required, for: .horizontal)

                let valueLabel = NSTextField(labelWithString: value)
                valueLabel.font = .systemFont(ofSize: 11, weight: .medium)
                valueLabel.textColor = Theme.shared.textPrimary
                valueLabel.lineBreakMode = .byTruncatingTail
                valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                rows.append([label, valueLabel])
                pairs.append((label, valueLabel))
            }

            let grid = NSGridView(views: rows)
            grid.rowSpacing = 5
            for index in 0..<rows.count {
                grid.row(at: index).height = 17
            }
            grid.columnSpacing = 10
            grid.column(at: 0).width = 78
            grid.column(at: 0).xPlacement = .leading
            stack.addArrangedSubview(grid)
        }
    }

    func applyTheme() {
        for pair in pairs {
            pair.label.textColor = Theme.shared.textSecondary
            pair.value.textColor = Theme.shared.textPrimary
        }
    }
}

// MARK: - 逐核负载条

final class CoreLoadBarView: NSView {
    var values: [Double] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, !values.isEmpty else { return }
        let count = values.count
        let gap: CGFloat = 3
        let width = (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count)
        let height = bounds.height

        for (index, value) in values.enumerated() {
            let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            let t = min(max(value / 100.0, 0), 1)
            let color = Self.loadColor(t)
            context.setFillColor(color.cgColor)
            context.addPath(path)
            context.fillPath()
        }
    }

    static func loadColor(_ t: Double) -> NSColor {
        // 绿 → 黄 → 红
        if t < 0.5 {
            let k = t / 0.5
            return NSColor(srgbRed: 0.2 + 0.75 * CGFloat(k), green: 0.75 - 0.15 * CGFloat(k), blue: 0.2, alpha: 1)
        }
        let k = (t - 0.5) / 0.5
        return NSColor(srgbRed: 0.95, green: 0.6 - 0.45 * CGFloat(k), blue: 0.2, alpha: 1)
    }
}

// MARK: - 逐核迷你图单元

final class PerCoreCellView: NSView, ThemeAware {
    private let label = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let chart = ChartView()
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        chart.showsGrid = true
        chart.showsCursor = true
        chart.glow = true
        chart.yMin = 0
        chart.yMax = 100
        chart.gridDivisions = 4
        // 逐核图按当前点数铺满宽度，启动即有 TMOG 式的满幅曲线
        chart.sampleCapacity = 0
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),

            valueLabel.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),

            chart.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(index: Int, values: [Double], current: Double) {
        label.stringValue = "CPU \(index)"
        valueLabel.stringValue = Formats.percent(current)
        chart.series = [.init(values: values, color: color)]
    }

    func applyTheme() {
        let theme = Theme.shared
        label.textColor = theme.textSecondary
        valueLabel.textColor = theme.textSecondary
        layer?.backgroundColor = theme.cardBackground.withAlphaComponent(0.45).cgColor
        layer?.borderColor = theme.separator.withAlphaComponent(0.7).cgColor
        chart.needsDisplay = true
    }
}

// MARK: - CPU 详情

final class CPUDetailView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "CPU")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let coreBar = CoreLoadBarView()
    private let sectionTitle = NSTextField(labelWithString: "% 各逻辑处理器使用率")
    private var coreCells: [PerCoreCellView] = []
    private let coreGrid = NSStackView()
    private let historyTitle = NSTextField(labelWithString: "滚动历史")
    private let stats = StatColumnsView()
    private let uptimeTitle = NSTextField(labelWithString: "运行时间")
    private let uptimeValue = NSTextField(labelWithString: "—")
    private let kv = KeyValueColumnsView()
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 26, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        coreBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coreBar)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        sectionTitle.font = .systemFont(ofSize: 11)
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionTitle)

        coreGrid.orientation = .vertical
        coreGrid.spacing = 8
        coreGrid.distribution = .fillEqually
        coreGrid.alignment = .width
        coreGrid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coreGrid)

        historyTitle.font = .systemFont(ofSize: 11)
        historyTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(historyTitle)

        stats.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stats)

        uptimeTitle.font = .systemFont(ofSize: 11)
        uptimeTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(uptimeTitle)

        uptimeValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        uptimeValue.lineBreakMode = .byTruncatingTail
        uptimeValue.translatesAutoresizingMaskIntoConstraints = false
        addSubview(uptimeValue)

        kv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(kv)

        let kvBottom = kv.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        kvBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            coreBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            coreBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            coreBar.heightAnchor.constraint(equalToConstant: 12),

            valueLabel.leadingAnchor.constraint(equalTo: coreBar.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: coreBar.centerYAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: coreBar.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            sectionTitle.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            sectionTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            coreGrid.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 6),
            coreGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            coreGrid.trailingAnchor.constraint(equalTo: trailingAnchor),
            coreGrid.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            historyTitle.topAnchor.constraint(equalTo: coreGrid.bottomAnchor, constant: 12),
            historyTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            stats.topAnchor.constraint(equalTo: historyTitle.bottomAnchor, constant: 4),
            stats.leadingAnchor.constraint(equalTo: leadingAnchor),
            stats.trailingAnchor.constraint(equalTo: trailingAnchor),

            uptimeTitle.topAnchor.constraint(equalTo: stats.bottomAnchor, constant: 7),
            uptimeTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            uptimeValue.topAnchor.constraint(equalTo: uptimeTitle.bottomAnchor, constant: 2),
            uptimeValue.leadingAnchor.constraint(equalTo: leadingAnchor),
            uptimeValue.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            kv.topAnchor.constraint(equalTo: uptimeValue.bottomAnchor, constant: 12),
            kv.leadingAnchor.constraint(equalTo: leadingAnchor),
            kv.trailingAnchor.constraint(equalTo: trailingAnchor),
            kvBottom,
        ])

        buildCoreGrid(coreCount: StaticInfo.logicalCores)
        stats.configure(items: [
            ("使用率", "—"),
            ("速度", "—"),
            ("进程", "—"),
            ("线程", "—"),
        ])
        kv.configure(columns: [
            [
                ("基准频率", StaticInfo.frequency(StaticInfo.baseFrequency)),
                ("物理核心", "\(StaticInfo.physicalCores)"),
                ("一级缓存", StaticInfo.cacheSize(StaticInfo.l1Cache)),
                ("二级缓存", StaticInfo.cacheSize(StaticInfo.l2Cache)),
                ("三级缓存", StaticInfo.cacheSize(StaticInfo.l3Cache)),
                ("虚拟化", StaticInfo.hypervisorSupported ? "支持" : "不支持"),
            ],
            [
                ("套接字", "\(StaticInfo.packages)"),
                ("逻辑处理器", "\(StaticInfo.logicalCores)"),
                ("架构", StaticInfo.machine),
                ("型号标识", StaticInfo.model),
                ("系统版本", StaticInfo.osVersion),
                ("虚拟机", StaticInfo.runningInVM ? "是" : "否"),
            ],
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildCoreGrid(coreCount: Int) {
        coreGrid.arrangedSubviews.forEach {
            coreGrid.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        coreCells.removeAll()
        guard coreCount > 0 else { return }

        let columns = min(4, coreCount)
        var row: [PerCoreCellView] = []
        for index in 0..<coreCount {
            let cell = PerCoreCellView(color: color)
            cell.translatesAutoresizingMaskIntoConstraints = false
            coreCells.append(cell)
            row.append(cell)
            if row.count == columns || index == coreCount - 1 {
                let rowStack = NSStackView(views: row)
                rowStack.orientation = .horizontal
                rowStack.spacing = 8
                rowStack.distribution = .fillEqually
                rowStack.alignment = .centerY
                coreGrid.addArrangedSubview(rowStack)
                for cell in row {
                    cell.heightAnchor.constraint(equalTo: rowStack.heightAnchor).isActive = true
                }
                row = []
            }
        }
    }

    func update(history: HistorySnapshot, system: SystemSnapshot?, processes: [ProcessInfo], threads: Int) {
        valueLabel.stringValue = Formats.percent(system?.cpuTotal ?? 0)
        valueLabel.textColor = color
        subtitleLabel.stringValue = "\(StaticInfo.logicalCores) 逻辑处理器 · 内核 \(Formats.percent(system?.kernelPercent ?? 0)) · \(StaticInfo.cpuBrand)"

        let coreValues = system?.perCore ?? []
        coreBar.values = coreValues
        if !history.perCore.isEmpty && coreCells.count != history.perCore.count {
            buildCoreGrid(coreCount: history.perCore.count)
        }
        for (index, cell) in coreCells.enumerated() {
            let values = index < history.perCore.count ? history.perCore[index] : []
            let current = index < coreValues.count ? coreValues[index] : (values.last ?? 0)
            cell.update(index: index, values: values, current: current)
        }

        stats.update(values: [
            Formats.percent(system?.cpuTotal ?? 0),
            StaticInfo.frequency(StaticInfo.baseFrequency),
            "\(processes.count)",
            "\(threads)",
        ])
        uptimeValue.stringValue = Formats.uptime(system?.uptime ?? 0)
    }

    func applyTheme() {
        let theme = Theme.shared
        titleLabel.textColor = theme.textPrimary
        valueLabel.textColor = color
        subtitleLabel.textColor = theme.textSecondary
        sectionTitle.textColor = theme.textSecondary
        historyTitle.textColor = theme.textSecondary
        uptimeTitle.textColor = theme.textSecondary
        uptimeValue.textColor = theme.textPrimary
        coreCells.forEach { $0.applyTheme() }
        stats.applyTheme()
        kv.applyTheme()
    }
}

// MARK: - 内存详情

final class MemoryDetailView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "内存")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedBarView()
    private let chart = ChartView()
    private let chartTitle = NSTextField(labelWithString: "内存使用率")
    private let metrics = MetricGridView()
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 26, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        bar.orientation = .horizontal
        bar.segmentCount = 30
        bar.color = color
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        chartTitle.font = .systemFont(ofSize: 11)
        chartTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartTitle)

        chart.showsGrid = true
        chart.yMin = 0
        chart.yMax = 1
        chart.sampleCapacity = 0
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        let metricsBottom = metrics.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        metricsBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            bar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 12),

            valueLabel.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            chartTitle.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            chartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            chart.topAnchor.constraint(equalTo: chartTitle.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            metrics.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 14),
            metrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor),
            metricsBottom,
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(history: HistorySnapshot, system: SystemSnapshot?) {
        let total = StaticInfo.memorySize
        let used = system?.memoryUsed ?? 0
        let ratio = total > 0 ? Double(used) / Double(total) : 0

        valueLabel.stringValue = Formats.percent(ratio * 100)
        valueLabel.textColor = color
        subtitleLabel.stringValue = "\(Formats.memory(used)) / \(Formats.memory(total))"
        bar.ratio = ratio
        chart.yMax = Double(total)
        chart.series = [.init(values: history.memoryUsed, color: color, fill: true)]

        metrics.configure(items: [
            ("已用", Formats.memory(used)),
            ("可用", Formats.memory(system?.memoryAvailable ?? 0)),
            ("缓存", Formats.memory(system?.memoryCached ?? 0)),
            ("已压缩", Formats.memory(system?.memoryCompressed ?? 0)),
            ("Wired", Formats.memory(system?.memoryWired ?? 0)),
            ("交换已用", Formats.memory(system?.swapUsed ?? 0)),
            ("交换总量", Formats.memory(system?.swapTotal ?? 0)),
            ("换入", "\(system?.pageIns ?? 0)"),
            ("换出", "\(system?.pageOuts ?? 0)"),
            ("压力", pressureName(system?.memoryPressure ?? -1)),
        ], columns: 5)
    }

    private func pressureName(_ level: Int32) -> String {
        switch level {
        case 1: return "正常"
        case 2: return "警告"
        case 4: return "严重"
        default: return "不可用"
        }
    }

    func applyTheme() {
        let theme = Theme.shared
        titleLabel.textColor = theme.textPrimary
        valueLabel.textColor = color
        subtitleLabel.textColor = theme.textSecondary
        chartTitle.textColor = theme.textSecondary
        bar.color = color
        metrics.applyTheme()
    }
}

// MARK: - 通用图表详情（GPU/磁盘/网络/电源/温度）

final class GenericDetailView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let chart = ChartView()
    private let chartTitle = NSTextField(labelWithString: "")
    private let metrics = MetricGridView()
    private var color: NSColor = .systemBlue
    private var hasSecondSeries = false

    override init(frame: NSRect) {
        super.init(frame: frame)

        titleLabel.font = .systemFont(ofSize: 26, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        chartTitle.font = .systemFont(ofSize: 11)
        chartTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartTitle)

        chart.showsGrid = true
        chart.yMin = 0
        chart.sampleCapacity = 0
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        let metricsBottom = metrics.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        metricsBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            chartTitle.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            chartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            chart.topAnchor.constraint(equalTo: chartTitle.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            metrics.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 14),
            metrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor),
            metricsBottom,
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        title: String,
        value: String,
        subtitle: String,
        chartValues: [Double],
        chartTitle: String,
        color: NSColor,
        metrics items: [(String, String)],
        secondSeries: [Double]? = nil,
        secondColor: NSColor? = nil
    ) {
        self.color = color
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        valueLabel.textColor = color
        subtitleLabel.stringValue = subtitle
        self.chartTitle.stringValue = chartTitle
        self.chartTitle.textColor = Theme.shared.textSecondary

        var series: [ChartView.Series] = [.init(values: chartValues, color: color, fill: true)]
        if let secondSeries, let secondColor {
            series.append(.init(values: secondSeries, color: secondColor))
            hasSecondSeries = true
        } else {
            hasSecondSeries = false
        }
        chart.series = series
        chart.yMax = Self.niceMax(values: chartValues + (secondSeries ?? []))
        metrics.configure(items: items)
    }

    private static func niceMax(values: [Double]) -> Double {
        let maxValue = values.max() ?? 1
        guard maxValue > 0 else { return 1 }
        let magnitude = pow(10, Double(Int(log10(maxValue))))
        return ceil(maxValue / magnitude) * magnitude
    }

    func applyTheme() {
        titleLabel.textColor = Theme.shared.textSecondary
        valueLabel.textColor = color
        subtitleLabel.textColor = Theme.shared.textSecondary
        chartTitle.textColor = Theme.shared.textSecondary
        metrics.applyTheme()
        chart.needsDisplay = true
    }
}

// MARK: - 磁盘详情（对标 TMOG：型号大标题 + 活跃时间分段仪表 + 双图 + 指标网格，无跳转按钮）

final class DiskDetailView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let gauge = SegmentedBarView()
    private let valueLabel = NSTextField(labelWithString: "")
    private let activeChartTitle = NSTextField(labelWithString: "% 活跃时间")
    private let activeChart = ChartView()
    private let activeCaption = NSTextField(labelWithString: "滚动历史")
    private let rateChartTitle = NSTextField(labelWithString: "磁盘传输速率")
    private let rateChart = ChartView()
    private let rateCaption = NSTextField(labelWithString: "滚动历史")
    private let metrics = MetricGridView()
    private var diskColor: NSColor = .systemGreen
    private var writeColor: NSColor = .systemBlue

    override init(frame: NSRect) {
        super.init(frame: frame)

        titleLabel.font = .systemFont(ofSize: 26, weight: .light)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        gauge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gauge)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        for label in [activeChartTitle, rateChartTitle] {
            label.font = .systemFont(ofSize: 11)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        for caption in [activeCaption, rateCaption] {
            caption.font = .systemFont(ofSize: 10)
            caption.translatesAutoresizingMaskIntoConstraints = false
            addSubview(caption)
        }

        for chart in [activeChart, rateChart] {
            chart.showsGrid = true
            chart.yMin = 0
            chart.translatesAutoresizingMaskIntoConstraints = false
            addSubview(chart)
        }

        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        let activeHeight = activeChart.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        let rateHeight = rateChart.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        activeHeight.priority = .defaultHigh
        rateHeight.priority = .defaultHigh
        // 富余高度按参考比例分配（活跃时间图 : 传输速率图 ≈ 1.6:1）
        let chartRatio = activeChart.heightAnchor.constraint(equalTo: rateChart.heightAnchor, multiplier: 1.6)
        chartRatio.priority = .defaultLow

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            gauge.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            gauge.leadingAnchor.constraint(equalTo: leadingAnchor),
            gauge.heightAnchor.constraint(equalToConstant: 14),

            valueLabel.centerYAnchor.constraint(equalTo: gauge.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            gauge.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),

            activeChartTitle.topAnchor.constraint(equalTo: gauge.bottomAnchor, constant: 14),
            activeChartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            activeChart.topAnchor.constraint(equalTo: activeChartTitle.bottomAnchor, constant: 6),
            activeChart.leadingAnchor.constraint(equalTo: leadingAnchor),
            activeChart.trailingAnchor.constraint(equalTo: trailingAnchor),
            activeHeight,
            chartRatio,

            activeCaption.topAnchor.constraint(equalTo: activeChart.bottomAnchor, constant: 4),
            activeCaption.leadingAnchor.constraint(equalTo: leadingAnchor),

            rateChartTitle.topAnchor.constraint(equalTo: activeCaption.bottomAnchor, constant: 12),
            rateChartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            rateChart.topAnchor.constraint(equalTo: rateChartTitle.bottomAnchor, constant: 6),
            rateChart.leadingAnchor.constraint(equalTo: leadingAnchor),
            rateChart.trailingAnchor.constraint(equalTo: trailingAnchor),
            rateHeight,

            rateCaption.topAnchor.constraint(equalTo: rateChart.bottomAnchor, constant: 4),
            rateCaption.leadingAnchor.constraint(equalTo: leadingAnchor),

            metrics.topAnchor.constraint(equalTo: rateCaption.bottomAnchor, constant: 12),
            metrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor),
            metrics.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(identity: DiskIdentity?, iokit: IOKitSample?, history: HistorySnapshot) {
        let theme = Theme.shared
        diskColor = theme.color(.disk)
        writeColor = theme.color(.network)

        titleLabel.stringValue = identity?.model ?? "磁盘"
        subtitleLabel.stringValue = identity.map { "\($0.medium) · \($0.bsdName)" } ?? "不可用"

        let active = iokit?.diskActiveTimePercent ?? 0
        valueLabel.stringValue = Formats.percent(active)
        valueLabel.textColor = diskColor
        gauge.color = diskColor
        gauge.segmentCount = 60
        gauge.ratio = active / 100

        activeChartTitle.textColor = theme.textSecondary
        rateChartTitle.textColor = theme.textSecondary
        activeCaption.textColor = theme.textSecondary
        rateCaption.textColor = theme.textSecondary

        activeChart.series = [.init(values: history.diskActive, color: diskColor, fill: true)]
        activeChart.yMax = Self.niceMax(values: history.diskActive)

        rateChart.series = [
            .init(values: history.diskRead, color: diskColor, fill: true),
            .init(values: history.diskWrite, color: writeColor),
        ]
        rateChart.yMax = Self.niceMax(values: history.diskRead + history.diskWrite)

        var items: [(String, String)] = [
            ("读取速度", iokit.map { Formats.rate($0.diskReadPerSecond) } ?? "不可用"),
            ("写入速度", iokit.map { Formats.rate($0.diskWritePerSecond) } ?? "不可用"),
            ("总读取量", iokit.map { Formats.memory($0.diskTotalReadBytes) } ?? "不可用"),
            ("总写入量", iokit.map { Formats.memory($0.diskTotalWriteBytes) } ?? "不可用"),
            ("活跃时间", iokit.map { Formats.percent($0.diskActiveTimePercent) } ?? "不可用"),
            ("平均响应时间", iokit?.diskAvgResponseMs.map { String(format: "%.1f ms", $0) } ?? "不可用"),
            ("容量", identity.map { $0.size > 0 ? Formats.memory($0.size) : "不可用" } ?? "不可用"),
        ]
        let fs = identity?.fileSystem ?? ""
        items.append(("已格式化", fs.isEmpty ? "不可用" : fs))
        items.append(("系统磁盘", identity.map { $0.isSystemDisk ? "是" : "否" } ?? "不可用"))
        items.append(("类型", identity?.interconnect ?? "不可用"))
        metrics.configure(items: items, columns: 4)
    }

    private static func niceMax(values: [Double]) -> Double {
        let maxValue = values.max() ?? 1
        guard maxValue > 0 else { return 1 }
        let magnitude = pow(10, Double(Int(log10(maxValue))))
        return ceil(maxValue / magnitude) * magnitude
    }

    func applyTheme() {
        let theme = Theme.shared
        titleLabel.textColor = theme.textPrimary
        subtitleLabel.textColor = theme.textSecondary
        valueLabel.textColor = diskColor
        activeChartTitle.textColor = theme.textSecondary
        rateChartTitle.textColor = theme.textSecondary
        activeCaption.textColor = theme.textSecondary
        rateCaption.textColor = theme.textSecondary
        gauge.color = diskColor
        metrics.applyTheme()
        activeChart.needsDisplay = true
        rateChart.needsDisplay = true
    }
}
