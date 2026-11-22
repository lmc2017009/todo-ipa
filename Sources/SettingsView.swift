import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore

    @State private var testing = false
    @State private var resultText: String?
    @State private var resultOK = false
    @State private var showKey = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.openai.com/v1", text: $store.settings.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { store.saveSettings() }

                    HStack {
                        Group {
                            if showKey {
                                TextField("API 密钥", text: keyBinding)
                            } else {
                                SecureField("API 密钥", text: keyBinding)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("接口")
                } footer: {
                    Text("兼容 OpenAI 协议的服务都可以：OpenAI、DeepSeek、Kimi、智谱、通义、硅基流动、OpenRouter 等。地址末尾会自动补 /v1。")
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack(spacing: 8) {
                            if testing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.horizontal.circle")
                            }
                            Text(testing ? "正在连接…" : "测试连接")
                        }
                    }
                    .disabled(testing)

                    if let resultText {
                        Text(resultText)
                            .font(.footnote)
                            .foregroundStyle(resultOK ? Color.green : Color.red)
                    }
                }

                Section("模型") {
                    if store.models.isEmpty {
                        Text("还没有模型列表，先点上面的「测试连接」。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("默认模型", selection: $store.settings.model) {
                            Text("未选择").tag("")
                            ForEach(store.models) { model in
                                Text(model.id).tag(model.id)
                            }
                        }
                        .onChange(of: store.settings.model) { _ in
                            store.saveSettings()
                        }
                    }

                    TextField("或手动输入模型 ID", text: $store.settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { store.saveSettings() }

                    Button("刷新模型列表") {
                        Task { await test() }
                    }
                    .disabled(testing)
                }

                Section("对话默认设置") {
                    Picker("深度思考", selection: $store.settings.thinkingLevel) {
                        ForEach(ThinkingLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .onChange(of: store.settings.thinkingLevel) { _ in
                        store.saveSettings()
                    }

                    Toggle("默认联网搜索", isOn: $store.settings.webSearch)
                        .onChange(of: store.settings.webSearch) { _ in
                            store.saveSettings()
                        }

                    Stepper("携带上下文 \(store.settings.contextLimit) 条",
                            value: $store.settings.contextLimit,
                            in: 4...60,
                            step: 2)
                        .onChange(of: store.settings.contextLimit) { _ in
                            store.saveSettings()
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("系统提示词")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("可选，例如「你是一名严谨的助手」",
                                  text: $store.settings.systemPrompt,
                                  axis: .vertical)
                            .lineLimit(2...6)
                            .onChange(of: store.settings.systemPrompt) { _ in
                                store.saveSettings()
                            }
                    }
                } footer: {
                    Text("深度思考是否生效取决于你接入的模型；模型不认这个参数时会自动降级重试。")
                }

                Section {
                    Button("清空全部对话", role: .destructive) {
                        showClearConfirm = true
                    }
                }

                Section {
                    LabeledContent("版本", value: "2.0 (1)")
                    LabeledContent("接口协议", value: "OpenAI 兼容")
                } footer: {
                    Text("密钥只保存在本机，不会上传到任何服务器。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog("清空全部对话？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.clearConversations() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var keyBinding: Binding<String> {
        Binding(get: { store.apiKey },
                set: { store.setAPIKey($0) })
    }

    private func test() async {
        testing = true
        resultText = nil
        let outcome = await store.testConnection()
        testing = false
        resultOK = outcome.succeeded
        resultText = outcome.message
    }
}