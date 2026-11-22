import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @StateObject private var engine = ChatEngine()

    let conversationID: UUID

    @State private var input: String = ""
    @State private var pending: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFilePicker = false
    @State private var notice: String?

    private var conversation: Conversation? {
        store.conversations.first(where: { $0.id == conversationID })
    }

    private var messages: [ChatMessage] {
        conversation?.messages ?? []
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty
    }

    private var modelLabel: String {
        let model = store.effectiveModel
        return model.isEmpty ? "选择模型" : model
    }

    var body: some View {
        VStack(spacing: 0) {
            messageArea
            composer
        }
        .navigationTitle(conversation?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                importFiles(urls)
            }
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            importPhotos(items)
            photoItems = []
        }
        .alert("提示", isPresented: noticeBinding) {
            Button("好", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: - 消息区

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty && !engine.isStreaming {
                        emptyState
                    }

                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }

                    if engine.isStreaming {
                        MessageBubble(message: ChatMessage(role: .assistant,
                                                           text: engine.liveText,
                                                           thinking: engine.liveThinking,
                                                           sources: engine.liveSources),
                                      streaming: true)
                    }

                    if !engine.status.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(engine.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("BOTTOM")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: engine.liveText) { _ in
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
            .onChange(of: messages.count) { _ in
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            Text("想聊点什么？")
                .font(.title3.weight(.semibold))

            Text("可以发文字、发照片、传文件；需要实时信息就打开联网搜索。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 30)
    }

    // MARK: - 输入区

    private var composer: some View {
        VStack(spacing: 0) {
            if !pending.isEmpty {
                attachmentStrip
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22))
                }

                Button {
                    showFilePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 22))
                }

                TextField("发消息…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pending) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.kind == .image ? "photo" : "doc.text")
                        Text(item.fileName)
                            .lineLimit(1)
                        Button {
                            pending.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var sendButton: some View {
        Button {
            if engine.isStreaming {
                engine.stop()
            } else {
                send()
            }
        } label: {
            Image(systemName: engine.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(canSend || engine.isStreaming ? Color.accentColor : Color.secondary)
        }
        .disabled(!canSend && !engine.isStreaming)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Section("模型") {
                    if store.models.isEmpty {
                        Button("从接口加载模型列表") {
                            Task { await store.testConnection() }
                        }
                    } else {
                        ForEach(store.models) { model in
                            Button {
                                store.settings.model = model.id
                                store.saveSettings()
                            } label: {
                                if model.id == store.effectiveModel {
                                    Label(model.id, systemImage: "checkmark")
                                } else {
                                    Text(model.id)
                                }
                            }
                        }
                    }
                }

                Section("深度思考") {
                    ForEach(ThinkingLevel.allCases) { level in
                        Button {
                            store.settings.thinkingLevel = level
                            store.saveSettings()
                        } label: {
                            if store.settings.thinkingLevel == level {
                                Label(level.title, systemImage: "checkmark")
                            } else {
                                Text(level.title)
                            }
                        }
                    }

                    if store.currentModelSupportsThinking == false {
                        Text("该模型未标注支持思考，会自动降级")
                    }
                }

                Section {
                    Button {
                        store.settings.webSearch.toggle()
                        store.saveSettings()
                    } label: {
                        Label(store.settings.webSearch ? "关闭联网搜索" : "开启联网搜索",
                              systemImage: store.settings.webSearch ? "globe.badge.chevron.backward" : "globe")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.settings.webSearch ? "globe" : "cpu")
                    Text(modelLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.footnote)
            }
        }
    }

    // MARK: - 动作

    private var noticeBinding: Binding<Bool> {
        Binding(get: { notice != nil },
                set: { if !$0 { notice = nil } })
    }

    private func send() {
        guard !engine.isStreaming else { return }
        guard store.hasAPI else {
            notice = "请先在「设置」里填写 API 地址和密钥"
            return
        }
        guard !store.effectiveModel.isEmpty else {
            notice = "请先选择或填写一个模型"
            return
        }

        var message = ChatMessage(role: .user,
                                  text: input.trimmingCharacters(in: .whitespacesAndNewlines))
        message.attachments = pending
        store.append(message, to: conversationID)

        input = ""
        pending = []

        let history = store.messages(for: conversationID)
        let settings = store.settings
        let key = store.apiKey
        let model = store.effectiveModel
        let target = conversationID

        engine.send(history: history, settings: settings, apiKey: key, model: model) { text, thinking, sources, failed in
            var reply = ChatMessage(role: .assistant, text: text)
            reply.thinking = thinking
            reply.sources = sources
            reply.isError = failed
            store.append(reply, to: target)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = ImageTool.jpeg(image) else {
                    continue
                }
                let attachment = Attachment(kind: .image,
                                           fileName: "图片-\(pending.count + 1).jpg",
                                           mimeType: "image/jpeg",
                                           payload: jpeg.base64EncodedString(),
                                           byteCount: jpeg.count)
                pending.append(attachment)
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            guard let data = try? Data(contentsOf: url) else { continue }

            if data.count <= 300_000, let text = String(data: data, encoding: .utf8) {
                let attachment = Attachment(kind: .file,
                                            fileName: url.lastPathComponent,
                                            mimeType: "text/plain",
                                            payload: text,
                                            byteCount: data.count)
                pending.append(attachment)
            } else {
                notice = "「\(url.lastPathComponent)」不是可读的文本文件，暂时只能发送图片或文本类文件"
            }
        }
    }
}