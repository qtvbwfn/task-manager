import AppKit
import Darwin

final class ProcessGroupNode: NSObject {
    let title: String
    var children: [ProcessNode]

    init(title: String, children: [ProcessNode]) {
        self.title = title
        self.children = children
    }
}

final class ProcessNode: NSObject {
    var info: ProcessInfo
    var children: [ProcessNode] = []

    init(info: ProcessInfo) {
        self.info = info
    }
}

final class ProcessesPanelViewController: PanelBaseViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private let viewPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let searchField = NSSearchField()
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let detailView = ProcessDetailView()

    private var groups: [ProcessGroupNode] = []
    private var nodeCache: [pid_t: ProcessNode] = [:]
    private var expandedPids: Set<pid_t> = []
    private var selectedPid: pid_t?
    private var sortKey = "cpu"
    private var sortAscending = false
    private var isVisiblePanel = false
    private var reloadCounter = 0

    private let iconCache = NSCache<NSString, NSImage>()

    private static let architecture: String = {
        var buffer = [CChar](repeating: 0, count: 64)
        var size = 64
        let result = sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return result == 0 ? String(cString: buffer) : "未知"
    }()

    init() { super.init(title: "进程") }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
        setupTable()
        setupDetail()
        NotificationCenter.default.addObserver(self, selector: #selector(samplerUpdated), name: .samplerDidUpdate, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isVisiblePanel = true
        reloadCounter = 0
        // 设置页修改"进程默认视图"后即时同步到本页工具栏
        viewPopup.selectItem(at: ProcessViewMode.allCases.firstIndex(of: Settings.shared.processView) ?? 0)
        reloadTree()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        isVisiblePanel = false
    }

    override func applyTheme() {
        super.applyTheme()
        outlineView.reloadData()
        detailView.applyTheme()
    }

    // MARK: - 布局

    private func setupToolbar() {
        let viewLabel = NSTextField(labelWithString: "视图")
        viewLabel.font = .systemFont(ofSize: 13)
        viewLabel.textColor = Theme.shared.textSecondary
        viewLabel.setContentHuggingPriority(.required, for: .horizontal)

        viewPopup.addItems(withTitles: ProcessViewMode.allCases.map(\.title))
        viewPopup.selectItem(at: ProcessViewMode.allCases.firstIndex(of: Settings.shared.processView) ?? 0)
        viewPopup.target = self
        viewPopup.action = #selector(viewModeChanged)

        searchField.placeholderString = "按名称、用户或 PID 筛选"
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 13)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let toolbar = NSStackView(views: [viewLabel, viewPopup, NSView(), searchField])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 2),
            toolbar.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])
    }

    private func setupTable() {
        // 列宽按最宽可能内容实测收紧（monospacedDigit 13pt）：PID 7 位 57pt、CPU "100.0%" 49pt、
        // 内存 "999.9 MB"/"999.99 GB" ≤67pt、状态 "运行中" 39pt、用户 "windowserver" 84pt，
        // 剩余宽度全部让给名称列（firstColumnOnlyAutoresizing）
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        func fitted(_ text: String, padding: CGFloat = 10) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: mono]).width) + padding
        }
        let columns: [(id: String, title: String, width: CGFloat, minWidth: CGFloat, alignment: NSTextAlignment)] = [
            ("name", "名称", 320, 180, .left),
            ("pid", "PID", fitted("9999999"), 44, .right),
            ("status", "状态", fitted("运行中"), 44, .left),
            ("user", "用户", fitted("windowserver"), 56, .left),
            ("cpu", "CPU", fitted("100.0%"), 46, .right),
            ("memory", "内存", max(fitted("999.9 MB"), fitted("999.99 GB")), 58, .right),
        ]

        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.minWidth
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.id, ascending: column.id != "cpu" && column.id != "memory")
            outlineView.addTableColumn(tableColumn)
        }
        outlineView.outlineTableColumn = outlineView.tableColumns.first
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = 24
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.style = .fullWidth
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.sortDescriptors = [NSSortDescriptor(key: "cpu", ascending: false)]
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.autoresizingMask = [.width]
        // 列间距归零：默认 17pt 横向间隙 × 5 个间隙浪费 85pt 名称列宽度
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)

        let menu = NSMenu()
        let killItem = menu.addItem(withTitle: "结束进程…", action: #selector(killSelectedProcess), keyEquivalent: "")
        killItem.target = self
        menu.delegate = self
        outlineView.menu = menu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(scrollView)
    }

    private func setupDetail() {
        detailView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(detailView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 36),
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            detailView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            detailView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            detailView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            detailView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            detailView.heightAnchor.constraint(equalToConstant: 144),
        ])
    }

    // MARK: - 数据

    @objc private func samplerUpdated() {
        guard isVisiblePanel else { return }
        reloadCounter += 1
        if reloadCounter % 2 == 0 {
            reloadTree()
        } else {
            updateVisibleRows()
        }
    }

    /// 非结构刷新：只更新已创建节点的数值并重绘可见行，避免每秒重建整棵树。
    private func updateVisibleRows() {
        let snapshot = Sampler.shared.processes
        for info in snapshot {
            nodeCache[info.pid]?.info = info
        }
        let visible = outlineView.rows(in: outlineView.visibleRect)
        let cpuColumn = outlineView.column(withIdentifier: NSUserInterfaceItemIdentifier("cpu"))
        if visible.length > 0, cpuColumn >= 0 {
            // 只刷可见行的 CPU 列；其余列随 0.5 Hz 的结构刷新更新
            outlineView.reloadData(
                forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                columnIndexes: IndexSet(integer: cpuColumn)
            )
        }
        refreshSelectedDetail()
    }

    @objc private func viewModeChanged() {
        Settings.shared.processView = ProcessViewMode.allCases[viewPopup.indexOfSelectedItem]
        reloadTree()
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadTree()
    }

    private func comparator(_ a: ProcessInfo, _ b: ProcessInfo) -> Bool {
        let result: ComparisonResult
        switch sortKey {
        case "name": result = a.name < b.name ? .orderedAscending : (a.name > b.name ? .orderedDescending : .orderedSame)
        case "pid": result = a.pid < b.pid ? .orderedAscending : (a.pid > b.pid ? .orderedDescending : .orderedSame)
        case "status": result = a.statusName < b.statusName ? .orderedAscending : (a.statusName > b.statusName ? .orderedDescending : .orderedSame)
        case "user": result = a.userName < b.userName ? .orderedAscending : (a.userName > b.userName ? .orderedDescending : .orderedSame)
        case "cpu": result = a.cpuPercent < b.cpuPercent ? .orderedAscending : (a.cpuPercent > b.cpuPercent ? .orderedDescending : .orderedSame)
        case "memory": result = a.footprint < b.footprint ? .orderedAscending : (a.footprint > b.footprint ? .orderedDescending : .orderedSame)
        default: result = .orderedSame
        }
        if result == .orderedSame { return a.pid < b.pid }
        return sortAscending ? result == .orderedAscending : result == .orderedDescending
    }

    private func reloadTree() {
        guard isVisiblePanel else { return }
        let snapshot = Sampler.shared.processes
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let mode = ProcessViewMode.allCases[viewPopup.indexOfSelectedItem]

        let filtered = snapshot.filter { process in
            if mode == .mine && process.uid != getuid() { return false }
            guard !query.isEmpty else { return true }
            return process.name.lowercased().contains(query)
                || process.userName.lowercased().contains(query)
                || String(process.pid).contains(query)
        }
        var newGroups: [ProcessGroupNode] = []
        var alivePids = Set<pid_t>(minimumCapacity: filtered.count)

        func node(for info: ProcessInfo) -> ProcessNode {
            alivePids.insert(info.pid)
            if let cached = nodeCache[info.pid] {
                cached.info = info
                cached.children = []
                return cached
            }
            let created = ProcessNode(info: info)
            nodeCache[info.pid] = created
            return created
        }

        /// 按 ppid 把同一组内的进程连成树；父进程不在组内的一律作为根。
        func buildForest(_ members: [ProcessInfo]) -> [ProcessNode] {
            var byPid: [pid_t: ProcessNode] = [:]
            for info in members { byPid[info.pid] = node(for: info) }

            var roots: [ProcessNode] = []
            for info in members {
                guard let current = byPid[info.pid] else { continue }
                if info.ppid != info.pid, let parent = byPid[info.ppid] {
                    parent.children.append(current)
                } else {
                    roots.append(current)
                }
            }

            func sortTree(_ current: ProcessNode) {
                current.children.sort { comparator($0.info, $1.info) }
                current.children.forEach(sortTree)
            }
            roots.forEach(sortTree)
            return roots
        }

        if mode == .mine {
            let nodes = filtered.sorted(by: comparator).map { node(for: $0) }
            newGroups.append(ProcessGroupNode(title: "我的进程 (\(nodes.count))", children: nodes))
        } else {
            // 应用程序：按 .app bundle 分组（组内按 ppid 连树，子进程缩进一级）
            var bundleMembers: [String: [ProcessInfo]] = [:]
            var backgroundInfos: [ProcessInfo] = []
            for process in filtered {
                if let bundle = process.appBundlePath {
                    bundleMembers[bundle, default: []].append(process)
                } else {
                    backgroundInfos.append(process)
                }
            }

            var appRoots: [ProcessNode] = []
            for members in bundleMembers.values {
                appRoots.append(contentsOf: buildForest(members))
            }
            appRoots.sort { comparator($0.info, $1.info) }

            let backgroundRoots = buildForest(backgroundInfos).sorted { comparator($0.info, $1.info) }

            if !appRoots.isEmpty {
                newGroups.append(ProcessGroupNode(title: "应用程序 (\(appRoots.count))", children: appRoots))
            }
            if mode != .apps && !backgroundRoots.isEmpty {
                newGroups.append(ProcessGroupNode(title: "后台 (\(backgroundRoots.count))", children: backgroundRoots))
            }
        }

        nodeCache = nodeCache.filter { alivePids.contains($0.key) }
        groups = newGroups

        outlineView.reloadData()
        for group in groups {
            outlineView.expandItem(group)
        }
        for node in expandedNodes(in: groups) {
            outlineView.expandItem(node)
        }
        restoreSelection()
        refreshSelectedDetail()
    }

    private func refreshSelectedDetail() {
        guard let pid = selectedPid,
              let info = Sampler.shared.processes.first(where: { $0.pid == pid }) else {
            detailView.update(info: nil, parentName: nil)
            return
        }
        let parentName = Sampler.shared.processes.first(where: { $0.pid == info.ppid })?.name
        detailView.update(info: info, parentName: parentName, detail: Sampler.shared.processDetail(pid: pid))
    }

    private func expandedNodes(in groups: [ProcessGroupNode]) -> [ProcessNode] {
        var result: [ProcessNode] = []
        for group in groups {
            for node in group.children where expandedPids.contains(node.info.pid) {
                result.append(node)
            }
        }
        return result
    }

    private func restoreSelection() {
        guard let pid = selectedPid else { return }
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? ProcessNode, node.info.pid == pid {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                return
            }
        }
        selectedPid = nil
        detailView.update(info: nil, parentName: nil)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let group = item as? ProcessGroupNode { return group.children.count }
        if let node = item as? ProcessNode { return node.children.count }
        return groups.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? ProcessGroupNode { return group.children[index] }
        if let node = item as? ProcessNode { return node.children[index] }
        return groups[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let group = item as? ProcessGroupNode { return !group.children.isEmpty }
        if let node = item as? ProcessNode { return !node.children.isEmpty }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? { nil }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let tableColumn else { return nil }

        if let group = item as? ProcessGroupNode {
            guard tableColumn == outlineView.outlineTableColumn else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("group")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? GroupCellView) ?? GroupCellView()
            cell.identifier = identifier
            cell.update(title: group.title, color: Theme.shared.textSecondary)
            return cell
        }

        guard let node = item as? ProcessNode else { return nil }
        let info = node.info
        let theme = Theme.shared

        switch tableColumn.identifier.rawValue {
        case "name":
            let identifier = NSUserInterfaceItemIdentifier("name")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NameCellView) ?? NameCellView()
            cell.identifier = identifier
            cell.update(name: info.name, icon: icon(for: info), color: theme.textPrimary)
            return cell
        case "pid":
            return textCell(outlineView, id: "pid", text: "\(info.pid)", alignment: .right, secondary: true)
        case "status":
            return textCell(outlineView, id: "status", text: info.statusName, alignment: .left, secondary: true)
        case "user":
            return textCell(outlineView, id: "user", text: info.userName, alignment: .left, secondary: true)
        case "cpu":
            let color = info.cpuPercent >= 0.05 ? theme.color(.cpu) : theme.textSecondary
            let identifier = NSUserInterfaceItemIdentifier("cpu")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? CPUCellView) ?? CPUCellView()
            cell.identifier = identifier
            cell.update(
                text: Formats.percent(info.cpuPercent),
                alignment: .right,
                color: color,
                ratio: min(max(info.cpuPercent / 100.0, 0), 1),
                fillColor: theme.color(.cpu)
            )
            return cell
        case "memory":
            return textCell(outlineView, id: "memory", text: Formats.memory(info.footprint), alignment: .right, color: theme.textPrimary)
        default:
            return nil
        }
    }

    private func textCell(_ outlineView: NSOutlineView, id: String, text: String, alignment: NSTextAlignment, secondary: Bool = false, color: NSColor? = nil) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("text-" + id)
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? TextCellView) ?? TextCellView()
        cell.identifier = identifier
        cell.update(text: text, alignment: alignment, color: color ?? (secondary ? Theme.shared.textSecondary : Theme.shared.textPrimary))
        return cell
    }

    private func icon(for info: ProcessInfo) -> NSImage? {
        if let bundle = info.appBundlePath {
            if let cached = iconCache.object(forKey: bundle as NSString) { return cached }
            // 缩小到 32px 位图再缓存：系统返回的原始图标可能是 512px 位图，多应用缓存会吃掉几十 MB
            let image = Self.downsampleIcon(NSWorkspace.shared.icon(forFile: bundle))
            iconCache.setObject(image, forKey: bundle as NSString)
            return image
        }
        return NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)
    }

    private static func downsampleIcon(_ source: NSImage) -> NSImage {
        let side = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return source }

        rep.size = NSSize(width: 16, height: 16)
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            source.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(rep)
        return image
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is ProcessNode
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? ProcessNode else {
            selectedPid = nil
            detailView.update(info: nil, parentName: nil)
            return
        }
        selectedPid = node.info.pid
        refreshSelectedDetail()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? ProcessNode {
            expandedPids.insert(node.info.pid)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? ProcessNode {
            expandedPids.remove(node.info.pid)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = outlineView.sortDescriptors.first, let key = descriptor.key else { return }
        sortKey = key
        sortAscending = descriptor.ascending
        reloadTree()
    }

    // MARK: - 结束进程

    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        menu.items.forEach { $0.isEnabled = (outlineView.item(atRow: row) as? ProcessNode) != nil }
    }

    @objc private func killSelectedProcess() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? ProcessNode else { return }
        let info = node.info

        let alert = NSAlert()
        alert.messageText = "结束进程“\(info.name)”(PID \(info.pid))？"
        alert.informativeText = info.uid == 0 || info.pid <= 100
            ? "该进程属于系统关键进程或 root 用户，需要管理员授权。未保存的数据可能丢失。"
            : "未保存的数据可能丢失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "结束进程")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        terminate(pid: info.pid, signal: SIGTERM)
    }

    private func terminate(pid: pid_t, signal: Int32) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if kill(pid, signal) == 0 {
                if signal == SIGTERM {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.checkTerminated(pid: pid) }
                }
                return
            }
            guard errno == EPERM else {
                DispatchQueue.main.async { self?.showAlert(message: "无法结束进程", info: "错误码 \(errno)") }
                return
            }
            // 权限不足：先 sudo（pam_tid → TouchID），失败回退 osascript（密码框）
            if Self.runSudoKill(pid: pid, signal: signal) || Self.runOsascriptKill(pid: pid, signal: signal) {
                if signal == SIGTERM {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.checkTerminated(pid: pid) }
                }
            } else {
                DispatchQueue.main.async { self?.showAlert(message: "无法获得授权", info: "未能结束进程 \(pid)。") }
            }
        }
    }

    private func checkTerminated(pid: pid_t) {
        var buffer = [CChar](repeating: 0, count: 1024)
        if proc_pidpath(pid, &buffer, 1024) > 0 {
            let alert = NSAlert()
            alert.messageText = "进程 \(pid) 未退出"
            alert.informativeText = "是否强制结束(SIGKILL)?"
            alert.addButton(withTitle: "强制结束")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .warning
            if alert.runModal() == .alertFirstButtonReturn {
                terminate(pid: pid, signal: SIGKILL)
            }
        }
    }

    private func showAlert(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }

    private static func runSudoKill(pid: pid_t, signal: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["kill", "-\(signal)", "\(pid)"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func runOsascriptKill(pid: pid_t, signal: Int32) -> Bool {
        let script = "do shell script \"kill -\(signal) \(pid)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

extension ProcessesPanelViewController: SearchFocusable {
    @objc func focusSearch(_ sender: Any?) {
        view.window?.makeFirstResponder(searchField)
    }
}

// MARK: - 单元格

final class GroupCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, color: NSColor) {
        label.stringValue = title
        label.textColor = color
    }
}

final class TextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private var baseColor: NSColor = .labelColor

    init() {
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { label.textColor = backgroundStyle == .emphasized ? .white : baseColor }
    }

    func update(text: String, alignment: NSTextAlignment, color: NSColor) {
        label.stringValue = text
        label.alignment = alignment
        baseColor = color
        label.textColor = backgroundStyle == .emphasized ? .white : color
    }
}

