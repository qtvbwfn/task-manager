import AppKit

/// 渲染开关：TM_NOGLOW=1 可关闭辉光（性能对比用）
enum RenderFlags {
    static let glow = Foundation.ProcessInfo.processInfo.environment["TM_NOGLOW"] == nil
}

/// 自绘折线图：网格 + 发光描边 + 右端三角游标。所有颜色经 Theme 解析，主题切换自动适配。
final class ChartView: NSView {
    struct Series {
        let values: [Double]
        let color: NSColor
        var fill: Bool = false
    }

    var series: [Series] = [] {
        didSet { needsDisplay = true }
    }
    var yMin: Double = 0
    var yMax: Double = 100
    var showsGrid = true
    var showsCursor = true
    var gridDivisions = 4
    var glow = true
    /// 历史缓冲容量：x 轴按固定容量取步长，数据不足时从左向右逐点追加（避免刚启动就被拉伸到全宽）。
    /// 设为 0 表示不预留空位，按当前点数铺满宽度（逐核迷你图用）
    var sampleCapacity = HistoryStore.capacity
    /// 双轴刻度：fraction 为自底部起在 0...1 区间的相对位置
    var leftAxisLabels: [(fraction: Double, text: String)] = [] { didSet { needsDisplay = true } }
    var rightAxisLabels: [(fraction: Double, text: String)] = [] { didSet { needsDisplay = true } }
    /// 轴刻度字号（温度页等需要比默认 9pt 更大的标注）
    var axisLabelFontSize: CGFloat = 9

    /// 刻度贴边叠绘在绘图区内（TMOG 式），不再预留边距挤占曲线宽度
    private var leftInset: CGFloat { 0 }
    private var rightInset: CGFloat { 0 }
    private var plotRect: NSRect {
        NSRect(x: leftInset, y: 0, width: max(bounds.width - leftInset - rightInset, 2), height: bounds.height)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        guard bounds.width > 2, bounds.height > 2 else { return }
        let plot = plotRect

        if showsGrid {
            drawGrid(context, bounds: plot)
        }

        let range = max(yMax - yMin, 0.0001)
        for item in series where item.values.count > 1 {
            let count = item.values.count
            let capacity = max(sampleCapacity, count, 2)
            let step = plot.width / CGFloat(capacity - 1)
            // 按像素宽度抽稀：517px 宽的图无需真画 240 个点
            let maxPoints = max(2, Int(plot.width / 2))
            let stride = max(1, Int(ceil(Double(count) / Double(maxPoints))))
            var points: [CGPoint] = []

            func appendPoint(_ index: Int) {
                let value = item.values[index]
                let x = plot.minX + CGFloat(index) * step
                let clamped = min(max(value, yMin), yMax)
                let y = plot.maxY - CGFloat((clamped - yMin) / range) * plot.height
                points.append(CGPoint(x: x, y: y))
            }

            var index = 0
            while index < count {
                appendPoint(index)
                index += stride
            }
            if (count - 1) % stride != 0 {
                appendPoint(count - 1)
            }

            // Catmull-Rom 平滑为三次贝塞尔（TMOG 式平缓），尖刺变圆滑
            let path = Self.smoothedPath(points)

            if item.fill, let first = item.values.first {
                let fillPath = path.mutableCopy()!
                let lastX = plot.minX + CGFloat(item.values.count - 1) * step
                let firstY = plot.maxY - CGFloat((min(max(first, yMin), yMax) - yMin) / range) * plot.height
                fillPath.addLine(to: CGPoint(x: lastX, y: plot.maxY))
                fillPath.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
                fillPath.addLine(to: CGPoint(x: plot.minX, y: firstY))
                fillPath.closeSubpath()
                context.setFillColor(item.color.withAlphaComponent(0.12).cgColor)
                context.addPath(fillPath)
                context.fillPath()
            }

            // 无 shadow 的"发光"：先描一条更粗的半透明线作光晕，再描实线（比 CG shadow 便宜一个量级）
            if glow && RenderFlags.glow {
                context.saveGState()
                context.setStrokeColor(item.color.withAlphaComponent(0.18).cgColor)
                context.setLineWidth(4.5)
                context.setLineJoin(.round)
                context.setLineCap(.round)
                context.addPath(path)
                context.strokePath()
                context.restoreGState()
            }

            context.saveGState()
            context.setStrokeColor(item.color.cgColor)
            context.setLineWidth(1.4)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }

        // 每条曲线末端各一个箭头游标，颜色随线（TMOG 式）
        if showsCursor {
            for item in series where item.values.count > 1 {
                let capacity = max(sampleCapacity, item.values.count, 2)
                let clamped = min(max(item.values.last!, yMin), yMax)
                let y = plot.maxY - CGFloat((clamped - yMin) / range) * plot.height
                let step = plot.width / CGFloat(capacity - 1)
                let x = min(plot.maxX - 5, plot.minX + CGFloat(item.values.count - 1) * step)
                let triangle = CGMutablePath()
                triangle.move(to: CGPoint(x: x - 3, y: y - 3))
                triangle.addLine(to: CGPoint(x: x + 3, y: y))
                triangle.addLine(to: CGPoint(x: x - 3, y: y + 3))
                triangle.closeSubpath()
                context.setFillColor(item.color.cgColor)
                context.addPath(triangle)
                context.fillPath()
            }
        }

        drawAxisLabels(in: plot)
    }

