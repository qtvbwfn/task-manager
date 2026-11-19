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
        NSLayoutConstraint.activate([
            newGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            newGrid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
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
    private let chart = ChartView()
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        chart.showsGrid = true
        chart.showsCursor = false
        chart.glow = false
        chart.yMin = 0
        chart.yMax = 100
        chart.gridDivisions = 2
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 1),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(index: Int, values: [Double]) {
        label.stringValue = "CPU \(index)"
        chart.series = [.init(values: values, color: color)]
    }

    func applyTheme() {
        label.textColor = Theme.shared.textSecondary
        chart.needsDisplay = true
    }
}

// MARK: - CPU 详情

final class CPUDetailView: NSView, ThemeAware {
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let coreBar = CoreLoadBarView()
    private let coreTitle = NSTextField(labelWithString: "各逻辑核利用率")
    private var coreCells: [PerCoreCellView] = []
    private let coreGrid = NSStackView()
    private let metrics = MetricGridView()
    private let kvMetrics = MetricGridView()
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)

        valueLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        coreBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coreBar)

        coreTitle.font = .systemFont(ofSize: 11)
        coreTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coreTitle)

        coreGrid.orientation = .vertical
        coreGrid.spacing = 4
        coreGrid.alignment = .width
        coreGrid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coreGrid)

        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        kvMetrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(kvMetrics)

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            subtitleLabel.firstBaselineAnchor.constraint(equalTo: valueLabel.firstBaselineAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 10),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            coreBar.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 6),
            coreBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            coreBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            coreBar.heightAnchor.constraint(equalToConstant: 10),

            coreTitle.topAnchor.constraint(equalTo: coreBar.bottomAnchor, constant: 8),
            coreTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            coreGrid.topAnchor.constraint(equalTo: coreTitle.bottomAnchor, constant: 4),
            coreGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            coreGrid.trailingAnchor.constraint(equalTo: trailingAnchor),

            metrics.topAnchor.constraint(equalTo: coreGrid.bottomAnchor, constant: 10),
            metrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor),

            kvMetrics.topAnchor.constraint(equalTo: metrics.bottomAnchor, constant: 8),
            kvMetrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            kvMetrics.trailingAnchor.constraint(equalTo: trailingAnchor),
            kvMetrics.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])

        buildCoreGrid(coreCount: StaticInfo.logicalCores)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildCoreGrid(coreCount: Int) {
        coreGrid.arrangedSubviews.forEach {
            coreGrid.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        coreCells.removeAll()

        let columns = 4
        var row: [PerCoreCellView] = []
        for index in 0..<coreCount {
            let cell = PerCoreCellView(color: color)
            cell.translatesAutoresizingMaskIntoConstraints = false
            cell.heightAnchor.constraint(equalToConstant: 56).isActive = true
            cell.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
            coreCells.append(cell)
            row.append(cell)
            if row.count == columns || index == coreCount - 1 {
                let rowStack = NSStackView(views: row)
                rowStack.orientation = .horizontal
                rowStack.spacing = 10
                rowStack.distribution = .fillEqually
                coreGrid.addArrangedSubview(rowStack)
                row = []
            }
        }
    }

    func update(history: HistorySnapshot, system: SystemSnapshot?, processes: [ProcessInfo], threads: Int) {
        valueLabel.stringValue = Formats.percent(system?.cpuTotal ?? 0)
        valueLabel.textColor = color
        subtitleLabel.stringValue = "\(StaticInfo.logicalCores) 逻辑处理器 · 内核 \(Formats.percent(system?.kernelPercent ?? 0))"

        let coreValues = system?.perCore ?? []
        coreBar.values = coreValues
        if coreCells.count != history.perCore.count {
            buildCoreGrid(coreCount: history.perCore.count)
        }
        for (index, cell) in coreCells.enumerated() {
            let values = index < history.perCore.count ? history.perCore[index] : []
            cell.update(index: index, values: values)
        }

        metrics.configure(items: [
            ("利用率", Formats.percent(system?.cpuTotal ?? 0)),
            ("进程数", "\(processes.count)"),
            ("线程数", "\(threads)"),
            ("运行时长", Formats.uptime(system?.uptime ?? 0)),
        ])
        kvMetrics.configure(items: [
            ("型号", StaticInfo.cpuBrand),
            ("物理核", "\(StaticInfo.physicalCores)"),
            ("逻辑核", "\(StaticInfo.logicalCores)"),
            ("L2 缓存", StaticInfo.cacheSize(StaticInfo.l2Cache)),
            ("L3 缓存", StaticInfo.cacheSize(StaticInfo.l3Cache)),
            ("基准频率", StaticInfo.frequency(StaticInfo.baseFrequency)),
        ], columns: 3)
    }

    func applyTheme() {
        valueLabel.textColor = color
        subtitleLabel.textColor = Theme.shared.textSecondary
        coreTitle.textColor = Theme.shared.textSecondary
        coreCells.forEach { $0.applyTheme() }
        metrics.applyTheme()
        kvMetrics.applyTheme()
    }
}

// MARK: - 内存详情

final class MemoryDetailView: NSView, ThemeAware {
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedBarView()
    private let chart = ChartView()
    private let chartTitle = NSTextField(labelWithString: "内存利用率")
    private let metrics = MetricGridView()
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)

        valueLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 12)
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
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            subtitleLabel.firstBaselineAnchor.constraint(equalTo: valueLabel.firstBaselineAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 10),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            bar.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 10),

            chartTitle.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
            chartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            chart.topAnchor.constraint(equalTo: chartTitle.bottomAnchor, constant: 4),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(equalToConstant: 144),

            metrics.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 10),
            metrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor),
            metrics.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
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
        ])
    }

    func applyTheme() {
        valueLabel.textColor = color
        subtitleLabel.textColor = Theme.shared.textSecondary
        chartTitle.textColor = Theme.shared.textSecondary
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

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        chartTitle.font = .systemFont(ofSize: 11)
        chartTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartTitle)

        chart.showsGrid = true
        chart.yMin = 0
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            subtitleLabel.firstBaselineAnchor.constraint(equalTo: valueLabel.firstBaselineAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 10),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            chartTitle.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 10),
            chartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            chart.topAnchor.constraint(equalTo: chartTitle.bottomAnchor, constant: 4),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(equalToConstant: 144),

            metrics.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 10),
            metrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor),
            metrics.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
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