import Foundation

// MARK: - 流事件

enum StreamEvent {
    case content(String)
    case reasoning(String)
    case toolCalls([ToolCallRecord])
}

// MARK: - 错误

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "接口地址无效，请检查设置里的 API 端点"
        case .unauthorized:
            return "密钥无效或没有权限（401）"
        case .http(let code, let message):
            return "请求失败（\(code)）：\(message)"
        case .empty:
            return "服务器返回了空内容"
        }
    }

    /// 400 / 404 / 422 可能是不支持某个扩展参数，可去掉后重试
    var retryableWithoutExtras: Bool {
        if case .http(let code, _) = self {
            return code == 400 || code == 404 || code == 422 || code == 500
        }
        return false
    }
}

// MARK: - 客户端

final class APIClient {
    let baseURL: String
    let apiKey: String

    private let session: URLSession

    init(baseURL: String, apiKey: String) {
        self.baseURL = APIClient.normalize(baseURL)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.lowercased().hasSuffix("/chat/completions") {
            value = String(value.dropLast("/chat/completions".count))
        }
        return value
    }

    private var chatURL: URL? {
        URL(string: baseURL + "/chat/completions")
    }

    private var modelsURL: URL? {
        URL(string: baseURL + "/models")
    }

    // MARK: 模型列表

    func fetchModels() async throws -> [ModelInfo] {
        guard let url = modelsURL else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.empty }

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard http.statusCode == 200 else {
            throw APIError.http(http.statusCode, Self.friendly(data))
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.empty
        }

        let rawList = (object["data"] as? [[String: Any]])
            ?? (object["models"] as? [[String: Any]])
            ?? []

        let blocked = ["embedding", "embed", "whisper", "tts", "dall-e", "moderation",
                       "audio", "realtime", "image", "rerank"]

        var result: [ModelInfo] = []
        for item in rawList {
            guard let id = item["id"] as? String, !id.isEmpty else { continue }
            let lower = id.lowercased()
            if blocked.contains(where: { lower.contains($0) }) { continue }
            let owner = (item["owned_by"] as? String) ?? ""
            result.append(ModelInfo(id: id, ownedBy: owner, supportsThinking: ModelInfo.inferThinking(id)))
        }

