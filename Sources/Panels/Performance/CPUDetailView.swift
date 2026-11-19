import AppKit

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

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
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
    private let utilizationBar = SegmentedBarView()
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

        titleLabel.font = .systemFont(ofSize: 32, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        utilizationBar.orientation = .horizontal
        utilizationBar.segmentCount = 60
        utilizationBar.color = color
        utilizationBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(utilizationBar)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        sectionTitle.font = .systemFont(ofSize: 13)
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionTitle)

        coreGrid.orientation = .vertical
        coreGrid.spacing = 8
        coreGrid.distribution = .fillEqually
        coreGrid.alignment = .width
        coreGrid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coreGrid)

        historyTitle.font = .systemFont(ofSize: 13)
        historyTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(historyTitle)

        stats.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stats)

        uptimeTitle.font = .systemFont(ofSize: 13)
        uptimeTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(uptimeTitle)

        uptimeValue.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
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

            utilizationBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            utilizationBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            utilizationBar.heightAnchor.constraint(equalToConstant: 14),

            valueLabel.leadingAnchor.constraint(equalTo: utilizationBar.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: utilizationBar.centerYAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: utilizationBar.bottomAnchor, constant: 6),
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
        utilizationBar.ratio = min(max((system?.cpuTotal ?? 0) / 100, 0), 1)
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
        utilizationBar.color = color
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
