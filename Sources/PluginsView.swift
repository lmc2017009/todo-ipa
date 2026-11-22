import SwiftUI

// MARK: - 插件页

struct PluginsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Color.secondary.opacity(0.5))

                Text("暂无插件")
                    .font(.headline)

                Text("插件会显示在这里")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("插件")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    PluginsView()
}
