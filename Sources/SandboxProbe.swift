import Foundation
import Darwin
import UIKit
import Photos
import Contacts
import EventKit
import AVFoundation

/// 沙盒 / 权限探测：用真实 I/O 判断当前进程的能力边界
enum SandboxProbe {
    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion == 0 {
            return "\(version.majorVersion).\(version.minorVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// 进程是否已经脱离沙盒（TrollStore no-sandbox / WQ sandbox extension 等）
    static let isSandboxEscaped: Bool = {
        canRead("/var/mobile/Containers/Data/Application")
            || canRead("/var/mobile/Library")
            || canRead("/var/mobile/Containers/Shared/AppGroup")
            || canRead("/private/var/mobile/Library")
    }()

    static func canRead(_ path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    static func canWrite(_ directory: String) -> Bool {
        let probe = (directory as NSString).appendingPathComponent(".aichat_probe_\(getpid())")
        let created = FileManager.default.createFile(atPath: probe, contents: Data("ok".utf8))
        if created { try? FileManager.default.removeItem(atPath: probe) }
        return created
    }

    static var documentsPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
    }

    /// 文档目录里已有的符号链接（name → target）
    static func preparedLinks() -> [(name: String, target: String)] {
        let docs = documentsPath
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: docs) else { return [] }
        var result: [(name: String, target: String)] = []
        for name in names.sorted() {
            let path = (docs as NSString).appendingPathComponent(name)
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
                result.append((name, target))
            }
        }
        return result
    }
}

/// WQ（worse_query）通道探测：只要存在可执行 wq / wqcli，模型就能经 shell 工具调用
enum WQSupport {
    static var binaryPath: String? {
        let docs = SandboxProbe.documentsPath
        let candidates: [String] = [
            Bundle.main.path(forResource: "wq", ofType: nil) ?? "",
            Bundle.main.path(forResource: "wqcli", ofType: nil) ?? "",
            (docs as NSString).appendingPathComponent("bin/wq"),
            (docs as NSString).appendingPathComponent("wq"),
            "/var/jb/usr/bin/wq",
            "/usr/bin/wq"
        ]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { binaryPath != nil }
}

/// 启动时的一次性准备：沙盒已解除时，在文档目录放好指向全盘关键位置的符号链接
enum SandboxBootstrap {
    static func prepare() {
        guard SandboxProbe.isSandboxEscaped else { return }
        let docs = SandboxProbe.documentsPath
        let links: [(String, String)] = [
            ("root", "/"),
            ("apps", "/var/mobile/Containers/Data/Application"),
            ("groups", "/var/mobile/Containers/Shared/AppGroup"),
            ("sms", "/var/mobile/Library/SMS"),
            ("media", "/var/mobile/Media")
        ]
        for (name, target) in links {
            let path = (docs as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path) { continue }
            try? FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
        }
    }
}

/// 给模型看的权限自检报告（只做文件系统层面的探测，可在后台线程安全调用）
enum AccessReport {
    static func text(grants: [String] = []) -> String {
        var lines: [String] = []
        lines.append("[权限自检]")
        lines.append("进程 uid：\(getuid())")

        if SandboxProbe.isSandboxEscaped {
            lines.append("沙盒：已解除（no-sandbox 或等价扩展已生效），可访问全盘 mobile 可见目录")
        } else {
            lines.append("""
            沙盒：未解除（当前是普通沙盒 App）
            为什么（结论，不要反复重试）：
            - com.apple.private.security.no-sandbox / platform-application 这类私有 entitlements，只在 TrollStore 安装或越狱环境下被 AMFI 认可；普通签名（AltStore / ESign / Sideloadly / 自签证书）重签时会丢弃它们。
            - TrollStore 仅支持 iOS 14.0–17.0；本机是 iOS \(SandboxProbe.osVersion)，不在支持范围。
            - posix_spawn 只允许执行受信任签名的 Mach-O，所以没有内置 busybox 也无法运行外部二进制。
            因此 /var/mobile、其他 App 容器、SMS 数据库在本机不可达。可达范围：App 文档目录 + 用户用 dir_grant 显式授权的目录 + 系统已授权的相册/通讯录/日历。
            """)
        }

        lines.append("系统授权：\n" + tccLines().joined(separator: "\n"))

        let probes: [(String, String)] = [
            ("/var/mobile/Containers/Data/Application", "全部 App 数据容器"),
            ("/var/mobile/Containers/Shared/AppGroup", "App Group 共享容器"),
            ("/var/mobile/Library", "系统库（偏好/短信/缓存）"),
            ("/var/mobile/Library/SMS", "短信数据库"),
            ("/var/mobile/Media/DCIM", "相册原始文件"),
            ("/private/var/mobile", "真实 var 路径"),
            ("/var/jb", "越狱 bootstrap"),
            ("/Applications", "系统 App")
        ]
        var readLines: [String] = []
        for (path, label) in probes {
            let mark = SandboxProbe.canRead(path) ? "可读" : "不可读"
            readLines.append("\(path)（\(label)）：\(mark)")
        }
        lines.append("路径探测：\n" + readLines.joined(separator: "\n"))

        let writable = SandboxProbe.canWrite("/var/mobile/Library/Caches")
        lines.append("全盘写入：\(writable ? "可用" : "不可用（可能只有读取扩展）")")

        if LocalShell.isAvailable {
            let path = LocalShell.binaryPath ?? ""
            lines.append("内置终端：\(path)（\(LocalShell.version)）")
        } else {
            lines.append("内置终端：未内置")
        }

        if let wq = WQSupport.binaryPath {
            lines.append("WQ 通道：可用 → \(wq)（经 shell 工具直接调用，例如 `wq ...`）")
        } else {
            lines.append("WQ 通道：未发现 wq 可执行文件（可放到 App 包内或 Documents/bin/wq）")
        }

        let links = SandboxProbe.preparedLinks()
        if links.isEmpty {
            lines.append("文档目录符号链接：无")
        } else {
            lines.append("文档目录符号链接：" + links.map { "\($0.name) → \($0.target)" }.joined(separator: "、"))
        }

        if grants.isEmpty {
            lines.append("用户授权目录：无。需要读 App 沙盒外的文件时，调用 dir_grant 让用户选择一个目录（支持跨 App 的「我的 iPhone」文件夹）。")
        } else {
            lines.append("用户授权目录（用 grant:标签/... 访问）：\n" + grants.joined(separator: "\n"))
        }

        lines.append("文档目录：\(SandboxProbe.documentsPath)")
        return lines.joined(separator: "\n")
    }

