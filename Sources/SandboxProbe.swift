import Foundation
import Darwin

/// 沙盒 / 权限探测：用真实 I/O 判断当前进程的能力边界
enum SandboxProbe {
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
    static func text() -> String {
        var lines: [String] = []
        lines.append("[权限自检]")
        lines.append("进程 uid：\(getuid())")

        if SandboxProbe.isSandboxEscaped {
            lines.append("沙盒：已解除（no-sandbox 或等价扩展已生效），可访问全盘 mobile 可见目录")
        } else {
            lines.append("沙盒：未解除，fs_* 只能访问 App 文档目录")
        }

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

        lines.append("文档目录：\(SandboxProbe.documentsPath)")
        return lines.joined(separator: "\n")
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