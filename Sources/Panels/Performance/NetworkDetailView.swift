import AppKit

/// 网络详情（对标 TMOG）：接口选择 + 吞吐量仪表 + 双序列图 + 指标网格（MAC/IP/连接速率/WiFi）
final class NetworkDetailView: NSView, ThemeAware {
    private let titleLabel = NSTextField(labelWithString: "网络")
    private let valueLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let gauge = SegmentedBarView()
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let chartTitle = NSTextField(labelWithString: "吞吐量")
    private let chart = ChartView()
    private let chartCaption = NSTextField(labelWithString: "滚动历史 · 蓝=下行 绿=上行")
    private let metrics = MetricGridView()

    private var color: NSColor = .systemBlue
    private var upColor: NSColor = .systemGreen
    private var lastSample: NetworkSampler.Sample?
    private var lastHistory: HistorySnapshot?
    /// nil = 合并所有接口
    private var selectedName: String?
    private var pickerNames: [String] = []

    override init(frame: NSRect) {
        super.init(frame: frame)

        titleLabel.font = .systemFont(ofSize: 32, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        gauge.segmentCount = 60
        gauge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gauge)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        picker.font = .systemFont(ofSize: 12)
        picker.target = self
        picker.action = #selector(pickerChanged)
        picker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picker)

