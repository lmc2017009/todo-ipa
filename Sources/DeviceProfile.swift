import Foundation
import Darwin
import UIKit
import CoreMotion

/// 设备档案：每次请求时生成快照，注入给模型
enum DeviceProfile {

    static func summary() -> String {
        var lines: [String] = ["[本机设备档案]"]
        lines.append("型号：\(deviceName())（\(machineIdentifier())）")
        lines.append("系统：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        lines.append("设备名：\(UIDevice.current.name)")
        lines.append("屏幕：\(Int(UIScreen.main.bounds.width))×\(Int(UIScreen.main.bounds.height)) @\(String(format: "%.1f", UIScreen.main.scale))x")
        lines.append("电量：\(batteryText())")
        lines.append("内存：总 \(memoryText())")
        lines.append("存储：\(diskText())")
        lines.append("网络：\(networkText())")
        lines.append("低电量模式：\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "开" : "关")")
        lines.append("语言/时区：\(Locale.current.identifier) / \(TimeZone.current.identifier)")
        lines.append("当前时间：\(dateText(Date()))")
        return lines.joined(separator: "\n")
    }

    static func deviceName() -> String {
        UIDevice.current.model
    }

    static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        var identifier = ""
        for child in mirror.children {
            guard let value = child.value as? Int8, value != 0 else { continue }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    static func batteryText() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "未知" }
        let percent = Int((level * 100).rounded())
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "充电中"
        case .full: state = "已充满"
        case .unplugged: state = "未充电"
        default: state = "未知"
        }
        return "\(percent)%（\(state)）"
    }

    static func memoryText() -> String {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%.1f GB", total)
    }

    static func diskText() -> String {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        guard let total = attributes?[.systemSize] as? NSNumber,
              let free = attributes?[.systemFreeSize] as? NSNumber else {
            return "未知"
        }
        let totalGB = total.doubleValue / 1_073_741_824
        let freeGB = free.doubleValue / 1_073_741_824
        let usedGB = max(0, totalGB - freeGB)
        return String(format: "已用 %.1f / 共 %.1f GB（剩余 %.1f GB）", usedGB, totalGB, freeGB)
    }

    static func networkText() -> String {
        var wifi = false
        var cellular = false
        var address = ""

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "未知" }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            if name == "en0" { wifi = true } else if name.hasPrefix("pdp_ip") { cellular = true } else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if address.isEmpty,
               getnameinfo(interface.ifa_addr,
                           socklen_t(interface.ifa_addr.pointee.sa_len),
                           &host,
                           socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: host)
            }
        }

        var parts: [String] = []
        if wifi { parts.append("Wi-Fi") }
        if cellular { parts.append("蜂窝") }
        if !address.isEmpty { parts.append("本机 IP \(address)") }
        return parts.isEmpty ? "未知" : parts.joined(separator: " · ")
    }

    static func motionText() -> String {
        let manager = CMMotionManager()
        guard manager.isAccelerometerAvailable else { return "该设备不支持加速度计" }
        manager.accelerometerUpdateInterval = 0.1
        manager.startAccelerometerUpdates()
        Thread.sleep(forTimeInterval: 0.2)
        defer { manager.stopAccelerometerUpdates() }

        guard let data = manager.accelerometerData else { return "暂时读不到数据" }
        let acceleration = data.acceleration
        var text = String(format: "加速度 x %.2f, y %.2f, z %.2f（单位 g）",
                          acceleration.x, acceleration.y, acceleration.z)

        if CMMotionManager().isGyroAvailable,
           let gyro = CMMotionManager().gyroData {
            text += String(format: "\n陀螺仪 %.2f, %.2f, %.2f", gyro.rotationRate.x,
                           gyro.rotationRate.y, gyro.rotationRate.z)
        }
        return text
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}