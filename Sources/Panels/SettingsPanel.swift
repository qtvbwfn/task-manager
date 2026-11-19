import AppKit

/// 设置页：外观 / 采样频率 / 进程默认视图 / 启动时打开，写入即持久化。
final class SettingsPanelViewController: PanelBaseViewController {
    private let appearanceSeg = NSSegmentedControl(
        labels: AppearanceMode.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let sampleSeg = NSSegmentedControl(
        labels: ["0.5 Hz", "1 Hz", "2 Hz"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let processViewPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let startupPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init() { super.init(title: "设置") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        appearanceSeg.target = self
        appearanceSeg.action = #selector(appearanceChanged)
        sampleSeg.target = self
        sampleSeg.action = #selector(sampleChanged)
        processViewPopup.target = self
        processViewPopup.action = #selector(processViewChanged)
        startupPopup.target = self
        startupPopup.action = #selector(startupPanelChanged)

        processViewPopup.addItems(withTitles: ProcessViewMode.allCases.map(\.title))
        startupPopup.addItems(withTitles: PanelID.allCases.map(\.title))

        let grid = NSGridView(views: [
            [Self.makeLabel("外观模式"), appearanceSeg],
            [Self.makeLabel("采样频率"), sampleSeg],
            [Self.makeLabel("进程默认视图"), processViewPopup],
            [Self.makeLabel("启动时打开"), startupPopup],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 18
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(grid)

        let hint = NSTextField(labelWithString: "设置自动保存；外观与进程视图即时生效，启动面板下次启动生效。")
        hint.font = .systemFont(ofSize: 12)
        hint.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(hint)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 4),
            grid.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 4),

            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 4),
        ])

        loadSettings()
        applyTheme()
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14)
        return label
    }

    private func loadSettings() {
        appearanceSeg.selectedSegment = Settings.shared.appearance.rawValue

        let interval = Settings.shared.sampleInterval
        switch interval {
        case 2.0: sampleSeg.selectedSegment = 0
        case 0.5: sampleSeg.selectedSegment = 2
        default: sampleSeg.selectedSegment = 1
        }

        processViewPopup.selectItem(at: ProcessViewMode.allCases.firstIndex(of: Settings.shared.processView) ?? 0)
        startupPopup.selectItem(at: PanelID.allCases.firstIndex(of: Settings.shared.startupPanel) ?? 0)
    }

    @objc private func appearanceChanged() {
        let mode = AppearanceMode(rawValue: appearanceSeg.selectedSegment) ?? .auto
        Theme.shared.mode = mode
    }

    @objc private func sampleChanged() {
        let intervals: [TimeInterval] = [2.0, 1.0, 0.5]
        Settings.shared.sampleInterval = intervals[sampleSeg.selectedSegment]
        Sampler.shared.restart()
    }

    @objc private func processViewChanged() {
        Settings.shared.processView = ProcessViewMode.allCases[processViewPopup.indexOfSelectedItem]
    }

    @objc private func startupPanelChanged() {
        Settings.shared.startupPanel = PanelID.allCases[startupPopup.indexOfSelectedItem]
    }

    override func applyTheme() {
        super.applyTheme()
        let theme = Theme.shared
        contentContainer.subviews.forEach { subview in
            if let label = subview as? NSTextField, label.font?.pointSize == 14 {
                label.textColor = theme.textSecondary
            }
        }
        if let hint = contentContainer.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.font?.pointSize == 12 }) {
            hint.textColor = theme.textSecondary
        }
    }
}