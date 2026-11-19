import AppKit

final class ServicesPanelViewController: PanelBaseViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    struct ServiceItem {
        let label: String
        let program: String
        let domain: String
        let disabled: Bool?
    }

    private let table = NSTableView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private var items: [ServiceItem] = []
    private var filtered: [ServiceItem] = []

    init() { super.init(title: "服务") }

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
        searchField.placeholderString = "按 Label 或程序路径筛选"
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

        let columns: [(String, String, CGFloat)] = [
            ("label", "Label", 320),
            ("program", "可执行文件", 360),
            ("domain", "域", 70),
            ("status", "禁用状态", 90),
        ]
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableColumn.minWidth = 60
            table.addTableColumn(tableColumn)
        }
        table.headerView = NSTableHeaderView()
        table.rowHeight = 23
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
            searchField.widthAnchor.constraint(equalToConstant: 260),

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
        refreshButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = Self.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.items = items
                self.applyFilter()
                self.refreshButton.isEnabled = true
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
                $0.label.lowercased().contains(query) || $0.program.lowercased().contains(query)
            }
        }
        countLabel.stringValue = "共 \(filtered.count) 项"
        table.reloadData()
    }

    // MARK: - 扫描

    private static func scan() -> [ServiceItem] {
        let domains: [(path: String, domain: String)] = [
            (NSHomeDirectory() + "/Library/LaunchAgents", "用户"),
            ("/Library/LaunchAgents", "用户"),
            ("/Library/LaunchDaemons", "系统"),
            ("/System/Library/LaunchAgents", "系统"),
            ("/System/Library/LaunchDaemons", "系统"),
        ]

        var results: [ServiceItem] = []
        for entry in domains {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: entry.path) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let path = entry.path + "/" + file
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? String(file.dropLast(6))
                let program: String
                if let programPath = plist["Program"] as? String {
                    program = programPath
                } else if let arguments = plist["ProgramArguments"] as? [String], let first = arguments.first {
                    program = first
                } else {
                    program = "—"
                }
                let disabled = plist["Disabled"] as? Bool
                results.append(ServiceItem(label: label, program: program, domain: entry.domain, disabled: disabled))
            }
        }

        let disabledMap = loadDisabledMap()

        return results.map { item in
            ServiceItem(
                label: item.label,
                program: item.program,
                domain: item.domain,
                disabled: disabledMap[item.label] ?? item.disabled
            )
        }.sorted { $0.label < $1.label }
    }

    /// launchctl print-disabled 输出：`"com.example.agent" => disabled`
    private static func loadDisabledMap() -> [String: Bool] {
        var map: [String: Bool] = [:]
        for domain in ["system", "gui/\(getuid())"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["print-disabled", domain]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("\""), let arrow = trimmed.range(of: "=>") else { continue }
                    let labelPart = trimmed[trimmed.startIndex..<arrow.lowerBound]
                        .trimmingCharacters(in: CharacterSet(charactersIn: " \"\t"))
                    let valuePart = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                    guard !labelPart.isEmpty else { continue }
                    map[labelPart] = valuePart.contains("disabled")
                }
            } catch {
                continue
            }
        }
        return map
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count, let tableColumn else { return nil }
        let item = filtered[row]
        let theme = Theme.shared
        let identifier = NSUserInterfaceItemIdentifier("service-" + tableColumn.identifier.rawValue)
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TextCellView) ?? TextCellView()
        cell.identifier = identifier

        switch tableColumn.identifier.rawValue {
        case "label": cell.update(text: item.label, alignment: .left, color: theme.textPrimary)
        case "program": cell.update(text: item.program, alignment: .left, color: theme.textSecondary)
        case "domain": cell.update(text: item.domain, alignment: .left, color: theme.textSecondary)
        case "status":
            if let disabled = item.disabled {
                cell.update(text: disabled ? "已禁用" : "已启用", alignment: .left,
                            color: disabled ? theme.statusWarn : theme.statusOk)
            } else {
                cell.update(text: "不可用", alignment: .left, color: theme.textSecondary)
            }
        default: return nil
        }
        return cell
    }
}
extension ServicesPanelViewController: SearchFocusable {
    @objc func focusSearch(_ sender: Any?) {
        view.window?.makeFirstResponder(searchField)
    }
}
