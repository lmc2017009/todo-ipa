import SwiftUI

// MARK: - 根视图

/// 三个页面：主页 / 插件 / 设置
///
/// 标签栏不画任何背景，完全交给系统：
/// 用 iOS 26 SDK 编译后，TabView 底部的标签栏会自动变成
/// 苹果的「液态玻璃」浮动胶囊（折射、高光、随滚动收起）。
struct ContentView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("主页", systemImage: "house.fill") }
                .tag(AppTab.home)

            PluginsView()
                .tabItem { Label("插件", systemImage: "puzzlepiece.extension.fill") }
                .tag(AppTab.plugins)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .liquidGlassTabBar()
    }
}

/// 标签页枚举
enum AppTab: Hashable {
    case home
    case plugins
    case settings
}

// MARK: - 液态玻璃标签栏

private struct LiquidGlassTabBar: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// iOS 26 起启用液态玻璃标签栏；旧系统原样返回
    func liquidGlassTabBar() -> some View {
        modifier(LiquidGlassTabBar())
    }
}

// MARK: - 主页

struct HomeView: View {
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
            .navigationTitle("主页")
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

    // MARK: 子视图

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

    // MARK: 动作

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