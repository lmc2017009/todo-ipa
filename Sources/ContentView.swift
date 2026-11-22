import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var store: ChatStore
    @StateObject private var permissions: PermissionCenter
    @StateObject private var approvals: ApprovalCenter
    @StateObject private var engine: ChatEngine

    @State private var tab: AppTab = .chat

    init() {
        let store = ChatStore()
        let permissions = PermissionCenter()
        let approvals = ApprovalCenter()

        _store = StateObject(wrappedValue: store)
        _permissions = StateObject(wrappedValue: permissions)
        _approvals = StateObject(wrappedValue: approvals)
        _engine = StateObject(wrappedValue: ChatEngine(store: store,
                                                       permissions: permissions,
                                                       approvals: approvals))
    }

    var body: some View {
        TabView(selection: $tab) {
            ConversationListView(selectedTab: $tab)
                .tabItem {
                    Label("聊天", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(AppTab.chat)

            CapabilityCenterView()
                .tabItem {
                    Label("能力", systemImage: "square.stack.3d.up.fill")
                }
                .tag(AppTab.capabilities)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .tint(.accentColor)
        .environmentObject(store)
        .environmentObject(permissions)
        .environmentObject(approvals)
        .environmentObject(engine)
        .onAppear {
            permissions.refresh()
            SandboxBootstrap.prepare()
        }
    }
}

// 入口见 AIChatApp.swift