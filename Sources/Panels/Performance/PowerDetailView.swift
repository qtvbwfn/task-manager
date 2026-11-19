import AppKit

// MARK: - 能耗指标卡

final class EnergyMetricCardView: NSView, ThemeAware {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "不可用")

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 56).isActive = true

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),

            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ value: String) {
        valueLabel.stringValue = value
    }

    func applyTheme() {
        let theme = Theme.shared
        layer?.backgroundColor = theme.cardBackground.withAlphaComponent(0.55).cgColor
        layer?.borderColor = theme.separator.withAlphaComponent(0.6).cgColor
        titleLabel.textColor = theme.textSecondary
        valueLabel.textColor = theme.textPrimary
        iconView.contentTintColor = theme.color(.power)
    }
}

// MARK: - 能耗详情（对标 TMOG：热状态副标题 + 功耗仪表/曲线 + 可用指标卡片网格）

final class PowerDetailView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "能耗")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let gauge = SegmentedBarView()
    private let valueLabel = NSTextField(labelWithString: "")
    private let chartTitle = NSTextField(labelWithString: "功耗")
    private let chart = ChartView()
    private let rollingTitle = NSTextField(labelWithString: "滚动历史")
    private let grid = NSStackView()
    private var cards: [EnergyMetricCardView] = []
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 32, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        gauge.orientation = .horizontal
        gauge.segmentCount = 60
        gauge.color = color
        gauge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gauge)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        chartTitle.font = .systemFont(ofSize: 13)
        chartTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartTitle)

        chart.showsGrid = true
        chart.yMin = 0
        chart.sampleCapacity = 0
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        rollingTitle.font = .systemFont(ofSize: 13)
        rollingTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rollingTitle)

        grid.orientation = .vertical
        grid.spacing = 10
        grid.alignment = .width
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        // 只保留本机可取数的指标；CPU/GPU/ANE/DRAM/SoC 封装功耗等无公开 API，不显示
        let definitions: [(symbol: String, title: String)] = [
            ("bolt.circle.fill", "实时功耗"),
            ("speedometer", "电源模式"),
            ("powerplug", "电源"),
            ("battery.75", "电量"),
            ("bolt.fill", "充电状态"),
            ("powerplug.fill", "适配器"),
            ("heart.text.square", "电池健康"),
            ("arrow.2.circlepath", "循环计数"),
            ("thermometer", "热状态"),
        ]
        for definition in definitions {
            cards.append(EnergyMetricCardView(symbol: definition.symbol, title: definition.title))
        }
        buildGrid()

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            gauge.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            gauge.leadingAnchor.constraint(equalTo: leadingAnchor),
            gauge.heightAnchor.constraint(equalToConstant: 12),

            valueLabel.leadingAnchor.constraint(equalTo: gauge.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: gauge.centerYAnchor),

            chartTitle.topAnchor.constraint(equalTo: gauge.bottomAnchor, constant: 14),
            chartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            chart.topAnchor.constraint(equalTo: chartTitle.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),

            rollingTitle.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 8),
            rollingTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            grid.topAnchor.constraint(equalTo: rollingTitle.bottomAnchor, constant: 10),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildGrid() {
        grid.arrangedSubviews.forEach {
            grid.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let columns = 3
        for start in stride(from: 0, to: cards.count, by: columns) {
            let end = min(start + columns, cards.count)
            var rowViews: [NSView] = cards[start..<end].map { $0 }
            // 最后一行不足 3 个时用空白占位，保证各列等宽
            while rowViews.count < columns { rowViews.append(NSView()) }

            let row = NSStackView(views: rowViews)
            row.orientation = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            row.alignment = .centerY
            grid.addArrangedSubview(row)
        }
    }

    func update(history: HistorySnapshot, iokit: IOKitSample?) {
        let watts = iokit?.watts
        let value = watts.map { String(format: "%.1f W", $0) } ?? "不可用"
        valueLabel.stringValue = value
        valueLabel.textColor = color

        let thermal = thermalText(Foundation.ProcessInfo.processInfo.thermalState)
        subtitleLabel.stringValue = "\(thermal) · \(iokit?.powerSource ?? "不可用")"

        // 仪表以适配器额定功率为满格；离电时按 60 W 估算
        let capacity = Double(iokit?.adapterWatts ?? 60)
        gauge.color = color
        gauge.ratio = min(max((watts ?? 0) / max(capacity, 1), 0), 1)

        chart.series = [.init(values: history.watts, color: color, fill: true)]
        let maxWatts = max(history.watts.max() ?? 0, watts ?? 0)
        chart.yMax = Self.niceMax(maxWatts)

        let charging = iokit?.hasBattery == true
            ? (iokit?.isCharging == true ? "充电中" : "未充电")
            : "不可用"
        let batteryText = iokit?.batteryPercent.map { String(format: "%.1f%%", Double($0)) } ?? "不可用"
        let adapterText = iokit?.adapterWatts.map { "\($0) W" } ?? "不可用"
        let healthText = iokit?.batteryHealthPercent.map { String(format: "%.0f%%", $0) } ?? "不可用"
        let cycleText = iokit?.cycleCount.map { "\($0)" } ?? "不可用"
        let powerMode = Foundation.ProcessInfo.processInfo.isLowPowerModeEnabled ? "低电量模式" : "正常"
        let values = [
            value,
            powerMode,
            iokit?.powerSource ?? "不可用",
            batteryText,
            charging,
            adapterText,
            healthText,
            cycleText,
            thermal,
        ]
        for (index, card) in cards.enumerated() where index < values.count {
            card.update(values[index])
        }
    }

    private static func niceMax(_ value: Double) -> Double {
        let minimum = 10.0
        let target = max(value, minimum)
        let magnitude = pow(10, floor(log10(target)))
        let normalized = target / magnitude
        let nice: Double
        if normalized <= 1 {
            nice = 1
        } else if normalized <= 2 {
            nice = 2
        } else if normalized <= 5 {
            nice = 5
        } else {
            nice = 10
        }
        return max(nice * magnitude, minimum)
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

    func applyTheme() {
        let theme = Theme.shared
        titleLabel.textColor = theme.textPrimary
        subtitleLabel.textColor = theme.textSecondary
        valueLabel.textColor = color
        chartTitle.textColor = theme.textSecondary
        rollingTitle.textColor = theme.textSecondary
        gauge.color = color
        cards.forEach { $0.applyTheme() }
        chart.needsDisplay = true
    }
}
