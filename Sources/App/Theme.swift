import AppKit

extension Notification.Name {
    static let themeDidChange = Notification.Name("tm.themeDidChange")
}

enum AppearanceMode: Int, CaseIterable {
    case auto = 0
    case light = 1
    case dark = 2

    var title: String {
        switch self {
        case .auto: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum SubsystemKind {
    case cpu, memory, gpu, disk, network, power, thermal
}

/// 双主题语义色。所有自绘视图在 draw 时经此解析颜色，主题切换即时生效。
final class Theme {
    static let shared = Theme()

    private var appearanceObservation: NSKeyValueObservation?

    private init() {
        // 跟随系统模式下，系统外观变化即时重绘
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            guard let self, self.mode == .auto else { return }
            self.notifyChange()
        }
    }

    var mode: AppearanceMode {
        get { Settings.shared.appearance }
        set {
            Settings.shared.appearance = newValue
            apply()
        }
    }

    var isDark: Bool {
        switch mode {
        case .auto:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua
        case .light:
            return false
        case .dark:
            return true
        }
    }

    func apply() {
        switch mode {
        case .auto:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    // MARK: - 语义色

    var windowBackground: NSColor { isDark ? NSColor(hex: 0x141414) : NSColor(hex: 0xF2F2F7) }
    var sidebarBackground: NSColor { isDark ? NSColor(hex: 0x0E0E0E) : NSColor(hex: 0xE9E9EE) }
    var statusBarBackground: NSColor { isDark ? NSColor(hex: 0x101010) : NSColor(hex: 0xE9E9EE) }
    var cardBackground: NSColor { isDark ? NSColor(hex: 0x1C1C1E) : .white }
    var textPrimary: NSColor { isDark ? .white : NSColor(hex: 0x1C1C1E) }
    var textSecondary: NSColor { isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(hex: 0x6E6E73) }
    var separator: NSColor { isDark ? NSColor(hex: 0x2A2A2A) : NSColor(hex: 0xD1D1D6) }

    var sidebarSelectionBg: NSColor { isDark ? NSColor(hex: 0x2F2F5A) : NSColor(hex: 0xD8D8F0) }
    var sidebarSelectionText: NSColor { isDark ? .white : NSColor(hex: 0x3D3D8F) }
    var sidebarHoverBg: NSColor { isDark ? NSColor(white: 1.0, alpha: 0.06) : NSColor(white: 0.0, alpha: 0.045) }

    var statusOk: NSColor { NSColor(hex: 0x34C759) }
    var statusWarn: NSColor { NSColor(hex: 0xFFCC00) }

    func color(_ kind: SubsystemKind) -> NSColor {
        switch kind {
        case .cpu:      return isDark ? NSColor(hex: 0x3FBF3F) : NSColor(hex: 0x2E9E2E)
        case .memory:   return isDark ? NSColor(hex: 0xC455F0) : NSColor(hex: 0xA437D8)
        case .gpu:      return isDark ? NSColor(hex: 0x4D9EF0) : NSColor(hex: 0x2673D9)
        case .disk:     return isDark ? NSColor(hex: 0x3FBF3F) : NSColor(hex: 0x2E9E2E)
        case .network:  return isDark ? NSColor(hex: 0x4D9EF0) : NSColor(hex: 0x2673D9)
        case .power:    return isDark ? NSColor(hex: 0xE8C547) : NSColor(hex: 0xB8960F)
        case .thermal:  return isDark ? NSColor(hex: 0xF08C3A) : NSColor(hex: 0xC25E12)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}