    // MARK: - 系统授权状态

    private static func tccLines() -> [String] {
        var lines: [String] = []
        lines.append("- 相册：\(photoText(PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue))")
        lines.append("- 通讯录：\(contactText(CNContactStore.authorizationStatus(for: .contacts).rawValue))")
        let store = EKEventStore()
        lines.append("- 日历：\(eventText(store.authorizationStatus(for: .event).rawValue))")
        lines.append("- 提醒事项：\(eventText(store.authorizationStatus(for: .reminder).rawValue))")
        lines.append("- 相机：\(captureText(AVCaptureDevice.authorizationStatus(for: .video).rawValue))")
        lines.append("- 麦克风：\(captureText(AVCaptureDevice.authorizationStatus(for: .audio).rawValue))")
        return lines
    }

    private static func photoText(_ raw: Int) -> String {
        switch raw {
        case 0: return "未询问"
        case 1: return "受限（家长控制）"
        case 2: return "已拒绝"
        case 3: return "已授权（全部照片）"
        case 4: return "已授权（仅选中的照片）"
        default: return "未知(\(raw))"
        }
    }

    private static func contactText(_ raw: Int) -> String {
        switch raw {
        case 0: return "未询问"
        case 1: return "受限"
        case 2: return "已拒绝"
        case 3: return "已授权"
        default: return raw >= 4 ? "已授权（受限访问）" : "未知(\(raw))"
        }
    }

    private static func eventText(_ raw: Int) -> String {
        switch raw {
        case 0: return "未询问"
        case 1: return "受限"
        case 2: return "已拒绝"
        case 3: return "已授权"
        case 4: return "已授权（完整访问）"
        case 5: return "仅允许写入"
        default: return "未知(\(raw))"
        }
    }

    private static func captureText(_ raw: Int) -> String {
        switch raw {
        case 0: return "未询问"
        case 1: return "受限"
        case 2: return "已拒绝"
        case 3: return "已授权"
        default: return "未知(\(raw))"
        }
    }

    /// 系统提示词里的简短运行时状态
    static func brief() -> String {
        var parts: [String] = []
        parts.append(SandboxProbe.isSandboxEscaped ? "沙盒已解除，可读写全盘" : "沙盒未解除，仅 App 文档")
        if LocalShell.isAvailable { parts.append("内置真实终端可用") }
        if WQSupport.isAvailable { parts.append("WQ 通道可用") }
        return "[运行时状态] " + parts.joined(separator: "；")
    }
}