        return result.sorted { $0.id < $1.id }
    }

    // MARK: 流式对话

    func stream(messages: [[String: Any]],
                settings: APISettings,
                tools: [[String: Any]],
                disableExtras: Bool = false) -> AsyncThrowingStream<StreamEvent, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = self.chatURL else { throw APIError.badURL }

                    var body = self.requestBody(messages: messages, settings: settings, tools: tools)
                    if disableExtras {
                        body.removeValue(forKey: "reasoning_effort")
                        body.removeValue(forKey: "enable_thinking")
                        body.removeValue(forKey: "thinking")
                        body.removeValue(forKey: "thinking_budget")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if !self.apiKey.isEmpty {
                        request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.empty }

                    if http.statusCode == 401 { throw APIError.unauthorized }
                    guard http.statusCode == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw APIError.http(http.statusCode, Self.friendly(data))
                    }

                    // 有些兼容实现会忽略 stream，直接返回整段 JSON
                    let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                    if contentType.contains("application/json") {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        self.emitWholeResponse(data: data, continuation: continuation)
                        continuation.finish()
                        return
                    }

                    var buffers: [Int: ToolBuffer] = [:]

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }

                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        if let error = object["error"] as? [String: Any] {
                            let message = (error["message"] as? String) ?? "服务端返回错误"
                            throw APIError.http(400, message)
                        }

                        guard let choices = object["choices"] as? [[String: Any]],
                              let first = choices.first else { continue }

                        let delta = (first["delta"] as? [String: Any])
                            ?? (first["message"] as? [String: Any])
                            ?? [:]

                        if let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(.content(content))
                        }
                        if let thinking = delta["reasoning_content"] as? String, !thinking.isEmpty {
                            continuation.yield(.reasoning(thinking))
                        } else if let thinking = delta["reasoning"] as? String, !thinking.isEmpty {
                            continuation.yield(.reasoning(thinking))
                        }

                        if let calls = delta["tool_calls"] as? [[String: Any]] {
                            for (order, item) in calls.enumerated() {
                                let index = (item["index"] as? Int) ?? order
                                let buffer = buffers[index] ?? ToolBuffer()
                                if let id = item["id"] as? String, !id.isEmpty {
                                    buffer.id = id
                                }
                                if let function = item["function"] as? [String: Any] {
                                    if let name = function["name"] as? String, !name.isEmpty {
                                        buffer.name += name
                                    }
                                    if let arguments = function["arguments"] as? String {
                                        buffer.arguments += arguments
                                    }
                                }
                                buffers[index] = buffer
                            }
                        }
                    }

                    if !buffers.isEmpty {
                        let calls = buffers.keys.sorted().compactMap { key -> ToolCallRecord? in
                            guard let buffer = buffers[key], !buffer.name.isEmpty else { return nil }
                            let id = buffer.id.isEmpty
                                ? "call_\(key)_\(Int(Date().timeIntervalSince1970))"
                                : buffer.id
                            return ToolCallRecord(id: id,
                                                  name: buffer.name,
                                                  arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments)
                        }
                        if !calls.isEmpty {
                            continuation.yield(.toolCalls(calls))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 组装

    private func requestBody(messages: [[String: Any]],
                             settings: APISettings,
                             tools: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "model": settings.effectiveModelName,
            "messages": messages,
            "stream": true
        ]

        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        let provider = Provider.detect(from: baseURL)
        if let effort = settings.thinkingLevel.effortValue {
            switch provider {
            case .openai, .openrouter, .custom:
                body["reasoning_effort"] = effort
            case .dashscope:
                body["enable_thinking"] = true
                body["thinking_budget"] = settings.thinkingLevel == .high ? 4096 : 1024
            case .zhipu, .moonshot:
                body["thinking"] = ["type": "enabled"]
            case .deepseek:
                break
            }
        }

        return body
    }

    private func emitWholeResponse(data: Data,
                                   continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first else { return }

        let message = (first["message"] as? [String: Any]) ?? [:]

        if let thinking = message["reasoning_content"] as? String, !thinking.isEmpty {
            continuation.yield(.reasoning(thinking))
        }
        if let content = message["content"] as? String, !content.isEmpty {
            continuation.yield(.content(content))
        }
        if let calls = message["tool_calls"] as? [[String: Any]] {
            let records = calls.compactMap { item -> ToolCallRecord? in
                guard let function = item["function"] as? [String: Any],
                      let name = function["name"] as? String else { return nil }
                return ToolCallRecord(id: (item["id"] as? String) ?? UUID().uuidString,
                                      name: name,
                                      arguments: (function["arguments"] as? String) ?? "{}")
            }
            if !records.isEmpty { continuation.yield(.toolCalls(records)) }
        }
    }

    // MARK: 工具函数

    /// 把会话消息序列化成 OpenAI 协议
    static func payload(for message: ChatMessage) -> [String: Any] {
        var result: [String: Any] = ["role": message.role.rawValue]

        switch message.role {
        case .tool:
            result["content"] = message.text
            result["tool_call_id"] = message.toolCallID ?? ""

        case .assistant:
            if message.toolCalls.isEmpty {
                result["content"] = message.text
            } else {
                result["content"] = message.text.isEmpty ? NSNull() : message.text
                result["tool_calls"] = message.toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.arguments]
                    ] as [String: Any]
                }
            }

        case .user:
            let images = message.attachments.filter { $0.kind == .image }
            let files = message.attachments.filter { $0.kind == .file }

            if images.isEmpty {
                var text = message.text
                for file in files {
                    text += "\n\n[附件 \(file.fileName)]\n\(file.payload)"
                }
                result["content"] = text
            } else {
                var parts: [[String: Any]] = []
                if !message.text.isEmpty {
                    parts.append(["type": "text", "text": message.text])
                }
                for image in images {
                    parts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(image.mimeType);base64,\(image.payload)"]
                    ])
                }
                for file in files {
                    parts.append(["type": "text", "text": "[附件 \(file.fileName)]\n\(file.payload)"])
                }
                result["content"] = parts
            }

        case .system:
            result["content"] = message.text
        }

        return result
    }

    private static func friendly(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        let text = String(data: data, encoding: .utf8) ?? "无详细信息"
        return String(text.prefix(300))
    }
}

// MARK: - 工具调用缓冲

private final class ToolBuffer {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}

// MARK: - 便捷访问

extension APISettings {
    /// 当前实际使用的模型名（空时用列表第一个）
    var effectiveModelName: String {
        model.isEmpty ? "gpt-4o-mini" : model
    }
}