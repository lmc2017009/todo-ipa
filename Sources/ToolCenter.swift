import Foundation
import Contacts
import EventKit
import Photos
import UIKit
import UserNotifications

/// 给模型执行设备能力的工具中心
@MainActor
final class ToolCenter {
    static let shared = ToolCenter()

    // MARK: - 工具声明

    func definitions(enabled: [CapabilityKind], terminalConfigured: Bool) -> [[String: Any]] {
        var tools: [[String: Any]] = []

        func add(_ name: String, _ description: String,
                 _ properties: [String: Any], _ required: [String]) {
            tools.append([
                "type": "function",
                "function": [
                    "name": name,
                    "description": description,
                    "parameters": [
                        "type": "object",
                        "properties": properties,
                        "required": required
                    ]
                ]
            ])
        }

        let set = Set(enabled)

        // 已解除沙盒时，fs_* 支持绝对路径
        let escaped = SandboxProbe.isSandboxEscaped

        if set.contains(.deviceInfo) {
            add("device_info", "读取本机档案：机型、系统、电量、内存、存储、网络、时间", [:], [])
            add("access_report", "权限自检：当前沙盒状态、可读写的全盘路径、内置终端、WQ 通道、文档目录符号链接。不确定能力边界时先调用它", [:], [])
        }

        if set.contains(.fileSandbox) {
            let scope = escaped
                ? "已解除沙盒，可直接使用绝对路径（如 /var/mobile/Library/SMS）"
                : "沙盒受限：可访问 App 文档目录（写作 /）以及用户已授权的目录（写作 grant:标签/子路径）"
            add("fs_list", "列出目录内容（\(scope)；根目录写作 /）",
                ["path": ["type": "string", "description": "目录路径，如 / 、/notes 或 grant:下载/子目录"]], [])
            add("fs_read", "读取文本文件（二进制文件会给出提示）",
                ["path": ["type": "string"]], ["path"])
            add("fs_write", "写入文本文件，自动创建目录",
                ["path": ["type": "string"], "content": ["type": "string"]], ["path", "content"])
            add("fs_delete", "删除文件或目录（系统关键目录会被拒绝）",
                ["path": ["type": "string"]], ["path"])
            add("fs_search", "按关键词搜索文件名与文件内容",
                ["keyword": ["type": "string"],
                 "path": ["type": "string", "description": "可选，搜索起点；默认沙盒根"]],
                ["keyword"])
            add("dir_grant", "弹出系统目录选择器，让用户授权一个目录（可跨 App，如「我的 iPhone」里别的 App 文件夹）。授权后可用 grant:标签/... 访问。需要读取 App 沙盒外的文件时，先调用它",
                ["label": ["type": "string", "description": "可选，给这个目录起的短标签，如 下载 / 微信文档"]],
                [])
            add("dir_list", "列出已授权的目录（标签与真实路径）", [:], [])
            add("dir_revoke", "撤销一个已授权目录",
                ["label": ["type": "string"]], ["label"])
        }

        if set.contains(.shell) {
            let mode: String
            if LocalShell.isAvailable {
                mode = "本机真实终端（内置 BusyBox，posix_spawn，无沙盒限制，可用绝对路径、管道、重定向）"
            } else if terminalConfigured {
                mode = "已连接远程主机，可执行真实 shell 命令"
            } else {
                mode = "当前是沙盒模拟终端，只能操作 App 文档目录"
            }
            add("shell", "执行 shell 命令。\(mode)。复杂或批量操作优先用它；不确定能力边界时先调用 access_report。",
                ["command": ["type": "string"]], ["command"])
        }

        if set.contains(.clipboard) {
            add("clipboard", "读取或写入剪贴板文本",
                ["action": ["type": "string", "enum": ["get", "set"]],
                 "text": ["type": "string", "description": "action=set 时要写入的文本"]],
                ["action"])
        }

        if set.contains(.motion) {
            add("motion", "读取设备当前的加速度与陀螺仪数据", [:], [])
        }

        if set.contains(.location) {
            add("location", "获取设备当前经纬度", [:], [])
        }

        if set.contains(.contacts) {
            add("contacts_search", "按姓名搜索通讯录联系人",
                ["query": ["type": "string"]], ["query"])
        }

        if set.contains(.calendar) {
            add("calendar_events", "查询未来若干天的日历日程",
                ["days": ["type": "integer", "description": "查询天数，默认 7"]], [])
        }

        if set.contains(.reminders) {
            add("reminder_create", "创建一条提醒事项",
                ["title": ["type": "string"],
                 "due": ["type": "string", "description": "可选，格式 yyyy-MM-dd HH:mm"]],
                ["title"])
        }

        if set.contains(.notifications) {
            add("notify", "发送一条本地通知提醒用户",
                ["title": ["type": "string"],
                 "body": ["type": "string"],
                 "seconds": ["type": "integer", "description": "多少秒后提醒，默认 1"]],
                ["title"])
        }

        if set.contains(.photoLibrary) {
            add("photos_recent", "把相册里最近的照片复制到沙盒，返回文件路径",
                ["limit": ["type": "integer", "description": "取几张，默认 3，最多 10"]], [])
        }

        return tools
    }

