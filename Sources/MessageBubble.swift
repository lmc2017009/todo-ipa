import SwiftUI

@MainActor
struct MessageBubble: View {
    let message: ChatMessage
    var streaming: Bool = false

    @State private var showThinking = false

    private var images: [Attachment] {
        message.attachments.filter { $0.kind == .image }
    }

    private var files: [Attachment] {
        message.attachments.filter { $0.kind == .file }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if !message.thinking.isEmpty {
                    thinkingBlock
                }

                if !images.isEmpty {
                    imageRow
                }

                if !files.isEmpty {
                    fileRow
                }

                if !message.text.isEmpty {
                    if message.role == .user {
                        userText
                    } else {
                        MarkdownText(text: message.text)
                            .foregroundStyle(message.isError ? Color.red : Color.primary)
                    }
                }

                if !message.sources.isEmpty {
                    sourceList
                }

                if streaming && message.text.isEmpty && message.thinking.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在生成…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if message.role != .user {
                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity,
               alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: - 片段

    private var userText: some View {
        Text(message.text)
            .font(.body)
            .foregroundStyle(Color.white)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var thinkingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showThinking.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(showThinking ? "收起思考过程" : "查看思考过程")
                    Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(message.thinking)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var imageRow: some View {
        HStack(spacing: 6) {
            ForEach(images) { item in
                if let data = Data(base64Encoded: item.payload), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var fileRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(files) { item in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text(item.fileName)
                        .lineLimit(1)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("参考来源")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(message.sources) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        Text("· \(source.title.isEmpty ? source.url : source.title)")
                            .font(.caption)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}