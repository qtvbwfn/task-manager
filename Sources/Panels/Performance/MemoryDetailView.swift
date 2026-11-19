import AppKit

// MARK: - 内存详情

final class MemoryDetailView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "内存")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedBarView()
    private let chart = ChartView()
    private let chartTitle = NSTextField(labelWithString: "内存使用率")
    private let rollingTitle = NSTextField(labelWithString: "滚动历史")
    private let metrics = MetricGridView()
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

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        bar.orientation = .horizontal
        bar.segmentCount = 30
        bar.color = color
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        chartTitle.font = .systemFont(ofSize: 13)
        chartTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartTitle)

        rollingTitle.font = .systemFont(ofSize: 13)
        rollingTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rollingTitle)

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

            rollingTitle.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 8),
            rollingTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            metrics.topAnchor.constraint(equalTo: rollingTitle.bottomAnchor, constant: 10),
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
            ("联动", Formats.memory(system?.memoryWired ?? 0)),
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
        rollingTitle.textColor = theme.textSecondary
        bar.color = color
        metrics.applyTheme()
    }
}
