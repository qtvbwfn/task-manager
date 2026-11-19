import AppKit

final class UsersPanelViewController: PanelBaseViewController, NSTableViewDataSource, NSTableViewDelegate {
    struct SessionItem {
        let user: String
        let line: String
        let host: String
        let kind: String
        let loginTime: Date
    }

    struct LocalUser {
        let name: String
        let uid: uid_t
        let home: String
        let shell: String
    }

    private let sessionTitle = NSTextField(labelWithString: "登录会话")
    private let sessionTable = NSTableView()
    private let userTitle = NSTextField(labelWithString: "本地用户")
    private let userTable = NSTableView()
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)

    private var sessions: [SessionItem] = []
    private var users: [LocalUser] = []

    init() { super.init(title: "用户") }

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
        sessionTitle.textColor = Theme.shared.textSecondary
        userTitle.textColor = Theme.shared.textSecondary
        sessionTable.reloadData()
        userTable.reloadData()
    }

    private func buildLayout() {
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(refreshButton)

        sessionTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        sessionTitle.translatesAutoresizingMaskIntoConstraints = false
        userTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        userTitle.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(sessionTitle)
        contentContainer.addSubview(userTitle)

        let sessionColumns: [(String, String, CGFloat, NSTextAlignment)] = [
            ("user", "用户", 140, .left),
            ("line", "会话", 140, .left),
            ("host", "来源", 160, .left),
            ("kind", "类型", 100, .left),
            ("time", "登录时间", 160, .left),
        ]
        for column in sessionColumns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableColumn.minWidth = 60
            tableColumn.resizingMask = .userResizingMask
            sessionTable.addTableColumn(tableColumn)
        }
        sessionTable.headerView = NSTableHeaderView()
        sessionTable.rowHeight = 24
        sessionTable.dataSource = self
        sessionTable.delegate = self
        sessionTable.style = .fullWidth
        sessionTable.autoresizingMask = [.width]

        let userColumns: [(String, String, CGFloat, NSTextAlignment)] = [
            ("username", "用户名", 160, .left),
            ("uid", "UID", 80, .right),
            ("home", "家目录", 300, .left),
            ("shell", "Shell", 160, .left),
        ]
        for column in userColumns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableColumn.minWidth = 60
            userTable.addTableColumn(tableColumn)
        }
        userTable.headerView = NSTableHeaderView()
        userTable.rowHeight = 24
        userTable.dataSource = self
        userTable.delegate = self
        userTable.style = .fullWidth
        userTable.autoresizingMask = [.width]

        let sessionScroll = NSScrollView()
        sessionScroll.documentView = sessionTable
        sessionScroll.hasVerticalScroller = true
        sessionScroll.autohidesScrollers = true
        sessionScroll.drawsBackground = false
        sessionScroll.translatesAutoresizingMaskIntoConstraints = false

        let userScroll = NSScrollView()
        userScroll.documentView = userTable
        userScroll.hasVerticalScroller = true
        userScroll.autohidesScrollers = true
        userScroll.drawsBackground = false
        userScroll.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(sessionScroll)
        contentContainer.addSubview(userScroll)

        NSLayoutConstraint.activate([
            refreshButton.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            sessionTitle.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 6),
            sessionTitle.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),

            sessionScroll.topAnchor.constraint(equalTo: sessionTitle.bottomAnchor, constant: 4),
            sessionScroll.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            sessionScroll.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            sessionScroll.heightAnchor.constraint(equalToConstant: 128),

            userTitle.topAnchor.constraint(equalTo: sessionScroll.bottomAnchor, constant: 8),
            userTitle.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),

            userScroll.topAnchor.constraint(equalTo: userTitle.bottomAnchor, constant: 4),
            userScroll.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            userScroll.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            userScroll.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    @objc private func refreshTapped() {
        reload()
    }

    private func reload() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sessions = Self.loadSessions()
            let users = Self.loadUsers()
            DispatchQueue.main.async {
                guard let self else { return }
                self.sessions = sessions
                self.users = users
                self.sessionTable.reloadData()
                self.userTable.reloadData()
            }
        }
    }

    private static func loadSessions() -> [SessionItem] {
        var results: [SessionItem] = []
        var seen = Set<String>()
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            let element = entry.pointee
            guard element.ut_type == USER_PROCESS else { continue }
            let user = withUnsafeBytes(of: element.ut_user) { raw in
                String(bytes: raw.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            }
            let line = withUnsafeBytes(of: element.ut_line) { raw in
                String(bytes: raw.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            }
            let host = withUnsafeBytes(of: element.ut_host) { raw in
                String(bytes: raw.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            }
            let time = Date(timeIntervalSince1970: TimeInterval(element.ut_tv.tv_sec) + TimeInterval(element.ut_tv.tv_usec) / 1_000_000.0)
            // getutxent 可能返回重复条目（同一 console 会话出现两次）
            let key = "\(user)|\(line)|\(element.ut_tv.tv_sec)"
            guard seen.insert(key).inserted else { continue }

            let kind: String
            if line.hasPrefix("console") {
                kind = "控制台"
            } else if line.hasPrefix("ttys") {
                kind = "终端"
            } else if !host.isEmpty {
                kind = "远程"
            } else {
                kind = "本地"
            }
            results.append(SessionItem(user: user, line: line, host: host, kind: kind, loginTime: time))
        }
        return results
    }

    private static func loadUsers() -> [LocalUser] {
        var results: [LocalUser] = []
        var seen = Set<uid_t>()
        setpwent()
        defer { endpwent() }
        while let entry = getpwent() {
            let passwd = entry.pointee
            // 排除系统服务账户（nobody 的 UID 以 -2/-1 形式回绕成 4294967xxx）
            guard passwd.pw_uid >= 500, passwd.pw_uid < 0x8000_0000 else { continue }
            guard seen.insert(passwd.pw_uid).inserted else { continue }
            let name = String(cString: passwd.pw_name)
            let home = String(cString: passwd.pw_dir)
            let shell = String(cString: passwd.pw_shell)
            results.append(LocalUser(name: name, uid: passwd.pw_uid, home: home, shell: shell))
        }
        return results.sorted { $0.uid < $1.uid }
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === sessionTable ? sessions.count : users.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let theme = Theme.shared

        if tableView === sessionTable {
            guard row < sessions.count else { return nil }
            let item = sessions[row]
            let identifier = NSUserInterfaceItemIdentifier("session-" + tableColumn.identifier.rawValue)
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TextCellView) ?? TextCellView()
            cell.identifier = identifier
            switch tableColumn.identifier.rawValue {
            case "user": cell.update(text: item.user, alignment: .left, color: theme.textPrimary)
            case "line": cell.update(text: item.line, alignment: .left, color: theme.textSecondary)
            case "host": cell.update(text: item.host.isEmpty ? "—" : item.host, alignment: .left, color: theme.textSecondary)
            case "kind": cell.update(text: item.kind, alignment: .left, color: theme.textSecondary)
            case "time": cell.update(text: Formats.date(item.loginTime), alignment: .left, color: theme.textSecondary)
            default: return nil
            }
            return cell
        }

        guard row < users.count else { return nil }
        let item = users[row]
        let identifier = NSUserInterfaceItemIdentifier("user-" + tableColumn.identifier.rawValue)
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TextCellView) ?? TextCellView()
        cell.identifier = identifier
        switch tableColumn.identifier.rawValue {
        case "username": cell.update(text: item.name, alignment: .left, color: theme.textPrimary)
        case "uid": cell.update(text: "\(item.uid)", alignment: .right, color: theme.textSecondary)
        case "home": cell.update(text: item.home, alignment: .left, color: theme.textSecondary)
        case "shell": cell.update(text: item.shell, alignment: .left, color: theme.textSecondary)
        default: return nil
        }
        return cell
    }
}