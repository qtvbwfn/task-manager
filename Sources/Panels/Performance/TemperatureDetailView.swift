import AppKit

// MARK: - 通用状态卡（热压力 / 热点）

final class ThermalStatCardView: NSView, ThemeAware {
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
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
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
        iconView.contentTintColor = theme.color(.thermal)
    }
}

// MARK: - 温度传感器卡（标题 + 当前值 + 迷你曲线）

final class TemperatureSensorCardView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "不可用")
    private let chart = ChartView()
    private let kind: SubsystemKind

    init(title: String, kind: SubsystemKind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 118).isActive = true

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        chart.showsGrid = true
        chart.sampleCapacity = 0
        chart.glow = true
        chart.yMin = 0
        chart.yMax = 100
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -6),

            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            chart.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(values: [Double], current: Double?) {
        let color = Theme.shared.color(kind)
        if let current {
            valueLabel.stringValue = String(format: "%.1f °C", current)
        } else {
            valueLabel.stringValue = "不可用"
        }
        valueLabel.textColor = color
        chart.series = [.init(values: values, color: color, fill: true)]

        // 迷你图按当前序列自适应量程（TMOG 式局部放大），避免 0–110 °C 下几乎一条直线
        let lo = values.min() ?? current ?? 0
        let hi = values.max() ?? current ?? 1
        let padding = max((hi - lo) * 0.15, 2)
        chart.yMin = lo - padding
        chart.yMax = hi + padding
    }

    func applyTheme() {
        let theme = Theme.shared
        layer?.backgroundColor = theme.cardBackground.withAlphaComponent(0.55).cgColor
        layer?.borderColor = theme.color(kind).withAlphaComponent(0.35).cgColor
        titleLabel.textColor = theme.textPrimary
        valueLabel.textColor = theme.color(kind)
        chart.needsDisplay = true
    }
}

// MARK: - 温度详情（对标 TMOG：热点仪表 + CPU/SoC 热点曲线 + 热压力/热点卡 + 温度传感器网格）

final class TemperatureDetailView: NSView, ThemeAware {
    private struct SensorDefinition {
        let key: String
        let title: String
        let kind: SubsystemKind
    }

    private let titleLabel = NSTextField(labelWithString: "温度")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let gauge = SegmentedBarView()
    private let valueLabel = NSTextField(labelWithString: "")
    private let sectionTitle = NSTextField(labelWithString: "CPU / SoC 热点")
    private let chart = ChartView()
    private let rollingTitle = NSTextField(labelWithString: "滚动历史")
    private let pressureCard = ThermalStatCardView(symbol: "thermometer", title: "热压力")
    private let hotspotCard = ThermalStatCardView(symbol: "flame.fill", title: "热点")
    private let sensorTitle = NSTextField(labelWithString: "温度传感器")
    private let sensorGrid = NSStackView()
    private var sensorCards: [TemperatureSensorCardView] = []
    private var sensorDefinitions: [SensorDefinition] = []
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

        sectionTitle.font = .systemFont(ofSize: 13)
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionTitle)

        chart.showsGrid = true
        chart.yMin = 0
        chart.yMax = 110
        chart.sampleCapacity = 0
        chart.axisLabelFontSize = 11
        chart.rightAxisLabels = [(1, "110.0 °C")]
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        rollingTitle.font = .systemFont(ofSize: 13)
        rollingTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rollingTitle)

        let infoRow = NSStackView(views: [pressureCard, hotspotCard])
        infoRow.orientation = .horizontal
        infoRow.spacing = 10
        infoRow.distribution = .fillEqually
        infoRow.alignment = .centerY
        infoRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoRow)

        sensorTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        sensorTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sensorTitle)

        sensorGrid.orientation = .vertical
        sensorGrid.spacing = 10
        sensorGrid.alignment = .width
        sensorGrid.distribution = .fillEqually
        sensorGrid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sensorGrid)

        let definitions: [SensorDefinition] = [
            .init(key: "TC0E", title: "CPU core (TC0E)", kind: .thermal),
            .init(key: "TC0F", title: "CPU core (TC0F)", kind: .thermal),
            .init(key: "TCXC", title: "CPU PECI (TCXC)", kind: .thermal),
            .init(key: "TC0P", title: "CPU proximity (TC0P)", kind: .thermal),
            .init(key: "TB0T", title: "电池 (TB0T)", kind: .gpu),
        ]
        sensorDefinitions = definitions
        for definition in definitions {
            sensorCards.append(TemperatureSensorCardView(title: definition.title, kind: definition.kind))
        }
        buildSensorGrid()

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

            sectionTitle.topAnchor.constraint(equalTo: gauge.bottomAnchor, constant: 14),
            sectionTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            chart.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),

            rollingTitle.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 8),
            rollingTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            infoRow.topAnchor.constraint(equalTo: rollingTitle.bottomAnchor, constant: 10),
            infoRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            infoRow.trailingAnchor.constraint(equalTo: trailingAnchor),

            sensorTitle.topAnchor.constraint(equalTo: infoRow.bottomAnchor, constant: 14),
            sensorTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            sensorGrid.topAnchor.constraint(equalTo: sensorTitle.bottomAnchor, constant: 8),
            sensorGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            sensorGrid.trailingAnchor.constraint(equalTo: trailingAnchor),
            sensorGrid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildSensorGrid() {
        sensorGrid.arrangedSubviews.forEach {
            sensorGrid.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let columns = 3
        for start in stride(from: 0, to: sensorCards.count, by: columns) {
            let end = min(start + columns, sensorCards.count)
            var rowViews: [NSView] = sensorCards[start..<end].map { $0 }
            while rowViews.count < columns { rowViews.append(NSView()) }

            let row = NSStackView(views: rowViews)
            row.orientation = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            row.alignment = .centerY
            sensorGrid.addArrangedSubview(row)
        }
    }

    func update(history: HistorySnapshot, iokit: IOKitSample?) {
        let current = iokit?.temperature
        let thermal = thermalText(Foundation.ProcessInfo.processInfo.thermalState)
        subtitleLabel.stringValue = "热压力 \(thermal)"

        valueLabel.stringValue = current.map { String(format: "%.1f °C", $0) } ?? "不可用"
        valueLabel.textColor = color
        gauge.color = color
        gauge.ratio = min(max((current ?? 0) / 110, 0), 1)

        chart.series = [.init(values: history.temperature, color: color, fill: true)]

        pressureCard.update(thermal)
        hotspotCard.update(current.map { String(format: "%.1f °C", $0) } ?? "不可用")

        for (index, definition) in sensorDefinitions.enumerated() where index < sensorCards.count {
            sensorCards[index].update(
                values: history.temperatureSensors[definition.key] ?? [],
                current: iokit?.sensorTemperatures[definition.key]
            )
        }
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
        sectionTitle.textColor = theme.textSecondary
        rollingTitle.textColor = theme.textSecondary
        sensorTitle.textColor = theme.textPrimary
        gauge.color = color
        pressureCard.applyTheme()
        hotspotCard.applyTheme()
        sensorCards.forEach { $0.applyTheme() }
        chart.needsDisplay = true
    }
}
