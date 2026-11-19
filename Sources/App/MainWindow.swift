import AppKit

final class MainWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "任务管理器"
        window.minSize = NSSize(width: 900, height: 600)
        window.isRestorable = false
        window.center()
        let controller = MainViewController()
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1120, height: 740))
        self.init(window: window)
        window.delegate = self
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowDidMiniaturize(_ notification: Notification) {
        Sampler.shared.setBackground(true)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        Sampler.shared.setBackground(false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 红点关闭后从 Dock 重新打开
        Sampler.shared.setBackground(false)
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭窗口但应用驻留 Dock：采样降频，不退出
        Sampler.shared.setBackground(true)
    }
}

enum SidebarItem: Equatable {
    case panel(PanelID)
    case settings
}

final class MainViewController: NSViewController, NSMenuItemValidation {
    private let sidebar = SidebarView()
    private let contentContainer = NSView()
    private let statusBar = StatusBarView()

    private var currentPanelVC: NSViewController?
    private var panels: [PanelID: PanelBaseViewController] = [:]
    private var settingsVC: SettingsPanelViewController?
    private var currentPanels: Set<PanelID> = []

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        view = root

        sidebar.onSelect = { [weak self] item in self?.show(item) }

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(sidebar)
        root.addSubview(contentContainer)
        root.addSubview(statusBar)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 176),

            contentContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: root.topAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(samplerUpdated), name: .samplerDidUpdate, object: nil)
        if let index = CommandLine.arguments.firstIndex(of: "--panel"),
           index + 1 < CommandLine.arguments.count,
           let id = PanelID(rawValue: CommandLine.arguments[index + 1]) {
            show(.panel(id))
        } else if CommandLine.arguments.contains("--settings") {
            show(.settings)
        } else {
            show(.panel(Settings.shared.startupPanel))
        }
        statusBar.setStatus(normal: true, text: "采样正常")
    }

    @objc private func samplerUpdated() {
        let count = Sampler.shared.processes.count
        let dynamicPanels = currentPanels.contains(.summary) || currentPanels.contains(.performance)
        var failures = 0
        if dynamicPanels {
            if Sampler.shared.system == nil { failures += 1 }
            if Sampler.shared.network == nil { failures += 1 }
            if let iokit = Sampler.shared.iokit {
                if iokit.temperature == nil { failures += 1 }
                if iokit.gpuUtilization == nil { failures += 1 }
                if iokit.hasBattery && iokit.watts == nil { failures += 1 }
            } else {
                failures += 3
            }
        }
        if failures > 0 {
            statusBar.setStatus(normal: false, text: "\(failures) 项数据源不可用")
        } else if count > 0 {
            statusBar.setStatus(normal: true, text: "采样正常", detail: "\(count) 个进程")
        }
    }

    // MARK: - 菜单动作（响应链）

    @objc func switchPanelMenuItem(_ sender: NSMenuItem) {
        let panels = PanelID.allCases
        guard sender.tag >= 0, sender.tag < panels.count else { return }
        show(.panel(panels[sender.tag]))
    }

    @objc func showSettingsMenuItem(_ sender: Any?) {
        show(.settings)
    }

    /// ⌘F：经当前面板转发到搜索框（面板 VC 不一定在响应链上）
    @objc func focusSearch(_ sender: Any?) {
        (currentPanelVC as? SearchFocusable)?.focusSearch(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(focusSearch(_:)) {
            return currentPanelVC is SearchFocusable
        }
        return true
    }

    @objc private func themeChanged() {
        applyTheme()
    }

    private func applyTheme() {
        let theme = Theme.shared
        view.layer?.backgroundColor = theme.windowBackground.cgColor
        contentContainer.layer?.backgroundColor = theme.windowBackground.cgColor
        sidebar.applyTheme()
        statusBar.applyTheme()
    }

    func show(_ item: SidebarItem) {
        switch item {
        case .panel(let id):
            switch id {
            case .summary:
                currentPanels = [.summary]
                Sampler.shared.setPanels([.summary])
            case .performance:
                currentPanels = [.performance]
                Sampler.shared.setPanels([.performance])
            case .processes:
                currentPanels = [.processes]
                Sampler.shared.setPanels([.processes])
            default:
                currentPanels = []
                Sampler.shared.setPanels([])
            }
        case .settings:
            currentPanels = []
            Sampler.shared.setPanels([])
        }

        let vc: NSViewController
        switch item {
        case .panel(let id):
            if let cached = panels[id] {
                vc = cached
            } else {
                let panel = Self.makePanel(id)
                panels[id] = panel
                vc = panel
            }
        case .settings:
            if let cached = settingsVC {
                vc = cached
            } else {
                let panel = SettingsPanelViewController()
                settingsVC = panel
                vc = panel
            }
        }

        sidebar.setSelected(item)

        guard vc !== currentPanelVC else { return }
        currentPanelVC?.view.removeFromSuperview()
        currentPanelVC?.removeFromParent()

        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentPanelVC = vc
    }

    private static func makePanel(_ id: PanelID) -> PanelBaseViewController {
        switch id {
        case .summary: return SummaryPanelViewController()
        case .performance: return PerformancePanelViewController()
        case .processes: return ProcessesPanelViewController()
        case .systemInfo: return SystemInfoPanelViewController()
        case .startup: return StartupPanelViewController()
        case .users: return UsersPanelViewController()
        case .services: return ServicesPanelViewController()
        }
    }
}

// MARK: - 侧边栏

final class SidebarView: NSView {
    var onSelect: ((SidebarItem) -> Void)?

    private var rows: [SidebarRow] = []
    private let topStack = NSStackView()
    private let bottomStack = NSStackView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        topStack.orientation = .vertical
        topStack.spacing = 2
        topStack.alignment = .width
        topStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topStack)

        bottomStack.orientation = .vertical
        bottomStack.spacing = 2
        bottomStack.alignment = .width
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomStack)

        for id in PanelID.allCases {
            let row = SidebarRow(item: .panel(id), title: id.title, symbol: id.icon)
            row.onClick = { [weak self] item in self?.onSelect?(item) }
            rows.append(row)
            topStack.addArrangedSubview(row)
        }

        let settingsRow = SidebarRow(item: .settings, title: "设置", symbol: "gearshape")
        settingsRow.onClick = { [weak self] item in self?.onSelect?(item) }
        rows.append(settingsRow)
        bottomStack.addArrangedSubview(settingsRow)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            topStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            bottomStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            bottomStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            bottomStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelected(_ item: SidebarItem) {
        for row in rows { row.setSelected(row.item == item) }
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.shared.sidebarBackground.cgColor
        rows.forEach { $0.refresh() }
    }
}

final class SidebarRow: NSView {
    let item: SidebarItem
    var onClick: ((SidebarItem) -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isSelectedRow = false
    private var isHovered = false
    private var tracking: NSTrackingArea?

    init(item: SidebarItem, title: String, symbol: String) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = title
        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(item)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func setSelected(_ selected: Bool) {
        isSelectedRow = selected
        refresh()
    }

    func refresh() {
        let theme = Theme.shared
        layer?.backgroundColor = (isSelectedRow ? theme.sidebarSelectionBg : (isHovered ? theme.sidebarHoverBg : .clear)).cgColor
        let color = isSelectedRow ? theme.sidebarSelectionText : theme.textPrimary
        label.textColor = color
        label.font = .systemFont(ofSize: 14, weight: isSelectedRow ? .semibold : .regular)
        iconView.contentTintColor = color
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: isSelectedRow ? .semibold : .regular)
    }
}