        chartTitle.font = .systemFont(ofSize: 13)
        chartTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartTitle)

        chart.showsGrid = true
        chart.yMin = 0
        chart.sampleCapacity = 0
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        chartCaption.font = .systemFont(ofSize: 12)
        chartCaption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartCaption)

        metrics.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metrics)

        let metricsBottom = metrics.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        metricsBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            gauge.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            gauge.leadingAnchor.constraint(equalTo: leadingAnchor),
            gauge.heightAnchor.constraint(equalToConstant: 14),

            valueLabel.leadingAnchor.constraint(equalTo: gauge.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: gauge.centerYAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: gauge.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            picker.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            picker.widthAnchor.constraint(lessThanOrEqualToConstant: 280),

            chartTitle.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 10),
            chartTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            chart.topAnchor.constraint(equalTo: chartTitle.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor),
            chart.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            chartCaption.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 4),
            chartCaption.leadingAnchor.constraint(equalTo: leadingAnchor),

            metrics.topAnchor.constraint(equalTo: chartCaption.bottomAnchor, constant: 12),
            metrics.leadingAnchor.constraint(equalTo: leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: trailingAnchor),
            metricsBottom,
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(sample: NetworkSampler.Sample?, history: HistorySnapshot) {
        lastSample = sample
        lastHistory = history
        rebuildPicker()
        render()
    }

    /// 截图调试用：--netif en0 直接选中某接口（配合 --panel performance --subsystem network）
    func select(interfaceName: String) {
        selectedName = interfaceName
    }

    // MARK: - 渲染

    private func rebuildPicker() {
        guard let sample = lastSample else { return }
        // 只列出物理网卡（en*），utun/awdl 等虚拟接口不进选择器
        let names = sample.perInterface.filter { $0.name.hasPrefix("en") }.map(\.name)
        guard names != pickerNames else { return }
        pickerNames = names
        picker.removeAllItems()
        picker.addItem(withTitle: "所有接口（合并）")
        for name in names {
            let type = sample.perInterface.first { $0.name == name }.map { typeName($0) } ?? ""
            picker.addItem(withTitle: "\(name) · \(type)")
        }
        if let selected = selectedName, let index = names.firstIndex(of: selected) {
            picker.selectItem(at: index + 1)
        } else {
            selectedName = nil
            picker.selectItem(at: 0)
        }
    }

    @objc private func pickerChanged() {
        let index = picker.indexOfSelectedItem
        selectedName = index <= 0 ? nil : (index - 1 < pickerNames.count ? pickerNames[index - 1] : nil)
        render()
    }

    private func render() {
        guard let sample = lastSample else { return }
        let theme = Theme.shared
        color = theme.color(.network)
        upColor = theme.color(.cpu)
        gauge.color = color
        valueLabel.textColor = color

        if let name = selectedName, let iface = sample.perInterface.first(where: { $0.name == name }) {
            renderInterface(iface, history: lastHistory)
        } else {
            renderMerged(sample, history: lastHistory)
        }
        metrics.applyTheme()
        chart.needsDisplay = true
    }

    /// 合并视图（对标 TMOG：已合并 N 个网络接口）
    private func renderMerged(_ sample: NetworkSampler.Sample, history: HistorySnapshot?) {
        titleLabel.stringValue = "网络"
        valueLabel.stringValue = Formats.rate(sample.bytesInPerSecond)
        subtitleLabel.stringValue = "已合并 \(sample.interfaces) 个网络接口 · 上行 \(Formats.rate(sample.bytesOutPerSecond))"

        let down = history?.networkIn ?? []
        let up = history?.networkOut ?? []
        setChart(down: down, up: up, current: sample.bytesInPerSecond + sample.bytesOutPerSecond)

        let ipv4Count = sample.perInterface.filter { !$0.ipv4.isEmpty }.count
        metrics.configure(items: [
            ("下行", Formats.rate(sample.bytesInPerSecond)),
            ("上行", Formats.rate(sample.bytesOutPerSecond)),
            ("累计接收", Formats.memory(sample.totalBytesIn)),
            ("累计发送", Formats.memory(sample.totalBytesOut)),
            ("接口名称", "所有接口"),
            ("连接类型", "已合并"),
            ("接口数", "\(sample.interfaces)"),
            ("硬件地址", "不适用"),
            ("IPv4 地址", ipv4Count > 0 ? "\(ipv4Count) 个" : "无"),
        ], columns: 4)
    }

    /// 单接口视图
    private func renderInterface(_ iface: NetworkInterfaceSample, history: HistorySnapshot?) {
        titleLabel.stringValue = iface.name
        valueLabel.stringValue = Formats.rate(iface.inPerSecond)
        let type = typeName(iface)
        subtitleLabel.stringValue = "\(type) · \(iface.isUp ? "已连接" : "未连接") · 上行 \(Formats.rate(iface.outPerSecond))"

        let down = history?.networkInByInterface[iface.name] ?? []
        let up = history?.networkOutByInterface[iface.name] ?? []
        setChart(down: down, up: up, current: iface.inPerSecond + iface.outPerSecond)

        var items: [(String, String)] = [
            ("下行", Formats.rate(iface.inPerSecond)),
            ("上行", Formats.rate(iface.outPerSecond)),
            ("累计接收", Formats.memory(iface.bytesIn)),
            ("累计发送", Formats.memory(iface.bytesOut)),
            ("接口名称", iface.name),
            ("连接类型", type),
            ("状态", iface.isUp ? "已连接" : "未连接"),
            ("硬件地址", iface.mac.isEmpty ? "不可用" : iface.mac),
            ("IPv4 地址", iface.ipv4.isEmpty ? "无" : iface.ipv4.joined(separator: " · ")),
            ("连接速率", iface.baudrateBps > 0 ? Formats.baudrate(iface.baudrateBps) : "不可用"),
        ]
        if let wifi = iface.wifi {
            items.append(contentsOf: [
                ("WiFi 名称", wifi.ssid ?? "需定位权限"),
                ("信道", wifi.channel),
                ("WiFi 速率", wifi.transmitMbps > 0 ? String(format: "%.0f Mb/s", wifi.transmitMbps) : "不可用"),
                ("信号强度", signalText(wifi.rssi)),
                ("噪声", wifi.rssi != 0 ? "\(wifi.noise) dBm" : "不可用"),
                ("安全性", wifi.security),
            ])
        }
        metrics.configure(items: items, columns: 4)
    }

    private func setChart(down: [Double], up: [Double], current total: Double) {
        chart.series = [
            .init(values: down, color: color, fill: true),
            .init(values: up, color: upColor),
        ]
        chart.yMax = Self.niceMax(values: down + up + [total])
        gauge.ratio = chart.yMax > 0 ? min(total / chart.yMax, 1) : 0
    }

    private func typeName(_ iface: NetworkInterfaceSample) -> String {
        iface.isWiFi ? "Wi-Fi" : (iface.name.hasPrefix("en") ? "以太网" : "其他")
    }

    private func signalText(_ rssi: Int) -> String {
        guard rssi != 0 else { return "未连接" }
        let quality: String
        if rssi >= -50 {
            quality = "优秀"
        } else if rssi >= -60 {
            quality = "良好"
        } else if rssi >= -70 {
            quality = "一般"
        } else {
            quality = "较弱"
        }
        return "\(rssi) dBm · \(quality)"
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
        valueLabel.textColor = color
        subtitleLabel.textColor = theme.textSecondary
        chartTitle.textColor = theme.textSecondary
        chartCaption.textColor = theme.textSecondary
        gauge.color = color
        metrics.applyTheme()
        chart.needsDisplay = true
    }
}