    // MARK: - 执行

    func run(_ call: ToolCallRecord, settings: APISettings) async -> String {
        let arguments = Self.parse(call.arguments)

        switch call.name {
        case "device_info":
            return DeviceProfile.summary()

        case "access_report":
            let grants = DirectoryGrant.summaryLines()
            return await Task.detached(priority: .userInitiated) {
                AccessReport.text(grants: grants)
            }.value

        case "fs_list":
            return list(path: arguments["path"] as? String ?? "/")

        case "fs_read":
            guard let path = arguments["path"] as? String else { return "缺少参数 path" }
            return read(path: path)

        case "fs_write":
            guard let path = arguments["path"] as? String,
                  let content = arguments["content"] as? String else { return "缺少参数 path / content" }
            return write(path: path, content: content)

        case "fs_delete":
            guard let path = arguments["path"] as? String else { return "缺少参数 path" }
            return delete(path: path)

        case "fs_search":
            guard let keyword = arguments["keyword"] as? String else { return "缺少参数 keyword" }
            return search(keyword: keyword, path: arguments["path"] as? String)

        case "dir_grant":
            let raw = (arguments["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = raw.isEmpty ? "目录\(DirectoryGrant.all().count + 1)" : raw
            guard let url = await DirectoryGrant.presentPicker() else {
                return "用户取消或超时，未授权任何目录"
            }
            guard let grant = DirectoryGrant.add(label: label, url: url) else {
                return "授权失败：无法为该目录创建 bookmark"
            }
            return """
            已授权：\(grant.path)
            标签：\(label)
            后续用 `grant:\(label)/文件名` 访问（可读写、可列举、可搜索）
            """

        case "dir_list":
            let lines = DirectoryGrant.summaryLines()
            if DirectoryGrant.all().isEmpty {
                return "还没有授权任何目录。需要访问 App 沙盒外的文件时，调用 dir_grant 让用户选择一个目录。"
            }
            return "已授权目录：\n" + lines.joined(separator: "\n")

        case "dir_revoke":
            guard let label = arguments["label"] as? String else { return "缺少参数 label" }
            return DirectoryGrant.remove(label: label) ? "已撤销授权：\(label)" : "没有找到标签为「\(label)」的授权"

        case "shell":
            guard let command = arguments["command"] as? String else { return "缺少参数 command" }
            if LocalShell.isAvailable {
                let result = await Task.detached(priority: .userInitiated) {
                    LocalShell.run(command)
                }.value
                if let result {
                    var text = "exit \(result.code)\n"
                    text += result.output.isEmpty ? "（无输出）" : result.output
                    return text
                }
            }
            if !settings.terminalHost.trimmingCharacters(in: .whitespaces).isEmpty {
                return await remoteShell(command, settings: settings)
            }
            return sandboxShell(command)

        case "clipboard":
            let action = (arguments["action"] as? String) ?? "get"
            if action == "set" {
                UIPasteboard.general.string = arguments["text"] as? String ?? ""
                return "已写入剪贴板"
            }
            return UIPasteboard.general.string ?? "剪贴板为空"

        case "motion":
            return DeviceProfile.motionText()

        case "location":
            guard let location = await LocationProvider.shared.current() else {
                return "定位不可用或未授权"
            }
            return String(format: "纬度 %.6f，经度 %.6f（水平精度约 %.0f 米）",
                          location.coordinate.latitude,
                          location.coordinate.longitude,
                          location.horizontalAccuracy)

        case "contacts_search":
            guard let query = arguments["query"] as? String else { return "缺少参数 query" }
            return searchContacts(query)

        case "calendar_events":
            let days = (arguments["days"] as? Int) ?? 7
            return calendarEvents(days: days)

        case "reminder_create":
            guard let title = arguments["title"] as? String else { return "缺少参数 title" }
            return createReminder(title: title, due: arguments["due"] as? String)

        case "notify":
            let title = (arguments["title"] as? String) ?? "提醒"
            let body = (arguments["body"] as? String) ?? ""
            let seconds = (arguments["seconds"] as? Int) ?? 1
            return notify(title: title, body: body, seconds: seconds)

        case "photos_recent":
            let limit = (arguments["limit"] as? Int) ?? 3
            return await recentPhotos(limit: limit)

        default:
            return "未知工具：\(call.name)"
        }
    }

    // MARK: - 文件系统

    private func documents() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func resolve(_ path: String) -> URL? {
        let root = documents().standardizedFileURL
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { trimmed = "/" }

        // 用户显式授权的目录：grant:标签/子路径
        if trimmed.lowercased().hasPrefix("grant:") {
            let rest = String(trimmed.dropFirst("grant:".count))
            let pieces = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            let label = pieces.first.map(String.init) ?? ""
            guard let base = DirectoryGrant.url(forLabel: label) else { return nil }
            let sub = pieces.count > 1 ? String(pieces[1]) : ""
            let candidate = (sub.isEmpty ? base : base.appendingPathComponent(sub)).standardizedFileURL
            let basePath = base.standardizedFileURL.path
            guard candidate.path == basePath || candidate.path.hasPrefix(basePath + "/") else {
                return nil
            }
            return candidate
        }

        // 已解除沙盒：绝对路径直接放行（全盘模式）
        if SandboxProbe.isSandboxEscaped, trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        if trimmed == "/" { return root }
        if trimmed.hasPrefix("/") { trimmed.removeFirst() }

        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }
        return candidate
    }

    private func relativePath(_ url: URL) -> String {
        let root = documents().standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == root { return "/" }
        guard path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count))
    }

    private func list(path: String) -> String {
        guard let url = resolve(path) else { return "路径越界，拒绝访问" }

        let options: FileManager.DirectoryEnumerationOptions =
            SandboxProbe.isSandboxEscaped ? [] : [.skipsHiddenFiles]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: options) else {
            return "无法读取目录：\(url.path)（权限不足或不存在）。沙盒受限时只能列举 / 与 grant:标签/...；要访问新目录请先调用 dir_grant。"
        }

        var lines: [String] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? item.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let isLink = values?.isSymbolicLink == true
            let isDir = values?.isDirectory == true
            let size = values?.fileSize ?? 0

            if isLink {
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: item.path)) ?? "?"
                lines.append("[链接] \(item.lastPathComponent) -> \(target)")
            } else if isDir {
                lines.append("[目录] \(item.lastPathComponent)/")
            } else {
                lines.append("[文件] \(item.lastPathComponent)  \(size) B")
            }
        }

        if url.standardizedFileURL.path == documents().standardizedFileURL.path {
            for line in DirectoryGrant.summaryLines() {
                lines.append("[授权] " + line)
            }
        }

        return lines.isEmpty ? "（空目录）" : lines.joined(separator: "\n")
    }

    private func read(path: String) -> String {
        guard let url = resolve(path) else { return "路径越界，拒绝访问" }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "读取失败：\(path)"
        }
        defer { try? handle.close() }

        let limit = 400_000
        let data = (try? handle.read(upToCount: limit)) ?? Data()
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? data.count

        if data.contains(0) {
            return "二进制文件（\(size) 字节），不直接返回内容；可用 shell 的 strings / xxd / sqlite3 处理。"
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        if size > limit {
            return "文件较大（\(size) 字节），只读取前 \(limit / 1000) KB：\n" + text
        }
        return text
    }

    private func write(path: String, content: String) -> String {
        guard let url = resolve(path) else { return "路径越界，拒绝访问" }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "已写入 \(url.path)（\(content.count) 字符）"
        } catch {
            return "写入失败：\(error.localizedDescription)"
        }
    }

    /// 系统 / 容器关键目录，禁止删除（防模型把设备搞坏）
    private static let protectedPaths: Set<String> = [
        "/", "/var", "/private", "/private/var", "/var/mobile",
        "/var/mobile/Library", "/var/mobile/Containers",
        "/var/mobile/Containers/Data", "/var/mobile/Containers/Bundle",
        "/var/containers", "/var/containers/Bundle",
        "/System", "/usr", "/bin", "/sbin", "/Library", "/Applications", "/Developer"
    ]

    private func delete(path: String) -> String {
        guard let url = resolve(path) else { return "路径越界，拒绝访问" }
        let normalized = url.standardizedFileURL.path

        if normalized == documents().standardizedFileURL.path {
            return "不能删除根目录"
        }
        if Self.protectedPaths.contains(normalized) {
            return "拒绝：\(normalized) 是系统/容器关键目录"
        }
        for protected in Self.protectedPaths where protected.hasPrefix(normalized + "/") {
            return "拒绝：\(normalized) 包含系统关键目录 \(protected)"
        }

        do {
            try FileManager.default.removeItem(at: url)
            return "已删除 \(path)"
        } catch {
            return "删除失败：\(error.localizedDescription)"
        }
    }

    private func search(keyword: String, path: String?) -> String {
        let root: URL
        if let path, !path.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let resolved = resolve(path) else { return "路径越界，拒绝访问" }
            root = resolved
        } else {
            root = documents()
        }

        var results: [String] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let options: FileManager.DirectoryEnumerationOptions =
            SandboxProbe.isSandboxEscaped ? [] : [.skipsHiddenFiles]

        if let enumerator = FileManager.default.enumerator(at: root,
                                                           includingPropertiesForKeys: keys,
                                                           options: options) {
            for case let url as URL in enumerator {
                if results.count >= 30 { break }
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }

                if url.lastPathComponent.lowercased().contains(keyword.lowercased()) {
                    results.append("[名字] \(url.path)")
                    continue
                }

                // 大文件跳过内容匹配，避免卡死
                if let size = values?.fileSize, size > 2_000_000 { continue }
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   text.localizedCaseInsensitiveContains(keyword) {
                    results.append("[内容] \(url.path)")
                }
            }
        }

        return results.isEmpty ? "没有找到包含「\(keyword)」的文件" : results.joined(separator: "\n")
    }

    // MARK: - 终端（沙盒模拟 / 远程执行器）

    private func sandboxShell(_ command: String) -> String {
        let parts = command.split(separator: " ").map(String.init)
        guard let head = parts.first else { return "空命令" }
        let arguments = Array(parts.dropFirst())

        switch head {
        case "help":
            return """
            这不是真实 shell，只是 App 内部的受限命令模拟器（没有 fork/exec，无法运行 busybox）。
            可用：pwd ls cat echo mkdir rm find df date whoami uname help
            需要真实命令：在「设置」里填写远程执行器地址；需要沙盒外文件：先调用 dir_grant 授权目录，再用 fs_* 读写。
            """

        case "pwd":
            return "/"

        case "ls":
            return list(path: arguments.first ?? "/")

        case "cat":
            guard let name = arguments.first else { return "用法：cat <文件>" }
            return read(path: name)

        case "echo":
            let text = arguments.joined(separator: " ")
            return text.isEmpty ? "\n" : text

        case "mkdir":
            guard let name = arguments.first, let url = resolve(name) else { return "路径无效" }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return "已创建目录 \(name)"
            } catch {
                return "创建失败：\(error.localizedDescription)"
            }

        case "rm":
            guard let name = arguments.first else { return "用法：rm <文件>" }
            return delete(path: name)

        case "find":
            guard let keyword = arguments.first else { return "用法：find <关键词>" }
            return search(keyword: keyword, path: nil)

        case "df":
            return DeviceProfile.diskText()

        case "date":
            return DeviceProfile.dateText(Date())

        case "whoami":
            return "mobile（沙盒用户）"

        case "uname":
            return "iOS \(UIDevice.current.systemVersion) \(DeviceProfile.machineIdentifier())"

        default:
            return """
            不支持「\(head)」：这不是真实 shell，没有 POSIX 执行能力，无法运行 \(head) 或 busybox。
            现在能做的替代：
            - 读写文件：fs_list / fs_read / fs_write / fs_search（沙盒外用 grant:标签/...）
            - 沙盒外目录：先 dir_grant 让用户授权，再用 grant:标签/... 访问
            - 真实命令：请用户在「设置 → 远程终端」填写执行器地址（HTTP POST {"cmd": ...}）
            模拟命令仅支持：pwd ls cat echo mkdir rm find df date whoami uname help
            """
        }
    }

    private func remoteShell(_ command: String, settings: APISettings) async -> String {
        var raw = settings.terminalHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("http") { raw = "http://" + raw }
        guard let url = URL(string: raw) else { return "远程终端地址无效" }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.terminalToken.isEmpty {
            request.setValue(settings.terminalToken, forHTTPHeaderField: "X-Token")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["cmd": command])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            return "exit \(code)\n\(text.isEmpty ? "（无输出）" : text)"
        } catch {
            return "远程执行失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 系统能力

    private func searchContacts(_ query: String) -> String {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) else {
            return "通讯录未授权或查询失败"
        }
        if contacts.isEmpty { return "没有找到「\(query)」" }

        return contacts.prefix(10).map { contact in
            let name = contact.familyName + contact.givenName
            let phones = contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: ", ")
            return "\(name)：\(phones.isEmpty ? "无号码" : phones)"
        }.joined(separator: "\n")
    }

    private func calendarEvents(days: Int) -> String {
        let store = EKEventStore()
        let start = Date()
        let end = Calendar.current.date(byAdding: .day,
                                        value: max(1, min(days, 60)),
                                        to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        if events.isEmpty { return "未来 \(days) 天没有日程" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"

        return events.prefix(15).map { event in
            "\(formatter.string(from: event.startDate)) \(event.title ?? "(无标题)")"
        }.joined(separator: "\n")
    }

    private func createReminder(title: String, due: String?) -> String {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let due, !due.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: due) {
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: date)
                    break
                }
            }
        }

        do {
            try store.save(reminder, commit: true)
            return "已创建提醒：\(title)"
        } catch {
            return "创建提醒失败：\(error.localizedDescription)"
        }
    }

    private func notify(title: String, body: String, seconds: Int) -> String {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let delay = max(1, min(seconds, 86_400))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(delay), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: trigger)

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        return "已安排在 \(delay) 秒后提醒：\(title)"
    }

    private func recentPhotos(limit: Int) async -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return "相册未授权，无法读取"
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = max(1, min(limit, 10))
        let assets = PHAsset.fetchAssets(with: options)
        if assets.count == 0 { return "相册里没有照片" }

        let directory = documents().appendingPathComponent("photos")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var saved: [String] = []
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .highQualityFormat

        var index = 0
        assets.enumerateObjects { asset, _, _ in
            index += 1
            let name = "photo-\(Int(Date().timeIntervalSince1970))-\(index).jpg"
            let target = directory.appendingPathComponent(name)
            manager.requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
                guard let data else { return }
                if (try? data.write(to: target)) != nil {
                    saved.append("/photos/\(name)")
                }
            }
        }

        return saved.isEmpty ? "读取照片失败" : "已保存到沙盒：\n" + saved.joined(separator: "\n")
    }

    // MARK: - 工具函数

    private static func parse(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }
}