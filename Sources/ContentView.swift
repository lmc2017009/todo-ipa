import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @State private var newTitle: String = ""
    @FocusState private var inputFocused: Bool

    private var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inputBar

                if store.items.isEmpty {
                    emptyState
                } else {
                    todoList
                }
            }
            .navigationTitle("清单")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清除已完成") {
                        store.clearDone()
                    }
                    .disabled(store.doneCount == 0)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !store.items.isEmpty {
                    footerBar
                }
            }
        }
    }

    // MARK: - 子视图

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("添加一项待办…", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .submitLabel(.done)
                .onSubmit(commit)

            Button(action: commit) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(!canAdd)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var todoList: some View {
        List {
            ForEach(store.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(item.isDone ? Color.green : Color.secondary)

                    Text(item.title)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? Color.secondary : Color.primary)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        store.toggle(item)
                    }
                }
            }
            .onDelete(perform: store.delete)
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 56))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Text("还没有待办")
                .font(.headline)
            Text("在上面输入内容，点 + 添加")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footerBar: some View {
        HStack {
            Text("共 \(store.items.count) 项 · 已完成 \(store.doneCount) 项")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: - 动作

    private func commit() {
        guard canAdd else { return }
        store.add(newTitle)
        newTitle = ""
        inputFocused = true
    }
}

#Preview {
    ContentView()
        .environmentObject(TodoStore())
}
