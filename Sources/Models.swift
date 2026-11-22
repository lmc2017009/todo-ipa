import Foundation
import UIKit

// MARK: - 角色

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - 工具调用

struct ToolCallRecord: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var arguments: String
}

// MARK: - 附件

struct Attachment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case image
        case file
    }

    var id = UUID()
    var kind: Kind
    var fileName: String
    var mimeType: String
    /// 图片：压缩后 JPEG 的 base64；文本文件：原文
    var payload: String
    var byteCount: Int = 0
}

// MARK: - 搜索来源

struct SearchSource: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var snippet: String
}

// MARK: - 消息

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: ChatRole
    var text: String
    var thinking: String = ""
    var attachments: [Attachment] = []
    var sources: [SearchSource] = []
    var toolCalls: [ToolCallRecord] = []
    var toolCallID: String? = nil
    var toolTrace: String = ""
    var createdAt = Date()
    var isError: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, role, text, thinking, attachments, sources
        case toolCalls, toolCallID, toolTrace, createdAt, isError
    }

    /// 兼容旧版本没有工具字段的会话文件
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decodeIfPresent(ChatRole.self, forKey: .role) ?? .assistant
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        sources = try container.decodeIfPresent([SearchSource].self, forKey: .sources) ?? []
        toolCalls = try container.decodeIfPresent([ToolCallRecord].self, forKey: .toolCalls) ?? []
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        toolTrace = try container.decodeIfPresent(String.self, forKey: .toolTrace) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
    }

    init(id: UUID = UUID(), role: ChatRole, text: String, thinking: String = "",
         attachments: [Attachment] = [], sources: [SearchSource] = [],
         toolCalls: [ToolCallRecord] = [], toolCallID: String? = nil,
         toolTrace: String = "", createdAt: Date = Date(), isError: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.thinking = thinking
        self.attachments = attachments
        self.sources = sources
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolTrace = toolTrace
        self.createdAt = createdAt
        self.isError = isError
    }
}

// MARK: - 会话

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var createdAt = Date()
    var updatedAt = Date()
}

// MARK: - 深度思考档位

enum ThinkingLevel: String, CaseIterable, Codable, Identifiable {
    case off
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var effortValue: String? {
        switch self {
        case .off: return nil
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
}

// MARK: - 服务商（决定扩展参数用哪个字段名）

enum Provider: String, Codable, CaseIterable, Identifiable {
    case openai
    case deepseek
    case moonshot
    case zhipu
    case dashscope
    case openrouter
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .moonshot: return "Kimi"
        case .zhipu: return "智谱"
        case .dashscope: return "通义"
        case .openrouter: return "OpenRouter"
        case .custom: return "自定义"
        }
    }

    static func detect(from baseURL: String) -> Provider {
        let value = baseURL.lowercased()
        if value.contains("deepseek") { return .deepseek }
        if value.contains("moonshot") || value.contains("kimi") { return .moonshot }
        if value.contains("bigmodel") || value.contains("zhipu") || value.contains("glm") { return .zhipu }
        if value.contains("dashscope") || value.contains("aliyun") { return .dashscope }
        if value.contains("openrouter") { return .openrouter }
        if value.contains("openai") { return .openai }
        return .custom
    }
}

// MARK: - 模型

struct ModelInfo: Identifiable, Codable, Equatable {
    var id: String
    var ownedBy: String = ""
    var supportsThinking: Bool = false

    static func inferThinking(_ modelID: String) -> Bool {
        let name = modelID.lowercased()
        let hints = ["reasoner", "reasoning", "thinking", "o1", "o3", "o4", "gpt-5",
                     "r1", "qwq", "k2", "glm-4.5", "glm-4.6", "-think", "gpt-oss"]
        return hints.contains { name.contains($0) }
    }
}

// MARK: - API 设置

struct APISettings: Codable, Equatable {
    var baseURL: String = "https://api.openai.com/v1"
    var model: String = ""
    var systemPrompt: String = ""
    var thinkingLevel: ThinkingLevel = .off
    var webSearch: Bool = false
    var contextLimit: Int = 20
    /// 允许模型调用设备工具
    var enableTools: Bool = true
    /// 高危工具（写入/删除/终端/定位）执行前二次确认
    var confirmTools: Bool = true
    /// 远程终端执行器（自己的电脑），留空则用沙盒模拟终端
    var terminalHost: String = ""
    var terminalToken: String = ""

    var terminalConfigured: Bool {
        !terminalHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL, model, systemPrompt, thinkingLevel, webSearch
        case contextLimit, enableTools, confirmTools, terminalHost, terminalToken
    }

    init() { }

    /// 兼容旧版本配置文件
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.openai.com/v1"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        thinkingLevel = try container.decodeIfPresent(ThinkingLevel.self, forKey: .thinkingLevel) ?? .off
        webSearch = try container.decodeIfPresent(Bool.self, forKey: .webSearch) ?? false
        contextLimit = try container.decodeIfPresent(Int.self, forKey: .contextLimit) ?? 20
        enableTools = try container.decodeIfPresent(Bool.self, forKey: .enableTools) ?? true
        confirmTools = try container.decodeIfPresent(Bool.self, forKey: .confirmTools) ?? true
        terminalHost = try container.decodeIfPresent(String.self, forKey: .terminalHost) ?? ""
        terminalToken = try container.decodeIfPresent(String.self, forKey: .terminalToken) ?? ""
    }
}

// MARK: - 图片压缩

enum ImageTool {
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let output = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return output.jpegData(compressionQuality: quality)
    }
}