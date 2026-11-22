import Foundation
import UIKit

// MARK: - 角色

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
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
    var createdAt = Date()
    var isError: Bool = false
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

    /// 只根据模型名做“可能性”推断，真正是否支持由接口返回 / 400 自动降级决定
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