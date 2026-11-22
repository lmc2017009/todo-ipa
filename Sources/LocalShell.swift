import Foundation
import Darwin

/// 本机真实终端：用 posix_spawn 拉起 App 包内 / 文档目录里的静态 BusyBox。
/// - 通过 TrollStore（或等价方式）安装、进程无沙盒时才能成功 spawn 并访问全盘；
/// - 子进程继承当前进程的沙盒状态（no-sandbox 时子进程同样无沙盒）。
enum LocalShell {
    struct RunResult {
        var code: Int32
        var output: String
        var timedOut: Bool
    }

    /// BusyBox 搜索顺序：App 包 → 文档 bin → 文档根 → 越狱 bootstrap
    static var binaryPath: String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidates: [String] = [
            Bundle.main.path(forResource: "busybox", ofType: nil) ?? "",
            docs.appendingPathComponent("bin/busybox").path,
            docs.appendingPathComponent("busybox").path,
            "/var/jb/bin/busybox",
            "/usr/bin/busybox"
        ]
        for path in candidates where !path.isEmpty {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static var isAvailable: Bool { binaryPath != nil }

    private static var binDirectory: String {
        guard let path = binaryPath else { return "" }
        return (path as NSString).deletingLastPathComponent
    }

    /// 工作目录：已解除沙盒时用 /，否则退回 App 文档目录
    static var workingDirectory: String {
        SandboxProbe.isSandboxEscaped
            ? "/"
            : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
    }

    /// BusyBox 版本行（带缓存，只探测一次）
    static let version: String = {
        guard isAvailable else { return "未内置" }
        if let result = run("busybox 2>&1 | head -1", timeout: 3) {
            let line = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? "未知版本" : line
        }
        return "未知版本"
    }()

    // MARK: - 执行

    static func run(_ command: String, timeout: TimeInterval = 30) -> RunResult? {
        guard let bb = binaryPath else { return nil }

        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else {
            return RunResult(code: -1, output: "无法创建输出管道", timedOut: false)
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, fds[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, fds[0])
        posix_spawn_file_actions_addclose(&fileActions, fds[1])

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        let docsBin = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bin").path
        var environment: [String] = [
            "PATH=\(binDirectory):\(docsBin):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME=\(NSHomeDirectory())",
            "TMPDIR=\(NSTemporaryDirectory())",
            "LANG=zh_CN.UTF-8",
            "TERM=dumb"
        ]
        for key in ["USER", "LOGNAME"] {
            if let value = ProcessInfo.processInfo.environment[key] {
                environment.append("\(key)=\(value)")
            }
        }

        let wrapped = "cd \(Self.shellQuote(workingDirectory)) 2>/dev/null || exit 126; " + command
        let arguments: [String] = [bb, "sh", "-c", wrapped]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
        envp.append(nil)
        defer {
            for pointer in argv where pointer != nil {
                free(UnsafeMutableRawPointer(pointer!))
            }
            for pointer in envp where pointer != nil {
                free(UnsafeMutableRawPointer(pointer!))
            }
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attr)
        }

        var pid: pid_t = 0
        let spawnCode: Int32 = argv.withUnsafeMutableBufferPointer { argvBuffer in
            envp.withUnsafeMutableBufferPointer { envpBuffer in
                posix_spawn(&pid, bb, &fileActions, &attr,
                            argvBuffer.baseAddress, envpBuffer.baseAddress)
            }
        }
        close(fds[1])

        guard spawnCode == 0 else {
            close(fds[0])
            let reason = String(cString: strerror(spawnCode))
            return RunResult(
                code: -1,
                output: "无法启动本机终端（\(reason)）。本机真实终端需要 TrollStore + no-sandbox 安装；普通签名请改用远程执行器。",
                timedOut: false
            )
        }

        let fd = fds[0]
        let currentFlags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, currentFlags | O_NONBLOCK)

        var data = Data()
        var timedOut = false
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
                continue
            }
            if count == 0 { break }
            if errno == EINTR { continue }
            if errno != EAGAIN && errno != EWOULDBLOCK { break }
            if Date() > deadline {
                kill(-pid, SIGKILL)
                timedOut = true
                break
            }
            usleep(15_000)
        }
        close(fd)

        var status: Int32 = 0
        let reaped = waitpid(pid, &status, 0) == pid
        var code: Int32 = -1
        if reaped {
            if timedOut {
                code = -2
            } else if (status & 0x7f) == 0 {
                code = (status >> 8) & 0xff
            } else {
                code = -(status & 0x7f)
            }
        }

        var output = String(data: data, encoding: .utf8)
            ?? "（输出无法按 UTF-8 解码，\(data.count) 字节）"
        if timedOut { output += "\n（执行超过 \(Int(timeout)) 秒，已强制终止）" }
        return RunResult(code: code, output: output, timedOut: timedOut)
    }

    /// POSIX shell 单引号转义（用于 cd）
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}