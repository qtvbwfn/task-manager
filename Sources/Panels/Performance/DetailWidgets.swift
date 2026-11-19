import AppKit

// MARK: - 指标网格

final class MetricGridView: NSView {
    private var grid: NSGridView?
    private var valueLabels: [(label: NSTextField, value: NSTextField)] = []

    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(items: [(String, String)], columns: Int = 4) {
        grid?.removeFromSuperview()
        valueLabels.removeAll()

        var rows: [[NSView]] = []
        var currentRow: [NSView] = []

        for (label, value) in items {
            let labelView = NSTextField(labelWithString: label)
            labelView.font = .systemFont(ofSize: 14)
            labelView.textColor = Theme.shared.textSecondary
            labelView.setContentHuggingPriority(.required, for: .horizontal)

            let valueView = NSTextField(labelWithString: value)
            valueView.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
            valueView.textColor = Theme.shared.textPrimary
            valueView.lineBreakMode = .byTruncatingTail
            valueView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let column = NSStackView(views: [labelView, valueView])
            column.orientation = .vertical
            column.spacing = 1
            column.alignment = .leading
            currentRow.append(column)
            valueLabels.append((labelView, valueView))

            if currentRow.count == columns {
                rows.append(currentRow)
                currentRow = []
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        let newGrid = NSGridView(views: rows)
        newGrid.rowSpacing = 8
        newGrid.columnSpacing = 18
        newGrid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newGrid)
        // 列摊满整宽：多余宽度均分到所有 .fill 列，避免数据挤在左侧（对标 TMOG）
        for index in 0..<newGrid.numberOfColumns { newGrid.column(at: index).xPlacement = .fill }
        NSLayoutConstraint.activate([
            newGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            newGrid.trailingAnchor.constraint(equalTo: trailingAnchor),
            newGrid.topAnchor.constraint(equalTo: topAnchor),
            newGrid.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        grid = newGrid
    }

    func applyTheme() {
        for pair in valueLabels {
            pair.label.textColor = Theme.shared.textSecondary
            pair.value.textColor = Theme.shared.textPrimary
        }
    }
}

// MARK: - 等宽指标列（滚动历史）

final class StatColumnsView: NSView, ThemeAware {
    private let stack = NSStackView()
    private var cells: [(label: NSTextField, value: NSTextField)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(items: [(String, String)]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        cells.removeAll()

        for (title, value) in items {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13)
            label.textColor = Theme.shared.textSecondary

            let valueLabel = NSTextField(labelWithString: value)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
            valueLabel.textColor = Theme.shared.textPrimary
            valueLabel.lineBreakMode = .byTruncatingTail
            valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let column = NSStackView(views: [label, valueLabel])
            column.orientation = .vertical
            column.spacing = 2
            column.alignment = .leading
            stack.addArrangedSubview(column)
            cells.append((label, valueLabel))
        }
    }

    func update(values: [String]) {
        guard values.count == cells.count else { return }
        for (index, value) in values.enumerated() {
            cells[index].value.stringValue = value
        }
    }

    func applyTheme() {
        for cell in cells {
            cell.label.textColor = Theme.shared.textSecondary
            cell.value.textColor = Theme.shared.textPrimary
        }
    }
}

// MARK: - 双栏键值表（CPU 规格）

final class KeyValueColumnsView: NSView, ThemeAware {
    private let stack = NSStackView()
    private var pairs: [(label: NSTextField, value: NSTextField)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 每栏一组 (标签, 值)，两栏并排且行高固定，保证左右两栏逐行对齐
    func configure(columns: [[(String, String)]]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        pairs.removeAll()

        for items in columns where !items.isEmpty {
            var rows: [[NSView]] = []
            for (title, value) in items {
                let label = NSTextField(labelWithString: title)
                label.font = .systemFont(ofSize: 13)
                label.textColor = Theme.shared.textSecondary
                label.setContentHuggingPriority(.required, for: .horizontal)

                let valueLabel = NSTextField(labelWithString: value)
                valueLabel.font = .systemFont(ofSize: 13, weight: .medium)
                valueLabel.textColor = Theme.shared.textPrimary
                valueLabel.lineBreakMode = .byTruncatingTail
                valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                rows.append([label, valueLabel])
                pairs.append((label, valueLabel))
            }

            let grid = NSGridView(views: rows)
            grid.rowSpacing = 5
            for index in 0..<rows.count {
                grid.row(at: index).height = 20
            }
            grid.columnSpacing = 10
            grid.column(at: 0).width = 90
            grid.column(at: 0).xPlacement = .leading
            stack.addArrangedSubview(grid)
        }
    }

    func applyTheme() {
        for pair in pairs {
            pair.label.textColor = Theme.shared.textSecondary
            pair.value.textColor = Theme.shared.textPrimary
        }
    }
}
