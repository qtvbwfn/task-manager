import AppKit

// MARK: - 通用图表详情（GPU/网络/温度）

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

        titleLabel.font = .systemFont(ofSize: 32, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        chartTitle.font = .systemFont(ofSize: 13)
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
