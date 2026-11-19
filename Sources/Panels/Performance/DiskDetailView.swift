import AppKit

// MARK: - 磁盘详情（对标 TMOG：型号大标题 + 活跃时间分段仪表 + 双图 + 指标网格；多盘时顶部可切换）

final class DiskDetailView: NSView, ThemeAware {
    private let picker = NSSegmentedControl()
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

    /// 当前选中的盘（bsdName）；nil = 跟随系统盘
    private var selectedBSD: String?
    /// 最近一次 update 的入参：切换磁盘时立即重绘，不必等下一个采样周期
    private var lastUpdate: (identities: [DiskIdentity], iokit: IOKitSample?, history: HistorySnapshot)?
    private var titleTopSingle: NSLayoutConstraint!
    private var titleTopPicker: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)

        picker.segmentStyle = .capsule
        picker.isHidden = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.target = self
        picker.action = #selector(pickerChanged)
        addSubview(picker)

        titleLabel.font = .systemFont(ofSize: 32, weight: .light)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        gauge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gauge)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        for label in [activeChartTitle, rateChartTitle] {
            label.font = .systemFont(ofSize: 14)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        for caption in [activeCaption, rateCaption] {
            caption.font = .systemFont(ofSize: 13)
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

        titleTopSingle = titleLabel.topAnchor.constraint(equalTo: topAnchor)
        let pickerTop = picker.topAnchor.constraint(equalTo: topAnchor)
        titleTopPicker = titleLabel.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8)

        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            pickerTop,

            titleTopSingle,
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
        // 初始为单盘状态（标题贴顶）；update() 里按盘数切换 titleTopSingle / titleTopPicker
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 预置选中盘（如 --disk 调试参数）；首次 update 前调用
    func select(bsdName: String) {
        selectedBSD = bsdName
    }

    @objc private func pickerChanged() {
        guard let last = lastUpdate else { return }
        let index = picker.selectedSegment
        guard index >= 0, index < last.identities.count else { return }
        selectedBSD = last.identities[index].bsdName
        update(identities: last.identities, iokit: last.iokit, history: last.history)
    }

    func update(identities: [DiskIdentity], iokit: IOKitSample?, history: HistorySnapshot) {
        lastUpdate = (identities, iokit, history)
        let theme = Theme.shared
        diskColor = theme.color(.disk)
        writeColor = theme.color(.network)

        let primary = identities.first(where: { $0.isSystemDisk }) ?? identities.first
        if let selected = selectedBSD, !identities.contains(where: { $0.bsdName == selected }) {
            selectedBSD = primary?.bsdName   // 卸载/换盘后回落
        }
        let identity = selectedBSD.flatMap { bsd in identities.first(where: { $0.bsdName == bsd }) } ?? primary

        // 切换器：仅多盘时显示
        if identities.count > 1 {
            if picker.segmentCount != identities.count {
                picker.segmentCount = identities.count
                for (index, disk) in identities.enumerated() {
                    let label = disk.size > 0 ? "\(disk.bsdName) · \(Formats.memory(disk.size))" : disk.bsdName
                    picker.setLabel(label, forSegment: index)
                }
            }
            picker.isHidden = false
            titleTopPicker.isActive = true
            titleTopSingle.isActive = false
            let target = identities.firstIndex { $0.bsdName == (selectedBSD ?? identity?.bsdName) } ?? 0
            if picker.selectedSegment != target { picker.selectedSegment = target }
        } else {
            picker.isHidden = true
            titleTopSingle.isActive = true
            titleTopPicker.isActive = false
        }

        titleLabel.stringValue = identity?.model ?? "磁盘"
        subtitleLabel.stringValue = identity.map { "\($0.medium) · \($0.bsdName)" } ?? "不可用"

        // 实时指标取选中盘；该盘无驱动统计（如刚接入）时显示不可用
        let per = identity.flatMap { iokit?.perDisk[$0.bsdName] }

        let active = per?.activeTimePercent ?? 0
        valueLabel.stringValue = Formats.percent(active)
        valueLabel.textColor = diskColor
        gauge.color = diskColor
        gauge.segmentCount = 60
        gauge.ratio = active / 100

        activeChartTitle.textColor = theme.textSecondary
        rateChartTitle.textColor = theme.textSecondary
        activeCaption.textColor = theme.textSecondary
        rateCaption.textColor = theme.textSecondary

        let bsd = identity?.bsdName ?? ""
        activeChart.series = [.init(values: history.diskActiveByDisk[bsd] ?? [], color: diskColor, fill: true)]
        activeChart.yMax = Self.niceMax(values: history.diskActiveByDisk[bsd] ?? [])

        let reads = history.diskReadByDisk[bsd] ?? []
        let writes = history.diskWriteByDisk[bsd] ?? []
        rateChart.series = [
            .init(values: reads, color: diskColor, fill: true),
            .init(values: writes, color: writeColor),
        ]
        rateChart.yMax = Self.niceMax(values: zip(reads, writes).map { $0.0 + $0.1 })

        var items: [(String, String)] = [
            ("读取速度", per.map { Formats.rate($0.readPerSecond) } ?? "不可用"),
            ("写入速度", per.map { Formats.rate($0.writePerSecond) } ?? "不可用"),
            ("总读取量", per.map { Formats.memory($0.totalReadBytes) } ?? "不可用"),
            ("总写入量", per.map { Formats.memory($0.totalWriteBytes) } ?? "不可用"),
            ("活跃时间", per.map { Formats.percent($0.activeTimePercent) } ?? "不可用"),
            ("平均响应时间", per?.avgResponseMs.map { String(format: "%.1f ms", $0) } ?? "不可用"),
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