final class CPUCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private var fillRatio: CGFloat = 0
    private var fillColor: NSColor = .systemGreen
    private var baseColor: NSColor = .labelColor

    init() {
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { label.textColor = backgroundStyle == .emphasized ? .white : baseColor }
    }

    func update(text: String, alignment: NSTextAlignment, color: NSColor, ratio: CGFloat, fillColor: NSColor) {
        label.stringValue = text
        label.alignment = alignment
        baseColor = color
        self.fillColor = fillColor
        fillRatio = min(max(ratio, 0), 1)
        label.textColor = backgroundStyle == .emphasized ? .white : color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // CPU% 绿色横条背景（方案 §4.2）
        if fillRatio > 0, bounds.width > 4 {
            let barRect = NSRect(
                x: 1,
                y: 3,
                width: max((bounds.width - 2) * fillRatio, 2),
                height: max(bounds.height - 6, 2)
            )
            let path = NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3)
            fillColor.withAlphaComponent(0.20).setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }
}

final class NameCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var baseColor: NSColor = .labelColor

    init() {
        super.init(frame: .zero)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        imageView = iconView

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let emphasized = backgroundStyle == .emphasized
            label.textColor = emphasized ? .white : baseColor
            iconView.contentTintColor = emphasized ? .white : baseColor
        }
    }

    func update(name: String, icon: NSImage?, color: NSColor) {
        label.stringValue = name
        baseColor = color
        label.textColor = backgroundStyle == .emphasized ? .white : color
        iconView.image = icon
        iconView.contentTintColor = backgroundStyle == .emphasized ? .white : color
    }
}

