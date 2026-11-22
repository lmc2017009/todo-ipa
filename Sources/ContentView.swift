import SwiftUI

enum AppTab: Hashable {
    case home
    case plugins
    case settings
}

@MainActor
struct ContentView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            ConversationListView(selectedTab: $selection)
                .tabItem { Label("主页", systemImage: "bubble.left.and.bubble.right.fill") }
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

// MARK: - 液态玻璃标签栏（iOS 26）

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
    func liquidGlassTabBar() -> some View {
        modifier(LiquidGlassTabBar())
    }
}