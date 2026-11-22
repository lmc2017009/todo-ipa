import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    let conversationID: UUID

    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var engine: ChatEngine
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var approvals: ApprovalCenter

    @State private var text: String = ""
    @State private var attachments: [Attachment] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var banner: String?

    var body: some View {
        VStack(spacing: 0) {
            messageList
        }
        .liquidBackdrop()
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(store.conversation(conversationID)?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { modelMenu }
        }
        .sheet(item: approvalBinding) { request in
            ApprovalSheet(request: request) { approved in
                approvals.resolve(approved)
            }
            .presentationDetents([.medium])
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.plainText, .text, .json, .commaSeparatedText, .xml, .sourceCode],
                      allowsMultipleSelection: false) { result in
            handleFile(result)
        }
        .onChange(of: pickedItems) { items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .alert("提示", isPresented: bannerBinding) {
            Button("知道了", role: .cancel) { banner = nil }
        } message: {
            Text(banner ?? "")
        }
    }

    // MARK: - 消息列表

    private var messages: [ChatMessage] {
        store.messages(for: conversationID)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if messages.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    }

                    ForEach(messages) { message in
                        MessageBubble(message: message,
                                      isStreaming: engine.isBusy(conversationID)
                                          && message.id == messages.last?.id
                                          && message.role == .assistant)
                            .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: messages.last?.text) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)

            Text("可以开始问了")
                .font(.headline)

            Text("模型取决于你在设置里接入的服务；\n已授权的设备能力会直接交给模型使用。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            FlowRow(spacing: 6) {
                ForEach(permissions.enabledKinds.prefix(6)) { kind in
                    CapabilityBadge(title: kind.title, icon: kind.icon)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 输入区

    private var composer: some View {
        VStack(spacing: 10) {
            if !attachments.isEmpty {
                attachmentStrip
            }
            HStack(spacing: 8) {
                attachMenu
                photoPicker


                TextField("发消息…", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.body)
                    .padding(.vertical, 6)

                sendButton
            }

            chipRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 28)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        if attachment.kind == .image,
                           let data = Data(base64Encoded: attachment.payload),
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                Text(attachment.fileName)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .frame(height: 58)
                            .frame(maxWidth: 150)
                            .glassSurface(cornerRadius: 12)
                        }

                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.55))
                        }
                        .offset(x: 5, y: -5)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private var attachMenu: some View {
        Menu {
            Button {
                showFileImporter = true
            } label: {
                Label("添加文本文件", systemImage: "doc.badge.plus")
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 22, weight: .light))
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $pickedItems, maxSelectionCount: 4, matching: .images) {
            Image(systemName: "photo.circle")
                .font(.system(size: 22, weight: .light))
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if engine.isBusy(conversationID) {
            Button {
                engine.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(.red)
            }
        } else {
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .disabled(!canSend)
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            Menu {
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
            } label: {
                CapabilityBadge(title: "思考 \(store.settings.thinkingLevel.title)",
                                icon: "brain",
                                tint: store.settings.thinkingLevel == .off ? .secondary : .purple)
            }

            Button {
                store.settings.webSearch.toggle()
                store.saveSettings()
            } label: {
                CapabilityBadge(title: "联网",
                                icon: "globe",
                                tint: store.settings.webSearch ? .green : .secondary)
            }
            .buttonStyle(.plain)

            CapabilityBadge(title: "\(permissions.enabledKinds.count) 项能力",
                            icon: "square.stack.3d.up",
                            tint: .blue)

            Spacer(minLength: 0)

            if !store.settings.enableTools {
                CapabilityBadge(title: "工具已关", icon: "wrench.and.screwdriver", tint: .orange)
            }
        }
    }

    private var modelMenu: some View {
        Menu {
            if store.models.isEmpty {
                Button("到设置里拉取模型列表") { }
            } else {
                ForEach(store.models.prefix(40)) { model in
                    Button {
                        store.settings.model = model.id
                        store.saveSettings()
                    } label: {
                        if store.effectiveModel == model.id {
                            Label(model.id, systemImage: "checkmark")
                        } else {
                            Text(model.id)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text(store.effectiveModel.isEmpty ? "选择模型" : store.effectiveModel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassSurface(cornerRadius: 12)
        }
    }

    // MARK: - 逻辑

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private func send() {
        guard canSend else { return }
        let payload = text
        let files = attachments
        text = ""
        attachments = []
        engine.start(conversationID: conversationID, text: payload, attachments: files)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = ImageTool.jpeg(image) else { continue }

            let attachment = Attachment(kind: .image,
                                        fileName: "image-\(Int(Date().timeIntervalSince1970)).jpg",
                                        mimeType: "image/jpeg",
                                        payload: jpeg.base64EncodedString(),
                                        byteCount: jpeg.count)
            attachments.append(attachment)
        }
        pickedItems = []
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            banner = "读不到这个文件"
            return
        }

        guard let content = String(data: data, encoding: .utf8) else {
            banner = "目前只支持文本类文件（PDF / Word 请先转成文本）"
            return
        }

        attachments.append(Attachment(kind: .file,
                                      fileName: url.lastPathComponent,
                                      mimeType: "text/plain",
                                      payload: String(content.prefix(60_000)),
                                      byteCount: data.count))
    }

    private var bannerBinding: Binding<Bool> {
        Binding(get: { banner != nil }, set: { if !$0 { banner = nil } })
    }

    private var approvalBinding: Binding<ApprovalCenter.Request?> {
        Binding(get: { approvals.request },
                set: { value in
                    if value == nil, approvals.request != nil {
                        approvals.resolve(false)
                    }
                })
    }
}

// MARK: - 确认弹窗

struct ApprovalSheet: View {
    let request: ApprovalCenter.Request
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: request.isDangerous ? "exclamationmark.triangle.fill" : "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(request.isDangerous ? .orange : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("模型想执行工具")
                        .font(.headline)
                    Text(request.call.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            ScrollView {
                Text(request.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(12)
            .glassSurface(cornerRadius: 14)

            if request.isDangerous {
                Text("这个操作会修改设备上的内容，请确认你了解它的作用。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    onDecision(false)
                } label: {
                    Text("拒绝")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button {
                    onDecision(true)
                } label: {
                    Text("允许")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}