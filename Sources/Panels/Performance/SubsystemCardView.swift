import AppKit

final class SubsystemCardView: NSView {
    let subsystem: PerformancePanelViewController.Subsystem
    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let line1Label = NSTextField(labelWithString: "")
    private let line2Label = NSTextField(labelWithString: "")
    private let sparkline = SparklineView()
    private var selected = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(subsystem: PerformancePanelViewController.Subsystem) {
        self.subsystem = subsystem
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 58).isActive = true

        titleLabel.stringValue = subsystem.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        line1Label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        line1Label.lineBreakMode = .byTruncatingTail
        line1Label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line1Label)

        line2Label.font = .systemFont(ofSize: 11)
        line2Label.lineBreakMode = .byTruncatingTail
        line2Label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line2Label)

        iconView.image = NSImage(systemSymbolName: subsystem.symbol, accessibilityDescription: subsystem.title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        sparkline.translatesAutoresizingMaskIntoConstraints = false
        sparkline.sampleCapacity = 0
        addSubview(sparkline)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            line1Label.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            line1Label.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            line1Label.trailingAnchor.constraint(lessThanOrEqualTo: sparkline.leadingAnchor, constant: -5),

            line2Label.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            line2Label.topAnchor.constraint(equalTo: line1Label.bottomAnchor, constant: 1),
            line2Label.trailingAnchor.constraint(lessThanOrEqualTo: sparkline.leadingAnchor, constant: -5),

            sparkline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sparkline.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            sparkline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            sparkline.widthAnchor.constraint(equalToConstant: 60),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refreshBackground() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshBackground() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        refreshBackground()
    }

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    func update(line1: String, line2: String, values: [Double], color: NSColor) {
        line1Label.stringValue = line1
        line2Label.stringValue = line2
        sparkline.values = values
        sparkline.color = color
        iconView.contentTintColor = color
    }

    func applyTheme() {
        let theme = Theme.shared
        titleLabel.textColor = theme.textPrimary
        line1Label.textColor = theme.textPrimary
        line2Label.textColor = theme.textSecondary
        iconView.contentTintColor = theme.color(subsystem.kind)
        refreshBackground()
    }

    private func refreshBackground() {
        let theme = Theme.shared
        let color = theme.color(subsystem.kind)
        if selected || hovered {
            layer?.backgroundColor = theme.cardBackground.cgColor
            layer?.borderColor = color.withAlphaComponent(selected ? 0.9 : 0.4).cgColor
        } else {
            layer?.backgroundColor = theme.cardBackground.withAlphaComponent(0.55).cgColor
            layer?.borderColor = theme.separator.withAlphaComponent(0.6).cgColor
        }
    }
}
