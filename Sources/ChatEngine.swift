import Foundation

/// 对话引擎：检索 → 组装上下文 → 流式输出 → 工具循环
@MainActor
final class ChatEngine: ObservableObject {
    @Published private(set) var runningConversation: UUID?
    @Published private(set) var lastError: String?

    private let store: ChatStore
    private let permissions: PermissionCenter
    private let approvals: ApprovalCenter
    private var runTask: Task<Void, Never>?

    /// 需要二次确认的工具
    private let guardedTools: Set<String> = ["shell", "fs_write", "fs_delete", "reminder_create"]

    init(store: ChatStore, permissions: PermissionCenter, approvals: ApprovalCenter) {
        self.store = store
        self.permissions = permissions
        self.approvals = approvals
    }

    var isRunning: Bool { runningConversation != nil }

    func isBusy(_ conversationID: UUID) -> Bool {
        runningConversation == conversationID
    }

    // MARK: - 入口

    func start(conversationID: UUID, text: String, attachments: [Attachment]) {
        guard runningConversation == nil else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed, attachments: attachments)
        store.append(userMessage, to: conversationID)

        lastError = nil
        runningConversation = conversationID

        runTask = Task { @MainActor in
            await self.perform(conversationID: conversationID)
            self.runningConversation = nil
            self.runTask = nil
            self.store.flush()
        }
    }

    func stop() {
        runTask?.cancel()
    }

    // MARK: - 主流程

    private func perform(conversationID: UUID) async {
        guard !store.settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = ChatMessage(role: .assistant,
                                      text: "还没有配置接口。请到「设置」填写 API 端点和密钥，再点测试连接。",
                                      isError: true)
            store.append(message, to: conversationID)
            return
        }

        let settings = store.settings
        let client = APIClient(baseURL: settings.baseURL, apiKey: store.apiKey)
        let enabled = permissions.enabledKinds
        // 相机 / 麦克风只做系统授权，没有对应的工具，避免提示里说了却调不到
        let toolKinds = enabled.filter { $0 != .camera && $0 != .microphone }

        var tools: [[String: Any]] = []
        if settings.enableTools && !toolKinds.isEmpty {
            tools = ToolCenter.shared.definitions(enabled: toolKinds,
                                                  terminalConfigured: settings.terminalConfigured)
        }

        var assistant = ChatMessage(role: .assistant, text: "")
        store.append(assistant, to: conversationID)
        var assistantID = assistant.id

        var searchBlock: String?
        if settings.webSearch {
            let query = store.messages(for: conversationID)
                .last(where: { $0.role == .user })?.text ?? ""
            if !query.isEmpty {
                let sources = await SearchService.shared.search(query: query)
                if !sources.isEmpty {
                    store.patchMessage(assistantID, in: conversationID) { $0.sources = sources }
                    searchBlock = SearchService.contextBlock(for: sources)
                }
            }
        }

        var disableExtras = false
        var disableTools = tools.isEmpty
        var rounds = 0

        while rounds < 5 {
            rounds += 1

            if Task.isCancelled {
                markStopped(assistantID, in: conversationID)
                return
            }

            let payload = buildMessages(conversationID: conversationID,
                                       excluding: assistantID,
                                       searchBlock: searchBlock,
                                       enabled: toolKinds,
                                       settings: settings)

            var collectedText = ""
            var collectedThinking = ""
            var calls: [ToolCallRecord] = []
            var streamError: Error?

            do {
                let stream = client.stream(messages: payload,
                                           settings: settings,
                                           tools: disableTools ? [] : tools,
                                           disableExtras: disableExtras)

                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .content(let chunk):
                        collectedText += chunk
                        store.patchMessage(assistantID, in: conversationID) { $0.text = collectedText }

                    case .reasoning(let chunk):
                        collectedThinking += chunk
                        store.patchMessage(assistantID, in: conversationID) { $0.thinking = collectedThinking }

                    case .toolCalls(let list):
                        calls = list
                    }
                }
            } catch {
                streamError = error
            }

            if Task.isCancelled {
                markStopped(assistantID, in: conversationID)
                return
            }

            // 服务端不支持扩展参数 / 工具时自动降级重试
            if let error = streamError as? APIError, error.retryableWithoutExtras {
                let message = error.errorDescription ?? ""
                let toolProblem = message.lowercased().contains("tool")
                if toolProblem && !disableTools {
                    disableTools = true
                    reset(assistantID, in: conversationID)
                    rounds -= 1
                    continue
                }
                if !disableExtras {
                    disableExtras = true
                    reset(assistantID, in: conversationID)
                    rounds -= 1
                    continue
                }
                if !disableTools {
                    disableTools = true
                    reset(assistantID, in: conversationID)
                    rounds -= 1
                    continue
                }
            }

            if let error = streamError {
                let text = error.localizedDescription
                lastError = text
                store.patchMessage(assistantID, in: conversationID) {
                    if $0.text.isEmpty {
                        $0.text = text
                    } else {
                        $0.text += "\n\n" + text
                    }
                    $0.isError = true
                }
                return
            }

            if calls.isEmpty {
                break
            }

            store.patchMessage(assistantID, in: conversationID) { $0.toolCalls = calls }

            for call in calls {
                if Task.isCancelled {
                    markStopped(assistantID, in: conversationID)
                    return
                }

                let approved = await approveIfNeeded(call, settings: settings)
                if Task.isCancelled {
                    markStopped(assistantID, in: conversationID)
                    return
                }

                let result: String
                if approved {
                    let raw = await ToolCenter.shared.run(call, settings: settings)
                    // 工具输出过长会撑爆上下文，截断后再回填给模型
                    if raw.count > 8_000 {
                        result = String(raw.prefix(8_000)) + "\n…（输出过长已截断）"
                    } else {
                        result = raw
                    }
                } else {
                    result = "用户拒绝了这次工具调用。请换一种方式回答，或向用户说明需要这项权限。"
                }

                let record = ChatMessage(role: .tool,
                                         text: result,
                                         toolCallID: call.id,
                                         toolTrace: "\(call.name) \(call.arguments)")
                store.append(record, to: conversationID)
            }

            let next = ChatMessage(role: .assistant, text: "")
            store.append(next, to: conversationID)
            assistantID = next.id
        }

        // 收尾：完全没有内容时给出提示
        let lastMessage = store.messages(for: conversationID).first(where: { $0.id == assistantID })
        if let lastMessage, lastMessage.text.isEmpty, lastMessage.thinking.isEmpty, lastMessage.toolCalls.isEmpty {
            store.patchMessage(assistantID, in: conversationID) {
                $0.text = "（模型没有返回内容，可以换个模型或再试一次）"
            }
        }
    }

    // MARK: - 上下文

    private func buildMessages(conversationID: UUID,
                               excluding messageID: UUID,
                               searchBlock: String?,
                               enabled: [CapabilityKind],
                               settings: APISettings) -> [[String: Any]] {

        var payload: [[String: Any]] = [
            ["role": "system", "content": systemPrompt(settings: settings,
                                                       enabled: enabled,
                                                       searchBlock: searchBlock)]
        ]

        let history = store.messages(for: conversationID).filter { message in
            if message.id == messageID { return false }
            if message.role == .assistant,
               message.text.isEmpty, message.thinking.isEmpty, message.toolCalls.isEmpty {
                return false
            }
            return true
        }

        let limit = max(2, min(settings.contextLimit, 60))
        for message in history.suffix(limit) {
            payload.append(APIClient.payload(for: message))
        }
        return payload
    }

    private func systemPrompt(settings: APISettings,
                              enabled: [CapabilityKind],
                              searchBlock: String?) -> String {
        var lines: [String] = []

        let custom = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append(custom)
        }

        lines.append("你是运行在用户 iPhone 上的 AI 助手。用中文回答，直接、准确、简洁；需要结构化时用 Markdown。")

        lines.append(DeviceProfile.summary())

        if settings.enableTools && !enabled.isEmpty {
            let list = enabled.map { "- \($0.title)：\($0.detail)" }.joined(separator: "\n")
            lines.append("""
            ## 你可以直接操作这台设备
            下面这些能力已经由用户授权，你可以调用工具完成，不要推给用户手动去做：
            \(list)

            调用规则：
            1. 需要设备上的真实数据（文件、电量、相册、位置、通讯录、日程）或需要执行命令、写文件时，直接发起工具调用。
            2. 不要编造工具结果，也不要说"我无法访问你的设备"。
            3. 工具报错时如实转述错误，并给出可行的替代方案。
            4. 只调用真正必要的工具，一次调用能解决就不要拆成多次。
            """)

            if !settings.terminalConfigured {
                lines.append("终端工具当前是 App 沙盒内的模拟终端，只能读写 App 自己的文档目录；需要真实 shell 时，提示用户在「设置」填写远程终端地址。")
            }
        } else {
            lines.append("当前没有可用的设备工具，只能基于对话内容和你的知识回答。")
        }

        if let searchBlock {
            lines.append(searchBlock)
        }

        lines.append("当前时间：\(DeviceProfile.dateText(Date()))")
        return lines.joined(separator: "\n\n")
    }

    // MARK: - 确认与收尾

    private func approveIfNeeded(_ call: ToolCallRecord, settings: APISettings) async -> Bool {
        guard settings.confirmTools, guardedTools.contains(call.name) else { return true }

        let detail = Self.describe(call)
        return await approvals.ask(call: call,
                                   detail: detail,
                                   isDangerous: call.name == "shell" || call.name == "fs_delete")
    }

    static func describe(_ call: ToolCallRecord) -> String {
        guard let data = call.arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return call.arguments
        }
        switch call.name {
        case "shell":
            return object["command"] as? String ?? call.arguments
        case "fs_write":
            let path = object["path"] as? String ?? "?"
            let content = object["content"] as? String ?? ""
            return "写入 \(path)\n\n" + String(content.prefix(300))
        case "fs_delete":
            return object["path"] as? String ?? call.arguments
        case "reminder_create":
            return object["title"] as? String ?? call.arguments
        default:
            return call.arguments
        }
    }

    private func markStopped(_ messageID: UUID, in conversationID: UUID) {
        store.patchMessage(messageID, in: conversationID) { message in
            if message.text.isEmpty {
                message.text = "（已停止生成）"
            } else {
                message.text += "\n\n（已停止生成）"
            }
        }
    }

    private func reset(_ messageID: UUID, in conversationID: UUID) {
        store.patchMessage(messageID, in: conversationID) { message in
            message.text = ""
            message.thinking = ""
            message.toolCalls = []
        }
    }
}