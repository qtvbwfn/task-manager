import Foundation

enum PanelID: String, CaseIterable {
    case summary, performance, processes, systemInfo, startup, users, services

    var title: String {
        switch self {
        case .summary: return "系统概要"
        case .performance: return "性能"
        case .processes: return "进程"
        case .systemInfo: return "系统信息"
        case .startup: return "登录项"
        case .users: return "用户"
        case .services: return "服务"
        }
    }

    var icon: String {
        switch self {
        case .summary: return "gauge"
        case .performance: return "chart.xyaxis.line"
        case .processes: return "list.bullet.rectangle"
        case .systemInfo: return "info.circle"
        case .startup: return "play.circle"
        case .users: return "person.2"
        case .services: return "gearshape.2"
        }
    }
}

enum ProcessViewMode: String, CaseIterable {
    case all, apps, mine

    var title: String {
        switch self {
        case .all: return "全部"
        case .apps: return "仅应用程序"
        case .mine: return "我的进程"
        }
    }
}

/// UserDefaults 封装。键名见方案 10.8。
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let appearance = "tm.appearance"
        static let sampleInterval = "tm.sampleInterval" // 秒：2 / 1 / 0.5
        static let processView = "tm.processView"
        static let startupPanel = "tm.startupPanel"
    }

    private init() {}

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: Key.appearance)) ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    /// 采样间隔（秒）：2 / 1 / 0.5，对应 0.5 / 1 / 2 Hz
    var sampleInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.sampleInterval)
            return v > 0 ? v : 1.0
        }
        set { defaults.set(newValue, forKey: Key.sampleInterval) }
    }

    var processView: ProcessViewMode {
        get { ProcessViewMode(rawValue: defaults.string(forKey: Key.processView) ?? "") ?? .all }
        set { defaults.set(newValue.rawValue, forKey: Key.processView) }
    }

    var startupPanel: PanelID {
        get { PanelID(rawValue: defaults.string(forKey: Key.startupPanel) ?? "") ?? .summary }
        set { defaults.set(newValue.rawValue, forKey: Key.startupPanel) }
    }
}