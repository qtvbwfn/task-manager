import Foundation

/// 历史快照：所有序列按时间顺序（最多 240 点）。
struct HistorySnapshot {
    var cpuTotal: [Double] = []
    var kernel: [Double] = []
    var perCore: [[Double]] = []
    var memoryUsed: [Double] = []
    var memoryAvailable: [Double] = []
    var memoryCached: [Double] = []
    var memoryCompressed: [Double] = []
    var swapUsed: [Double] = []
    var temperature: [Double] = []
    var gpuUtilization: [Double] = []
    var diskRead: [Double] = []
    var diskWrite: [Double] = []
    var diskActive: [Double] = []
    var networkIn: [Double] = []
    var networkOut: [Double] = []
    var watts: [Double] = []
}

final class HistoryStore {
    static let capacity = 240

    var cpuTotal = RingBuffer<Double>(capacity: capacity)
    var kernel = RingBuffer<Double>(capacity: capacity)
    var perCore: [RingBuffer<Double>] = []
    var memoryUsed = RingBuffer<Double>(capacity: capacity)
    var memoryAvailable = RingBuffer<Double>(capacity: capacity)
    var memoryCached = RingBuffer<Double>(capacity: capacity)
    var memoryCompressed = RingBuffer<Double>(capacity: capacity)
    var swapUsed = RingBuffer<Double>(capacity: capacity)
    var temperature = RingBuffer<Double>(capacity: capacity)
    var gpuUtilization = RingBuffer<Double>(capacity: capacity)
    var diskRead = RingBuffer<Double>(capacity: capacity)
    var diskWrite = RingBuffer<Double>(capacity: capacity)
    var diskActive = RingBuffer<Double>(capacity: capacity)
    var networkIn = RingBuffer<Double>(capacity: capacity)
    var networkOut = RingBuffer<Double>(capacity: capacity)
    var watts = RingBuffer<Double>(capacity: capacity)

    func append(system: SystemSnapshot) {
        if perCore.count != system.perCore.count {
            perCore = Array(repeating: RingBuffer<Double>(capacity: Self.capacity), count: system.perCore.count)
        }
        cpuTotal.append(system.cpuTotal)
        kernel.append(system.kernelPercent)
        for (index, value) in system.perCore.enumerated() {
            perCore[index].append(value)
        }
        memoryUsed.append(Double(system.memoryUsed))
        memoryAvailable.append(Double(system.memoryAvailable))
        memoryCached.append(Double(system.memoryCached))
        memoryCompressed.append(Double(system.memoryCompressed))
        swapUsed.append(Double(system.swapUsed))
    }

    func append(iokit: IOKitSample) {
        if let temperature = iokit.temperature { self.temperature.append(temperature) }
        if let gpu = iokit.gpuUtilization { gpuUtilization.append(gpu) }
        diskRead.append(iokit.diskReadPerSecond)
        diskWrite.append(iokit.diskWritePerSecond)
        diskActive.append(iokit.diskActiveTimePercent)
        if let watts = iokit.watts { self.watts.append(watts) }
    }

    func append(network: NetworkSampler.Sample) {
        networkIn.append(network.bytesInPerSecond)
        networkOut.append(network.bytesOutPerSecond)
    }

    func snapshot() -> HistorySnapshot {
        HistorySnapshot(
            cpuTotal: cpuTotal.values,
            kernel: kernel.values,
            perCore: perCore.map { $0.values },
            memoryUsed: memoryUsed.values,
            memoryAvailable: memoryAvailable.values,
            memoryCached: memoryCached.values,
            memoryCompressed: memoryCompressed.values,
            swapUsed: swapUsed.values,
            temperature: temperature.values,
            gpuUtilization: gpuUtilization.values,
            diskRead: diskRead.values,
            diskWrite: diskWrite.values,
            diskActive: diskActive.values,
            networkIn: networkIn.values,
            networkOut: networkOut.values,
            watts: watts.values
        )
    }
}

