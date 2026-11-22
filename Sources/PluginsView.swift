import SwiftUI

@MainActor
struct PluginsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.tertiary)

                Text("暂无插件")
                    .font(.headline)

                Text("插件能力稍后开放")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("插件")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}