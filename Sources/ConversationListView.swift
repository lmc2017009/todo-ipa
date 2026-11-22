import SwiftUI

@MainActor
struct ConversationListView: View {
    @EnvironmentObject private var store: ChatStore
    @Binding var selectedTab: AppTab

    @State private var path: [UUID] = []
    @State private var renaming: Conversation?
    @State private var renameText: String = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !store.hasAPI {
                    setupRow
                }

                if store.conversations.isEmpty {
                    emptyRow
                }

                ForEach(store.conversations) { conversation in
                    NavigationLink(value: conversation.id) {
                        row(conversation)
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deleteConversation(id: conversation.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            renaming = conversation
                            renameText = conversation.title
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            store.deleteConversation(id: conversation.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .liquidBackdrop()
            .navigationTitle("聊天")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ChatView(conversationID: id)
            }
            .alert("重命名对话", isPresented: renamingBinding) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if let target = renaming {
                        store.rename(id: target.id, title: renameText)
                    }
                    renaming = nil
                }
            }
        }
    }

    // MARK: - 子视图

    private var setupRow: some View {
        Button {
            selectedTab = .settings
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("还没有配置接口")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("填写 API 地址与密钥后即可对话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var emptyRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            Text("开始一个新对话")
                .font(.headline)
            Text("点右上角新建，或在设置里先配好接口")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }

    private func row(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(preview(conversation))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.relative(conversation.updatedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 逻辑

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil },
                set: { if !$0 { renaming = nil } })
    }

    private func preview(_ conversation: Conversation) -> String {
        guard let last = conversation.messages.last else { return "还没有消息" }
        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return last.attachments.isEmpty ? "还没有消息" : "附件"
        }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    private func newChat() {
        let id = store.newConversation()
        path.append(id)
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}