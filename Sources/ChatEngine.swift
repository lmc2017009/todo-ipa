import Foundation

/// 单次对话的流式引擎：负责联网检索 → 组装上下文 → 流式接收 → 思考参数自动降级
@MainActor
final class ChatEngine: ObservableObject {
    @Published var liveText: String = ""
    @Published var liveThinking: String = ""
    @Published var liveSources: [SearchSource] = []
    @Published var isStreaming: Bool = false
    @Published var status: String = ""

    private var task: Task<Void, Never>?

    func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
        status = ""
    }

    func send(history: [ChatMessage],
              settings: APISettings,
              apiKey: String,
              model: String,
              onComplete: @escaping @MainActor (String, String, [SearchSource], Bool) -> Void) {
        task?.cancel()

        liveText = ""
        liveThinking = ""
        liveSources = []
        isStreaming = true
        status = ""

        task = Task { [weak self] in
            guard let self else { return }

            guard let userMessage = history.last(where: { $0.role == .user }) else {
                self.isStreaming = false
                onComplete("", "", [], true)
                return
            }

            // 1. 联网检索
            var sources: [SearchSource] = []
            var systemText = settings.systemPrompt

            if settings.webSearch {
                let query = userMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    self.status = "正在联网检索…"
                    sources = await SearchService.shared.search(query: query)
                    if !sources.isEmpty {
                        self.liveSources = sources
                        let block = SearchService.contextBlock(for: sources)
                        systemText = systemText.isEmpty ? block : systemText + "\n\n" + block
                    } else {
                        self.status = "没有检索到结果，直接回答"
                    }
                }
            }

            // 2. 组装消息
            var messages: [ChatMessage] = []
            if !systemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append(ChatMessage(role: .system, text: systemText))
            }
            let limit = max(2, settings.contextLimit)
            messages.append(contentsOf: history.suffix(limit))

            self.status = "正在生成…"

            let client = APIClient(baseURL: settings.baseURL, apiKey: apiKey)
            var includeThinking = settings.thinkingLevel != .off
            var didRetryWithoutThinking = false
            var failed = false

            while true {
                do {
                    for try await event in client.streamChat(model: model,
                                                             messages: messages,
                                                             settings: settings,
                                                             includeThinking: includeThinking) {
                        if Task.isCancelled { throw CancellationError() }
                        switch event {
                        case .delta(let chunk):
                            self.liveText += chunk
                        case .thinking(let chunk):
                            self.liveThinking += chunk
                        }
                    }
                    break
                } catch is CancellationError {
                    break
                } catch {
                    let status = (error as? APIError)?.statusCode
                    if includeThinking,
                       !didRetryWithoutThinking,
                       let code = status,
                       code == 400 || code == 422 {
                        // 该模型不认思考参数 → 自动关掉重试一次
                        includeThinking = false
                        didRetryWithoutThinking = true
                        self.liveText = ""
                        self.liveThinking = ""
                        self.status = "该模型不支持思考参数，已自动降级"
                        continue
                    }
                    self.liveText = error.localizedDescription
                    failed = true
                    break
                }
            }

            self.isStreaming = false
            self.status = ""
            onComplete(self.liveText, self.liveThinking, sources, failed)
        }
    }
}