/// 调度核心：串行采样队列，只有可见面板需要的数据才会被采样。
final class Sampler {
    static let shared = Sampler()

    private let queue = DispatchQueue(label: "tm.sampler", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    private let processSampler = ProcessSampler()
    private let systemSampler = SystemSampler()
    private let iokitSampler = IOKitSampler()
    private let networkSampler = NetworkSampler()

    private var needsProcesses = false
    private var needsFastProcesses = false
    private var needsSystem = false
    private var active = false
    private var tickCount: UInt64 = 0
    /// 窗口关闭到 Dock / 最小化时为 true：降频到 0.25 Hz
    private var background = false

    private var storedProcesses: [ProcessInfo] = []
    private var storedSystem: SystemSnapshot?
    private var storedIOKit: IOKitSample?
    private var storedNetwork: NetworkSampler.Sample?
    private var history = HistoryStore()
    private var storedHistory = HistorySnapshot()

    var processes: [ProcessInfo] {
        lock.lock()
        defer { lock.unlock() }
        return storedProcesses
    }

    var system: SystemSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return storedSystem
    }

    var iokit: IOKitSample? {
        lock.lock()
        defer { lock.unlock() }
        return storedIOKit
    }

    var network: NetworkSampler.Sample? {
        lock.lock()
        defer { lock.unlock() }
        return storedNetwork
    }

    var historySnapshot: HistorySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return storedHistory
    }

    /// 选中进程的按需详情（Footprint / 磁盘 IO），只在进程页详情区使用。
    func processDetail(pid: pid_t) -> ProcessDetail? {
        processSampler.detail(pid: pid)
    }

    private init() {}

    /// 由 UI 层告知当前可见面板集合；空集合 = 暂停采样。
    func setPanels(_ panels: Set<PanelID>) {
        queue.async { [weak self] in
            guard let self else { return }
            self.needsProcesses = panels.contains(.processes) || panels.contains(.summary) || panels.contains(.performance)
            // 进程页需要 1 Hz 实时 CPU；系统概要/性能页进程列表可降到 0.5 Hz（Top 表本身 0.25 Hz 重排）
            self.needsFastProcesses = panels.contains(.processes)
            self.needsSystem = panels.contains(.summary) || panels.contains(.performance)
            let shouldRun = !panels.isEmpty
            if shouldRun != self.active {
                self.active = shouldRun
                shouldRun ? self.startTimer() : self.stopTimer()
            }
        }
    }

    /// 采样频率变化后重启定时器
    func restart() {
        queue.async { [weak self] in
            guard let self, self.active else { return }
            self.stopTimer()
            self.startTimer()
        }
    }

    /// 窗口关闭（驻留 Dock）或最小化：固定降到 0.25 Hz；重新可见时恢复设置频率。
    func setBackground(_ isBackground: Bool) {
        queue.async { [weak self] in
            guard let self, self.background != isBackground else { return }
            self.background = isBackground
            if self.active {
                self.stopTimer()
                self.startTimer()
            }
        }
    }

    private func startTimer() {
        stopTimer()
        let interval = background ? 4.0 : Settings.shared.sampleInterval
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        tickCount &+= 1
        let sampleProcesses = needsProcesses && (needsFastProcesses || tickCount % 2 == 0)
        let processes = sampleProcesses ? processSampler.sample() : nil
        let system = needsSystem ? systemSampler.sample() : nil
        var iokitSample: IOKitSample?
        var networkSample: NetworkSampler.Sample?
        if needsSystem {
            iokitSample = iokitSampler.sample()
            networkSample = networkSampler.sample()
        }

        lock.lock()
        if let processes { storedProcesses = processes }
        if let system {
            storedSystem = system
            history.append(system: system)
        }
        if let iokitSample {
            storedIOKit = iokitSample
            history.append(iokit: iokitSample)
        }
        if let networkSample {
            storedNetwork = networkSample
            history.append(network: networkSample)
        }
        storedHistory = history.snapshot()
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .samplerDidUpdate, object: nil)
        }
    }
}