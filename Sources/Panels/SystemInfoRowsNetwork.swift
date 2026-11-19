import Foundation

/// 系统信息 · 网络组页面 builder（Wi-Fi / 以太网 / 网络 / 位置 / 宗卷 / 防火墙）
extension SystemInfoPanelViewController {

    /// Wi-Fi：SPAirPortDataType（当前网络 / 附近网络 / 无线网卡信息）
    func wifiRows() -> [InfoRowSpec] {
        guard let entry = SPReader.first("SPAirPortDataType") else {
            return [.field("Wi-Fi", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        let wifiIfs = SPReader.array(entry, "spairport_airport_interfaces")
            .filter { !(SPReader.value($0, "_name") ?? "").hasPrefix("awdl") && !(SPReader.value($0, "_name") ?? "").hasPrefix("p2p") }
        for interface in wifiIfs {
            let name = SPReader.value(interface, "_name") ?? "Wi-Fi 接口"
            rows.append(.section(name))
            if let status = SPReader.value(interface, "spairport_status_information") {
                rows.append(.field("状态", SPMap.airportStatus(status)))
            }
            if let mac = SPReader.value(interface, "spairport_wireless_mac_address") {
                rows.append(.field("MAC 地址", mac))
            }
            if let firmware = SPReader.value(interface, "spairport_wireless_firmware_version") {
                rows.append(.field("无线固件", firmware))
            }
            // 当前网络
            if let current = interface["spairport_current_network_information"] as? [String: Any] {
                rows.append(.subSection("当前网络"))
                if let channel = SPReader.value(current, "spairport_network_channel") {
                    rows.append(.field("信道", channel))
                }
                if let phy = SPReader.value(current, "spairport_network_phymode") {
                    rows.append(.field("物理模式", phy))
                }
                if let rate = SPReader.value(current, "spairport_network_rate") {
                    rows.append(.field("速率", "\(rate) Mbps"))
                }
                if let security = SPReader.value(current, "spairport_security_mode") {
                    rows.append(.field("安全", SPMap.securityMode(security)))
                }
                if let signal = SPReader.value(current, "spairport_signal_noise") {
                    rows.append(.field("信号 / 噪声", signal))
                }
            }
            // 附近网络（只显示前 10 条）
            let others = SPReader.array(interface, "spairport_airport_other_local_wireless_networks")
            if !others.isEmpty {
                let shown = Array(others.prefix(10))
                for network in shown {
                    var line = "附近 · "
                    if let channel = SPReader.value(network, "spairport_network_channel") {
                        line += channel
                    }
                    if let security = SPReader.value(network, "spairport_security_mode") {
                        line += " · \(SPMap.securityMode(security))"
                    }
                    if let signal = SPReader.value(network, "spairport_signal_noise") {
                        line += " · \(signal)"
                    }
                    rows.append(.field("网络", line.trimmingCharacters(in: .whitespaces)))
                }
                if others.count > shown.count {
                    rows.append(.note("附近网络共 \(others.count) 个，仅显示前 \(shown.count) 个"))
                }
            }
        }
        // 无线软件版本
        if let software = entry["spairport_software_information"] as? [String: Any] {
            if let version = SPReader.value(software, "spairport_family_version") {
                rows.append(.field("无线软件", version))
            }
        }
        return rows
    }

    /// 以太网：SPEthernetDataType（控制器/总线/MAC/链路）
    func ethernetRows() -> [InfoRowSpec] {
        let entries = SPReader.entries("SPEthernetDataType")
        if entries == nil {
            return [.field("以太网", isLoading ? "正在读取…" : "不可用")]
        }
        guard !entries!.isEmpty else {
            return [.field("以太网", "未检测到以太网控制器")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries! {
            let name = SPReader.value(entry, "_name") ?? "以太网控制器"
            rows.append(.section(name))
            if let bus = SPReader.value(entry, "spethernet_bus") {
                rows.append(.field("总线", SPMap.ethernetBus(bus)))
            }
            if let vendor = SPReader.value(entry, "spethernet_vendor_name") {
                rows.append(.field("供应商", vendor))
            }
            if let product = SPReader.value(entry, "spethernet_product_name") {
                rows.append(.field("产品", product))
            }
            if let driver = SPReader.value(entry, "spethernet_driver") {
                rows.append(.field("驱动", driver))
            }
            if let bsd = SPReader.value(entry, "spethernet_BSD_Device_Name") {
                rows.append(.field("BSD 设备名", bsd))
            }
            if let mac = SPReader.value(entry, "spethernet_mac_address") {
                rows.append(.field("MAC 地址", mac))
            }
            if let maxSpeed = SPReader.value(entry, "spethernet_max_link_speed") {
                rows.append(.field("最大链路速率", SPMap.ethernetMaxSpeed(maxSpeed)))
            }
            if let avb = SPReader.value(entry, "spethernet_avb_support") {
                rows.append(.field("AVB 支持", SPMap.yesNo(avb)))
            }
        }
        return rows
    }

    /// 网络：SPNetworkDataType（各服务/接口/代理）+ 实时吞吐
    func networkRows() -> [InfoRowSpec] {
        var rows: [InfoRowSpec] = []
        if let sample = networkSample {
            rows.append(contentsOf: [
                .field("下行速率", Formats.rate(sample.bytesInPerSecond)),
                .field("上行速率", Formats.rate(sample.bytesOutPerSecond)),
                .field("累计接收", Formats.memory(sample.totalBytesIn)),
                .field("累计发送", Formats.memory(sample.totalBytesOut)),
            ])
        } else if isLoading {
            rows.append(.field("下行速率", "正在读取…"))
        }
        if let services = SPReader.entries("SPNetworkDataType") {
            for service in services {
                let name = SPReader.value(service, "_name") ?? "服务"
                rows.append(.section(name))
                if let type = SPReader.value(service, "type") {
                    rows.append(.field("类型", type))
                }
                if let bsd = SPReader.value(service, "interface") {
                    rows.append(.field("BSD 设备名", bsd))
                }
                let addresses = SPReader.value(service, "ip_address")
                    ?? (service["ip_address"] as? [String] ?? []).first
                if let addresses, !addresses.isEmpty {
                    rows.append(.field("IP 地址", addresses))
                }
                if let ipv4 = service["IPv4"] as? [String: Any],
                   let method = SPReader.value(ipv4, "ConfigMethod") {
                    rows.append(.field("IPv4 配置", method))
                }
                if let proxies = service["Proxies"] as? [String: Any] {
                    var proxyParts: [String] = []
                    if let enabled = SPReader.value(proxies, "HTTPEnable"), enabled == "yes",
                       let host = SPReader.value(proxies, "HTTPProxy") {
                        proxyParts.append("HTTP \(host)")
                    }
                    if let enabled = SPReader.value(proxies, "SOCKSEnable"), enabled == "yes",
                       let host = SPReader.value(proxies, "SOCKSProxy") {
                        proxyParts.append("SOCKS \(host)")
                    }
                    if !proxyParts.isEmpty {
                        rows.append(.field("代理", proxyParts.joined(separator: " · ")))
                    }
                }
            }
        } else if isLoading {
            rows.append(.field("服务", "正在读取…"))
        }
        // 接口状态（getifaddrs）
        for interface in interfaces {
            if interface.ipv4 == nil && interface.ipv6 == nil { continue }
            rows.append(.subSection(interface.name))
            let hasRoutable = interface.ipv4 != nil || (interface.ipv6.map { !$0.hasPrefix("fe80") } ?? false)
            let status: String
            if interface.isRunning && hasRoutable {
                status = "已连接"
            } else if interface.isUp {
                status = "已启用"
            } else {
                status = "未启用"
            }
            rows.append(.field("状态", status))
            if let mac = interface.mac {
                rows.append(.field("MAC 地址", mac))
            }
        }
        if rows.isEmpty {
            rows.append(.field("网络", "未检测到网络服务"))
        }
        return rows
    }

    /// 位置：SPNetworkLocationDataType（网络位置）
    func locationRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPNetworkLocationDataType") else {
            return [.field("位置", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        for entry in entries {
            let name = SPReader.value(entry, "_name") ?? "位置"
            rows.append(.section(name))
            if let active = SPReader.value(entry, "spnetworklocation_isActive") {
                rows.append(.field("活动", active == "yes" ? "是" : "否"))
            }
            let services = SPReader.array(entry, "spnetworklocation_services")
            rows.append(.field("服务数", "\(services.count)"))
            for service in services {
                let serviceName = SPReader.value(service, "_name") ?? "服务"
                var subtitle = ""
                if let ipv4 = service["IPv4"] as? [String: Any],
                   let method = SPReader.value(ipv4, "ConfigMethod") {
                    subtitle = "IPv4 \(method)"
                }
                rows.append(.subSection(subtitle.isEmpty ? serviceName : "\(serviceName)（\(subtitle)）"))
            }
        }
        if rows.isEmpty {
            rows.append(.field("位置", "未定义网络位置"))
        }
        return rows
    }

    /// 宗卷：SPNetworkVolumeDataType（网络挂载卷）
    func volumeRows() -> [InfoRowSpec] {
        guard let entries = SPReader.entries("SPNetworkVolumeDataType") else {
            return [.field("宗卷", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        if entries.isEmpty {
            rows.append(.field("网络宗卷", "未挂载网络宗卷"))
        }
        for entry in entries {
            let name = SPReader.value(entry, "_name") ?? "宗卷"
            rows.append(.section(name))
            if let mountedFrom = SPReader.value(entry, "spnetworkvolume_mntfromname") {
                rows.append(.field("挂载自", mountedFrom))
            }
            if let fs = SPReader.value(entry, "spnetworkvolume_fstypename") {
                rows.append(.field("文件系统", fs))
            }
            if let path = SPReader.value(entry, "spnetworkvolume_fsmtnonname") {
                rows.append(.field("挂载点", path))
            }
            if let automount = SPReader.value(entry, "spnetworkvolume_automounted") {
                rows.append(.field("自动挂载", SPMap.yesNo(automount)))
            }
        }
        return rows
    }

    /// 防火墙：SPFirewallDataType（全局状态/隐身/日志/放行应用）
    func firewallRows() -> [InfoRowSpec] {
        guard let entry = SPReader.first("SPFirewallDataType") else {
            return [.field("防火墙", isLoading ? "正在读取…" : "不可用")]
        }
        var rows: [InfoRowSpec] = []
        if let state = SPReader.value(entry, "spfirewall_globalstate") {
            rows.append(.field("防火墙状态", SPMap.firewallState(state)))
        }
        if let stealth = SPReader.value(entry, "spfirewall_stealthenabled") {
            rows.append(.field("隐身模式", SPMap.yesNo(stealth)))
        }
        if let logging = SPReader.value(entry, "spfirewall_loggingenabled") {
            rows.append(.field("记录日志", SPMap.yesNo(logging)))
        }
        if let apps = entry["spfirewall_applications"] as? [String: Any] {
            rows.append(.section("放行应用"))
            if apps.isEmpty {
                rows.append(.field("数量", "0"))
            }
            for (bundleID, rule) in apps.sorted(by: { ($0.value as? String) ?? "" < ($1.value as? String) ?? "" }) {
                let ruleText = SPMap.firewallAllow(rule as? String ?? "")
                rows.append(.field(bundleID, ruleText))
            }
        }
        return rows
    }
}
