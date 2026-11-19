import AppKit

final class StartupPanelViewController: PanelBaseViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    struct StartupItem {
        let name: String
        let kind: String
        let path: String
        let disabled: Bool
    }

    private let table = NSTableView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private var items: [StartupItem] = []
    private var filtered: [StartupItem] = []

    init() { super.init(title: "登录项") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        reload()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    override func applyTheme() {
        super.applyTheme()
        countLabel.textColor = Theme.shared.textSecondary
        table.reloadData()
    }

    private func buildLayout() {
        searchField.placeholderString = "按名称或路径筛选"
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 13)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(searchField)
        contentContainer.addSubview(countLabel)
        contentContainer.addSubview(refreshButton)

        let columns: [(String, String, CGFloat, NSTextAlignment)] = [
            ("name", "名称", 220, .left),
            ("kind", "种类", 110, .left),
            ("path", "路径", 380, .left),
            ("status", "状态", 80, .left),
        ]
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableColumn.minWidth = 60
            table.addTableColumn(tableColumn)
        }
        table.headerView = NSTableHeaderView()
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        table.style = .fullWidth
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 240),

            countLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 10),

            refreshButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    @objc private func refreshTapped() {
        reload()
    }

    private func reload() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = Self.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.items = items
                self.applyFilter()
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filtered = items
        } else {
            filtered = items.filter {
                $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query)
            }
        }
        countLabel.stringValue = "共 \(filtered.count) 项"
        table.reloadData()
    }

    private static func scan() -> [StartupItem] {
        let home = NSHomeDirectory()
        let dirs: [(path: String, kind: String)] = [
            (home + "/Library/LaunchAgents", "用户代理"),
            ("/Library/LaunchAgents", "本地代理"),
            ("/Library/LaunchDaemons", "本地守护"),
        ]
        var results: [StartupItem] = []
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let fullPath = dir.path + "/" + file
                guard let data = FileManager.default.contents(atPath: fullPath),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? String(file.dropLast(6))
                let disabled = (plist["Disabled"] as? Bool) ?? false
                results.append(StartupItem(name: label, kind: dir.kind, path: fullPath, disabled: disabled))
            }
        }
        return results.sorted { $0.name < $1.name }
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count, let tableColumn else { return nil }
        let item = filtered[row]
        let theme = Theme.shared
        let identifier = NSUserInterfaceItemIdentifier("startup-" + tableColumn.identifier.rawValue)
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TextCellView) ?? TextCellView()
        cell.identifier = identifier

        switch tableColumn.identifier.rawValue {
        case "name": cell.update(text: item.name, alignment: .left, color: theme.textPrimary)
        case "kind": cell.update(text: item.kind, alignment: .left, color: theme.textSecondary)
        case "path": cell.update(text: item.path, alignment: .left, color: theme.textSecondary)
        case "status":
            cell.update(text: item.disabled ? "已禁用" : "已启用", alignment: .left,
                        color: item.disabled ? theme.statusWarn : theme.statusOk)
        default: return nil
        }
        return cell
    }
}
extension StartupPanelViewController: SearchFocusable {
    @objc func focusSearch(_ sender: Any?) {
        view.window?.makeFirstResponder(searchField)
    }
}
