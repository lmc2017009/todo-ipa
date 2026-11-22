import Foundation

// MARK: - 错误

enum APIError: LocalizedError {
    case invalidURL
    case noKey
    case server(status: Int, message: String)
    case decoding(String)
    case network(String)

    var statusCode: Int? {
        if case .server(let status, _) = self { return status }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "API 地址格式不正确"
        case .noKey:
            return "还没有填写 API 密钥"
        case .server(let status, let message):
            let detail = message.isEmpty ? "" : "\n\(message)"
            switch status {
            case 400: return "请求被拒绝（400），可能是模型名或参数不被支持\(detail)"
            case 401: return "密钥无效或已过期（401）\(detail)"
            case 402: return "账户余额不足（402）\(detail)"
            case 403: return "没有访问权限（403）\(detail)"
            case 404: return "接口路径不存在（404），请检查 API 地址是否以 /v1 结尾\(detail)"
            case 413: return "内容太大了（413），请减少图片或附件\(detail)"
            case 429: return "请求过于频繁或额度用尽（429）\(detail)"
            case 500...599: return "服务端错误（\(status)）\(detail)"
            default: return "服务端返回 \(status)\(detail)"
            }
        case .decoding(let message):
            return "返回内容解析失败：\(message)"
        case .network(let message):
            return "网络错误：\(message)"
        }
    }
}

// MARK: - 流事件

enum StreamEvent {
    case delta(String)
    case thinking(String)
}

// MARK: - 客户端

struct APIClient {
    let baseURL: String
    let apiKey: String

    var normalizedBase: String { Self.normalize(baseURL) }

    /// 补全协议头与 /v1 后缀
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if !value.lowercased().hasPrefix("http") {
            value = "https://" + value
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        let lower = value.lowercased()
        if !lower.contains("/v1") && !lower.contains("/api/") {
            value += "/v1"
        }
        return value
    }

    // MARK: 模型列表

    func fetchModels() async throws -> [ModelInfo] {
        let base = normalizedBase
        guard !base.isEmpty, let url = URL(string: base + "/models") else {
            throw APIError.invalidURL
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.noKey
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.network("没有收到响应")
            }
            guard http.statusCode == 200 else {
                throw APIError.server(status: http.statusCode, message: Self.extractMessage(data))
            }

            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            let items = (decoded.data ?? []).map {
                ModelInfo(id: $0.id,
                          ownedBy: $0.owned_by ?? "",
                          supportsThinking: ModelInfo.inferThinking($0.id))
            }
            return Self.filtered(items)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.network(error.localizedDescription)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: 流式对话

    func streamChat(model: String,
                    messages: [ChatMessage],
                    settings: APISettings,
                    includeThinking: Bool) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let base = normalizedBase
                    guard !base.isEmpty, let url = URL(string: base + "/chat/completions") else {
                        throw APIError.invalidURL
                    }
                    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw APIError.noKey
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 180
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    var body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { Self.payload(for: $0) }
                    ]

                    if includeThinking {
                        switch Provider.detect(from: baseURL) {
                        case .deepseek, .moonshot, .zhipu:
                            body["thinking"] = ["type": "enabled"]
                        case .dashscope:
                            body["enable_thinking"] = true
                        default:
                            if let effort = settings.thinkingLevel.effortValue {
                                body["reasoning_effort"] = effort
                            }
                        }
                    }

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.network("没有收到响应")
                    }

                    guard http.statusCode == 200 else {
                        var text = ""
                        for try await line in bytes.lines {
                            text += line
                        }
                        throw APIError.server(status: http.statusCode,
                                              message: Self.extractMessage(Data(text.utf8)))
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, payload != "[DONE]" else { continue }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else {
                            continue
                        }
                        guard let delta = chunk.choices?.first?.delta else { continue }
                        if let text = delta.reasoning_content, !text.isEmpty {
                            continuation.yield(.thinking(text))
                        }
                        if let text = delta.reasoning, !text.isEmpty {
                            continuation.yield(.thinking(text))
                        }
                        if let text = delta.content, !text.isEmpty {
                            continuation.yield(.delta(text))
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

    // MARK: - 私有

    private static func payload(for message: ChatMessage) -> [String: Any] {
        var content = message.text
        for file in message.attachments where file.kind == .file {
            content += "\n\n【附件：\(file.fileName)】\n\(file.payload)"
        }

        let images = message.attachments.filter { $0.kind == .image }
        if images.isEmpty {
            return ["role": message.role.rawValue, "content": content]
        }

        var parts: [[String: Any]] = []
        if !content.isEmpty {
            parts.append(["type": "text", "text": content])
        }
        for image in images {
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:\(image.mimeType);base64,\(image.payload)"]
            ])
        }
        return ["role": message.role.rawValue, "content": parts]
    }

    private static func filtered(_ items: [ModelInfo]) -> [ModelInfo] {
        let blocked = ["embedding", "embed", "whisper", "tts", "moderation", "rerank",
                       "bge", "clip", "stable-diffusion", "dall-e", "sora", "audio"]
        var seen = Set<String>()
        return items.filter { model in
            let name = model.id.lowercased()
            if name.isEmpty { return false }
            if blocked.contains(where: { name.contains($0) }) { return false }
            return seen.insert(model.id).inserted
        }
    }

    private static func extractMessage(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return String(text.prefix(300))
    }

    // MARK: - 解码结构

    private struct ModelsResponse: Decodable {
        struct Item: Decodable {
            let id: String
            let owned_by: String?
        }
        let data: [Item]?
    }

    private struct StreamChunk: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoning_content: String?
            let reasoning: String?
        }
        struct Choice: Decodable {
            let delta: Delta?
        }
        let choices: [Choice]?
    }
}