    /// Catmull-Rom → 三次贝塞尔：相邻点作切线控制点，尖刺变平缓（TMOG 式）
    private static func smoothedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        for index in 0..<(points.count - 1) {
            let previous = points[max(index - 1, 0)]
            let current = points[index]
            let next = points[index + 1]
            let after = points[min(index + 2, points.count - 1)]
            let control1 = CGPoint(x: current.x + (next.x - previous.x) / 6, y: current.y + (next.y - previous.y) / 6)
            let control2 = CGPoint(x: next.x - (after.x - current.x) / 6, y: next.y - (after.y - current.y) / 6)
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        return path
    }

    private func drawAxisLabels(in plot: NSRect) {
        guard !leftAxisLabels.isEmpty || !rightAxisLabels.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: axisLabelFontSize, weight: .regular),
            .foregroundColor: Theme.shared.textSecondary,
        ]

        func draw(_ labels: [(fraction: Double, text: String)], rightAligned: Bool) {
            for label in labels {
                let text = label.text as NSString
                let size = text.size(withAttributes: attributes)
                let y = min(max(plot.minY + plot.maxY - CGFloat(label.fraction) * plot.height - size.height / 2, 0), bounds.height - size.height)
                // 叠绘在绘图区边缘：左贴左、右贴右，不占曲线空间
                let x = rightAligned ? plot.maxX - size.width - 3 : plot.minX + 3
                text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            }
        }

        draw(leftAxisLabels, rightAligned: false)
        draw(rightAxisLabels, rightAligned: true)
    }

    private func drawGrid(_ context: CGContext, bounds: NSRect) {
        let color = Theme.shared.separator.withAlphaComponent(0.5).cgColor
        context.setStrokeColor(color)
        context.setLineWidth(0.5)

        for index in 0...gridDivisions {
            let y = bounds.height * CGFloat(index) / CGFloat(gridDivisions)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        let verticals = 6
        for index in 0...verticals {
            let x = bounds.width * CGFloat(index) / CGFloat(verticals)
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
        }
        context.strokePath()
    }
}

