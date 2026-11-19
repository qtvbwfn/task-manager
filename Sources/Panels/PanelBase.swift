import AppKit

/// 有搜索框的面板实现此协议，⌘F 经响应链定位到当前面板的搜索框。
@objc protocol SearchFocusable {
    @objc func focusSearch(_ sender: Any?)
}

/// 遵循此协议的视图在主题切换时由各面板统一调用 applyTheme() 刷新配色。
protocol ThemeAware: AnyObject {
    func applyTheme()
}

/// 所有面板的基类：标题 + 内容容器，统一响应主题切换。
class PanelBaseViewController: NSViewController {
    let panelTitle: String

    private let titleLabel = NSTextField(labelWithString: "")
    let contentContainer = NSView()

    /// 性能页对齐 TMOG：大标题由右侧详情区提供，页面不再重复一行"性能"
    var showsPanelTitle: Bool { true }

    init(title: String) {
        self.panelTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        view = root

        titleLabel.font = .systemFont(ofSize: 26, weight: .light)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentContainer)

        if showsPanelTitle {
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
                titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

                contentContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
                contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            ])
        } else {
            titleLabel.isHidden = true
            NSLayoutConstraint.activate([
                contentContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
                contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
                contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            ])
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    @objc private func themeChanged() {
        applyTheme()
    }

    func applyTheme() {
        titleLabel.stringValue = panelTitle
        titleLabel.textColor = Theme.shared.textPrimary
        view.layer?.backgroundColor = Theme.shared.windowBackground.cgColor
    }
}