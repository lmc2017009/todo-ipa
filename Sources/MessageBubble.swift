import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false

    @State private var showThinking = false
    @State private var showToolOutput = false

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userBubble
            case .assistant:
                assistantBubble
            case .tool:
                toolCard
            case .system:
                EmptyView()
            }
        }
    }

    // MARK: - 用户

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)

            VStack(alignment: .trailing, spacing: 8) {
                if !message.attachments.isEmpty {
                    attachmentGrid(message.attachments)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                }

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func attachmentGrid(_ attachments: [Attachment]) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(attachments) { attachment in
                if attachment.kind == .image, let image = Self.decode(attachment) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 168, height: 126)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text(attachment.fileName)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassSurface(cornerRadius: 14)
                }
            }
        }
    }

    // MARK: - 助手

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: message.isError ? "exclamationmark.bubble" : "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.isError ? Color.red : Color.accentColor)

                Text(message.isError ? "出错了" : "助手")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if !message.toolCalls.isEmpty {
                    CapabilityBadge(title: "\(message.toolCalls.count) 次工具",
                                    icon: "wrench.and.screwdriver",
                                    tint: .orange)
                }
            }

            if !message.thinking.isEmpty {
                thinkingPanel
            }

            if message.text.isEmpty {
                if isStreaming {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在生成")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } else if message.isError {
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                MarkdownText(text: message.text)
            }

            if !message.sources.isEmpty {
                sourceList
            }

            if !message.toolCalls.isEmpty && !isStreaming {
                toolChips
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22)
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("复制回答", systemImage: "doc.on.doc")
            }
        }
    }

    private var thinkingPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showThinking.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .semibold))
                    Text(showThinking ? "收起思考过程" : "查看思考过程")
                        .font(.caption2.weight(.medium))
                    Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(message.thinking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var toolChips: some View {
        FlowRow(spacing: 6) {
            ForEach(message.toolCalls) { call in
                CapabilityBadge(title: call.name,
                                icon: Self.icon(for: call.name),
                                tint: .orange)
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                Text("联网来源")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            ForEach(Array(message.sources.enumerated()), id: \.element.id) { index, source in
                Link(destination: URL(string: source.url) ?? URL(string: "https://example.com")!) {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor.opacity(0.16), in: Circle())

                        Text(source.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 工具结果

    private var toolCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showToolOutput.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10, weight: .semibold))
                    Text(toolTitle)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: showToolOutput ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showToolOutput {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(message.text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 16)
    }

    private var toolTitle: String {
        let trace = message.toolTrace.trimmingCharacters(in: .whitespacesAndNewlines)
        if trace.isEmpty { return "工具结果" }
        return String(trace.prefix(60))
    }

    // MARK: - 工具函数

    private static func decode(_ attachment: Attachment) -> UIImage? {
        guard let data = Data(base64Encoded: attachment.payload) else { return nil }
        return UIImage(data: data)
    }

    private static func icon(for tool: String) -> String {
        switch tool {
        case "device_info": return "iphone.gen3"
        case "shell": return "terminal"
        case let name where name.hasPrefix("fs_"): return "folder"
        case "clipboard": return "doc.on.clipboard"
        case "motion": return "gyroscope"
        case "location": return "location"
        case "contacts_search": return "person.crop.circle"
        case "calendar_events": return "calendar"
        case "reminder_create": return "checklist"
        case "notify": return "bell"
        case "photos_recent": return "photo.stack"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - 自动换行布局

struct FlowRow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                width = max(width, lineWidth)
                height += lineHeight + lineSpacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        width = max(width, lineWidth)
        height += lineHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}