/// 迷你趋势线（无网格无刻度，只画曲线与右端游标）。
final class SparklineView: NSView {
    var values: [Double] = [] {
        didSet { needsDisplay = true }
    }
    var color: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }
    /// 与主图一致：数据不足 240 点时从左向右追加，不拉伸
    var sampleCapacity = HistoryStore.capacity

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 2, bounds.height > 2 else { return }
        guard values.count > 1 else { return }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 0.0001)

        let path = CGMutablePath()
        let capacity = max(sampleCapacity, values.count, 2)
        let step = bounds.width / CGFloat(capacity - 1)
        let maxPoints = max(2, Int(bounds.width / 2))
        let stride = max(1, Int(ceil(Double(values.count) / Double(maxPoints))))

        func append(_ index: Int) {
            let value = values[index]
            let x = CGFloat(index) * step
            let y = bounds.height - CGFloat((value - minValue) / range) * (bounds.height - 4) - 2
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        var index = 0
        while index < values.count {
            append(index)
            index += stride
        }
        if (values.count - 1) % stride != 0 {
            append(values.count - 1)
        }

        if RenderFlags.glow {
            context.saveGState()
            context.setStrokeColor(color.withAlphaComponent(0.20).cgColor)
            context.setLineWidth(3.6)
            context.setLineJoin(.round)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.2)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()

        if let last = values.last {
            let y = bounds.height - CGFloat((last - minValue) / range) * (bounds.height - 4) - 2
            let cursorX = min(bounds.width - 6, CGFloat(values.count - 1) * step)
            let triangle = CGMutablePath()
            triangle.move(to: CGPoint(x: cursorX, y: y - 2.5))
            triangle.addLine(to: CGPoint(x: cursorX + 5, y: y))
            triangle.addLine(to: CGPoint(x: cursorX, y: y + 2.5))
            triangle.closeSubpath()
            context.setFillColor(Theme.shared.textPrimary.cgColor)
            context.addPath(triangle)
            context.fillPath()
        }
    }
}

/// 分段式仪表：水平 / 垂直两种方向，点亮段带辉光。
final class SegmentedBarView: NSView {
    enum Orientation { case horizontal, vertical }

    var ratio: Double = 0 {
        didSet { needsDisplay = true }
    }
    var color: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }
    var orientation: Orientation = .horizontal
    var segmentCount = 30
    var segmentGap: CGFloat = 2

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        guard bounds.width > 4, bounds.height > 4 else { return }

        let isHorizontal = orientation == .horizontal
        let total = isHorizontal ? bounds.width : bounds.height
        let cross = isHorizontal ? bounds.height : bounds.width
        let segmentLength = (total - segmentGap * CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
        let filledCount = Int((min(max(ratio, 0), 1) * Double(segmentCount)).rounded())
        let radius = min(segmentLength / 2, cross / 2)

        // 先画未点亮段，再把所有点亮段合并成一个 path 只做一次 shadow（逐段 shadow 代价极高）
        for index in filledCount..<segmentCount {
            let rect = Self.segmentRect(index: index, cross: cross, segmentLength: segmentLength, gap: segmentGap, isHorizontal: isHorizontal)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            context.setFillColor(color.withAlphaComponent(0.15).cgColor)
            context.addPath(path)
            context.fillPath()
        }

        if filledCount > 0 {
            let litPath = CGMutablePath()
            for index in 0..<filledCount {
                let rect = Self.segmentRect(index: index, cross: cross, segmentLength: segmentLength, gap: segmentGap, isHorizontal: isHorizontal)
                litPath.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            context.saveGState()
            if RenderFlags.glow {
                context.setStrokeColor(color.withAlphaComponent(0.25).cgColor)
                context.setLineWidth(2)
                context.addPath(litPath)
                context.strokePath()
            }
            context.setFillColor(color.cgColor)
            context.addPath(litPath)
            context.fillPath()
            context.restoreGState()
        }
    }

    private static func segmentRect(index: Int, cross: CGFloat, segmentLength: CGFloat, gap: CGFloat, isHorizontal: Bool) -> CGRect {
        if isHorizontal {
            let x = CGFloat(index) * (segmentLength + gap)
            return CGRect(x: x, y: 0, width: segmentLength, height: cross)
        }
        // 垂直方向 index 0 在底部，点亮段自下而上填充
        let y = CGFloat(index) * (segmentLength + gap)
        return CGRect(x: 0, y: y, width: cross, height: segmentLength)
    }
}