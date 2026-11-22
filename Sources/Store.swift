import Foundation

/// 全局状态：会话列表 + 接口配置 + 模型缓存
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published var settings: APISettings = APISettings()
    @Published private(set) var apiKey: String = ""
    @Published private(set) var models: [ModelInfo] = []

    private let conversationsURL: URL
    private let settingsURL: URL
    private let modelsCacheKey = "aichat.models.v1"
    private var saveTask: Task<Void, Never>?

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        conversationsURL = directory.appendingPathComponent("conversations.json")
        settingsURL = directory.appendingPathComponent("settings.json")
        load()
    }

    // MARK: - 派生状态

    var hasAPI: Bool {
        !settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveModel: String {
        if !settings.model.isEmpty { return settings.model }
        return models.first?.id ?? ""
    }

    /// nil 表示未知（还没拉到模型列表）
    var currentModelSupportsThinking: Bool? {
        guard let model = models.first(where: { $0.id == effectiveModel }) else { return nil }
        return model.supportsThinking
    }

    // MARK: - 会话

    @discardableResult
    func newConversation() -> UUID {
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        flush()
        return conversation.id
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        flush()
    }

    func rename(id: UUID, title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].title = trimmed.isEmpty ? "新对话" : trimmed
        flush()
    }

    func conversation(_ id: UUID) -> Conversation? {
        conversations.first(where: { $0.id == id })
    }

    func messages(for id: UUID) -> [ChatMessage] {
        conversation(id)?.messages ?? []
    }

    func append(_ message: ChatMessage, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()

        if message.role == .user, conversations[index].title == "新对话" {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                conversations[index].title = String(trimmed.prefix(24))
            }
        }

        let updated = conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        scheduleSave()
    }

    /// 流式更新时逐字修改，不落盘（由 scheduleSave 合并写入）
    func patchMessage(_ messageID: UUID, in conversationID: UUID,
                      _ block: (inout ChatMessage) -> Void) {
        guard let cIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIndex = conversations[cIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        block(&conversations[cIndex].messages[mIndex])
        conversations[cIndex].updatedAt = Date()
        scheduleSave()
    }

    func clearConversations() {
        conversations.removeAll()
        flush()
    }

    // MARK: - 配置

    func setAPIKey(_ key: String) {
        apiKey = key
        Keychain.save(key)
    }

    func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    /// 连接测试：GET /models，顺便把模型列表拉回来
    func testConnection() async -> (message: String, succeeded: Bool) {
        let client = APIClient(baseURL: settings.baseURL, apiKey: apiKey)
        let start = Date()

        do {
            let list = try await client.fetchModels()
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            models = list
            saveModels()

            if settings.model.isEmpty, let first = list.first {
                settings.model = first.id
                saveSettings()
            }

            return ("连接成功 · \(list.count) 个模型 · \(elapsed) ms", true)
        } catch {
            return (error.localizedDescription, false)
        }
    }

    // MARK: - 持久化

    private func load() {
        if let data = try? Data(contentsOf: conversationsURL),
           let list = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = list.sorted { $0.updatedAt > $1.updatedAt }
        }

        if let data = try? Data(contentsOf: settingsURL),
           let value = try? JSONDecoder().decode(APISettings.self, from: data) {
            settings = value
        }

        if let data = UserDefaults.standard.data(forKey: modelsCacheKey),
           let list = try? JSONDecoder().decode([ModelInfo].self, from: data) {
            models = list
        }

        apiKey = Keychain.read()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: conversationsURL, options: .atomic)
    }

    private func saveModels() {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: modelsCacheKey)
    }
}