// MARK: - 详情面板

final class ProcessDetailView: NSView {
    private let headerLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let sectionsStack = NSStackView()
    private let placeholderLabel = NSTextField(labelWithString: "选择一个进程查看详情")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        headerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pathLabel)

        sectionsStack.orientation = .horizontal
        sectionsStack.alignment = .top
        sectionsStack.distribution = .fillEqually
        sectionsStack.spacing = 14
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionsStack)

        placeholderLabel.font = .systemFont(ofSize: 13)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),

            pathLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 1),
            pathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            sectionsStack.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 6),
            sectionsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sectionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            sectionsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),

            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyTheme()
        update(info: nil, parentName: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyTheme() {
        let theme = Theme.shared
        layer?.backgroundColor = theme.cardBackground.cgColor
        layer?.borderColor = theme.separator.cgColor
        headerLabel.textColor = theme.textPrimary
        pathLabel.textColor = theme.textSecondary
        placeholderLabel.textColor = theme.textSecondary
        for column in sectionsStack.arrangedSubviews {
            (column as? DetailSectionView)?.applyTheme()
        }
    }

    func update(info: ProcessInfo?, parentName: String?, detail: ProcessDetail? = nil) {
        placeholderLabel.isHidden = info != nil
        headerLabel.isHidden = info == nil
        pathLabel.isHidden = info == nil
        sectionsStack.isHidden = info == nil

        guard let info else { return }

        headerLabel.stringValue = "\(info.name) (\(info.pid))"
        pathLabel.stringValue = info.executablePath.isEmpty ? "路径不可用" : info.executablePath

        sectionsStack.arrangedSubviews.forEach {
            sectionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let identity = DetailSectionView(title: "身份", rows: [
            ("父进程", parentName.map { "\($0) (\(info.ppid))" } ?? "\(info.ppid)"),
            ("用户", info.userName),
            ("状态", info.statusName),
            ("架构", ProcessesPanelViewController.architectureName),
        ])
        let lifetime = DetailSectionView(title: "生命周期", rows: [
            ("启动", Formats.date(info.startTime)),
            ("运行时长", Formats.uptime(info.uptime)),
            ("线程数", "\(info.threads)"),
            ("优先级", "\(info.priority)"),
        ])
        let processor = DetailSectionView(title: "处理器", rows: [
            ("CPU", Formats.percent(info.cpuPercent)),
            ("CPU 时间", Formats.cpuTime(info.cpuTimeNanos)),
        ])
        let memory = DetailSectionView(title: "内存", rows: [
            ("Footprint", Formats.memory(detail?.footprint ?? info.resident)),
            ("常驻内存", Formats.memory(detail?.resident ?? info.resident)),
            ("缺页", "\(info.faults)"),
        ])
        let diskRows: [(String, String)]
        if let detail {
            diskRows = [
                ("读取速率", Formats.rate(detail.diskReadPerSecond)),
                ("写入速率", Formats.rate(detail.diskWritePerSecond)),
                ("读取总量", Formats.memory(detail.diskBytesRead)),
                ("写入总量", Formats.memory(detail.diskBytesWritten)),
            ]
        } else {
            diskRows = [("磁盘 IO", "不可用")]
        }
        let disk = DetailSectionView(title: "磁盘", rows: diskRows)

        [identity, lifetime, processor, memory, disk].forEach { sectionsStack.addArrangedSubview($0) }
        applyTheme()
    }
}

final class DetailSectionView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private var valueLabels: [(label: NSTextField, value: NSTextField)] = []

    init(title: String, rows: [(String, String)]) {
        super.init(frame: .zero)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 2
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            rowsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            rowsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])

        for (label, value) in rows {
            let labelView = NSTextField(labelWithString: label)
            labelView.font = .systemFont(ofSize: 11)
            labelView.setContentHuggingPriority(.required, for: .horizontal)

            let valueView = NSTextField(labelWithString: value)
            valueView.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            valueView.lineBreakMode = .byTruncatingTail
            valueView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let row = NSStackView(views: [labelView, valueView])
            row.orientation = .horizontal
            row.spacing = 5
            row.alignment = .firstBaseline
            rowsStack.addArrangedSubview(row)
            valueLabels.append((labelView, valueView))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyTheme() {
        let theme = Theme.shared
        titleLabel.textColor = theme.textSecondary
        for pair in valueLabels {
            pair.label.textColor = theme.textSecondary
            pair.value.textColor = theme.textPrimary
        }
    }
}

extension ProcessesPanelViewController {
    static var architectureName: String { architecture }
}