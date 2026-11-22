import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var permissions: PermissionCenter

    @State private var isTesting = false
    @State private var testResult: (message: String, succeeded: Bool)?
    @State private var showTerminalHelp = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    apiCard
                    modelCard
                    chatCard
                    terminalCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .liquidBackdrop()
            .navigationTitle("设置")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.settings) { _ in
                store.saveSettings()
            }
            .confirmationDialog("清空所有对话？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    store.clearConversations()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("这个操作不可撤销")
            }
        }
    }

    // MARK: - 接口

    private var apiCard: some View {
        SectionGlassCard(title: "接口", icon: "network") {
            VStack(alignment: .leading, spacing: 10) {
                Text("API 端点")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("https://api.openai.com/v1", text: $store.settings.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(11)
                    .background(Color.secondary.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("API 密钥")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("sk-…", text: Binding(
                    get: { store.apiKey },
                    set: { store.setAPIKey($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, design: .monospaced))
                .padding(11)
                .background(Color.secondary.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        test()
                    } label: {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.horizontal.circle")
                            }
                            Text(isTesting ? "测试中…" : "测试连接")
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting)

                    Button {
                        Task { await refreshModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 44)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting)
                }

                if let testResult {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: testResult.succeeded ? "checkmark.circle" : "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(testResult.succeeded ? .green : .red)

                        Text(testResult.message)
                            .font(.caption2)
                            .foregroundStyle(testResult.succeeded ? Color.secondary : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 模型

    private var modelCard: some View {
        SectionGlassCard(title: "模型", icon: "cpu") {
            VStack(alignment: .leading, spacing: 10) {
                if store.models.isEmpty {
                    Text("还没有模型列表，点上面的刷新或测试连接来拉取；也可以直接手填模型名。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("模型名，例如 gpt-4o-mini", text: $store.settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .padding(11)
                    .background(Color.secondary.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !store.models.isEmpty {
                    Menu {
                        ForEach(store.models) { model in
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
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("从 \(store.models.count) 个模型里选")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .font(.footnote)
                        .padding(11)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let supports = store.currentModelSupportsThinking {
                    HStack(spacing: 5) {
                        Image(systemName: supports ? "brain" : "questionmark.circle")
                            .font(.system(size: 10))
                        Text(supports ? "这个模型支持深度思考" : "这个模型没有明显的思考标记")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 对话

    private var chatCard: some View {
        SectionGlassCard(title: "对话", icon: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: 12) {
                Text("系统提示词（可选）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $store.settings.systemPrompt)
                    .font(.footnote)
                    .frame(minHeight: 74, maxHeight: 120)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Toggle("默认联网检索", isOn: $store.settings.webSearch)
                    .font(.footnote)

                Toggle("允许模型调用设备工具", isOn: $store.settings.enableTools)
                    .font(.footnote)

                Toggle("高危工具二次确认", isOn: $store.settings.confirmTools)
                    .font(.footnote)

                Stepper(value: $store.settings.contextLimit, in: 2...60) {
                    HStack {
                        Text("上下文条数")
                            .font(.footnote)
                        Spacer(minLength: 0)
                        Text("\(store.settings.contextLimit)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $store.settings.toolOutputLimit, in: 2_000...64_000, step: 2_000) {
                    HStack {
                        Text("工具输出上限")
                            .font(.footnote)
                        Spacer(minLength: 0)
                        Text("\(store.settings.toolOutputLimit) 字符")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("默认思考档位")
                        .font(.footnote)
                    Spacer(minLength: 0)
                    Picker("", selection: $store.settings.thinkingLevel) {
                        ForEach(ThinkingLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                HStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 10))
                    Text("能力中心已开放 \(permissions.enabledKinds.count) 项，去「能力」页调整")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 终端

    private var terminalCard: some View {
        SectionGlassCard(title: "终端", icon: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("远程执行器地址，例如 http://192.168.1.5:8765", text: $store.settings.terminalHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(11)
                    .background(Color.secondary.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                SecureField("访问令牌（可选，放在 X-Token 头）", text: $store.settings.terminalToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 12, design: .monospaced))
                    .padding(11)
                    .background(Color.secondary.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(store.settings.terminalConfigured
                     ? "已配置远程执行器，本机 BusyBox 不可用时会转发到这台主机。"
                     : "本机内置 BusyBox 可用时直接在本机执行；留空远程地址且未内置时为沙盒模拟终端。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Image(systemName: LocalShell.isAvailable ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(LocalShell.isAvailable ? Color.green : Color.orange)

                    Text(LocalShell.isAvailable
                         ? "本机终端：\(LocalShell.version)（TrollStore + no-sandbox 安装后可读全盘）"
                         : "本机终端：未内置 BusyBox（把 busybox 放进 App 包或 Documents/bin 即可启用）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showTerminalHelp.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                        Text("怎么在电脑上开真终端")
                        Spacer(minLength: 0)
                        Image(systemName: showTerminalHelp ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)

                if showTerminalHelp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在电脑上保存成 runner.py，装好 Python 后运行 python3 runner.py，然后把手机和电脑连同一个 Wi-Fi，地址填 http://电脑IP:8765。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(Self.runnerSnippet)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            UIPasteboard.general.string = Self.runnerSnippet
                        } label: {
                            Label("复制脚本", systemImage: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - 数据

    private var dataCard: some View {
        SectionGlassCard(title: "数据", icon: "externaldrive") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("对话数量")
                        .font(.footnote)
                    Spacer(minLength: 0)
                    Text("\(store.conversations.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空所有对话", systemImage: "trash")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        SectionGlassCard(title: "关于", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI 对话 2.1")
                    .font(.footnote.weight(.medium))

                Text("纯 SwiftUI，自带设备能力与工具调用；能做什么取决于你接入的模型，以及「能力」页里授权了多少项。未越狱设备无法获取系统 root 或其他 App 的数据。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 逻辑

    private func test() {
        guard !isTesting else { return }
        isTesting = true
        testResult = nil

        Task {
            let result = await store.testConnection()
            testResult = result
            isTesting = false
        }
    }

    private func refreshModels() async {
        guard !isTesting else { return }
        isTesting = true
        testResult = nil

        let result = await store.testConnection()
        testResult = result
        isTesting = false
    }

    private static let runnerSnippet = """
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import json, subprocess

    TOKEN = ""  # 填了就要求 X-Token 一致

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            if TOKEN and self.headers.get("X-Token") != TOKEN:
                self.send_response(401); self.end_headers(); return
            n = int(self.headers.get("Content-Length", 0))
            cmd = json.loads(self.rfile.read(n) or b"{}").get("cmd", "")
            p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            body = (p.stdout + p.stderr).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)

    HTTPServer(("0.0.0.0", 8765), H).serve_forever()
    """
}