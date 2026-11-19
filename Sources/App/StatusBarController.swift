import AppKit

/// 底部状态栏：正常绿点 / 降级黄点 + 进程数 + 运行时长。
final class StatusBarView: NSView {
    private let dot = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let uptimeLabel = NSTextField(labelWithString: "")
    private var timer: Timer?
    private let startDate = Date()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        uptimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        uptimeLabel.alignment = .right
        uptimeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(uptimeLabel)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            uptimeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            uptimeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUptime()
        }
        updateUptime()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        timer?.invalidate()
    }

    func setStatus(normal: Bool, text: String) {
        setStatus(normal: normal, text: text, detail: nil)
    }

    func setStatus(normal: Bool, text: String, detail: String?) {
        dot.layer?.backgroundColor = (normal ? Theme.shared.statusOk : Theme.shared.statusWarn).cgColor
        statusLabel.stringValue = detail.map { "\(text) · \($0)" } ?? text
        statusLabel.textColor = Theme.shared.textSecondary
    }

    private func updateUptime() {
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        uptimeLabel.stringValue = String(format: "已运行 %02d:%02d:%02d", h, m, s)
        uptimeLabel.textColor = Theme.shared.textSecondary
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.shared.statusBarBackground.cgColor
        statusLabel.textColor = Theme.shared.textSecondary
        uptimeLabel.textColor = Theme.shared.textSecondary
    }
}