import SwiftUI

// MARK: - 设置页

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Color.secondary.opacity(0.5))

                Text("暂无设置")
                    .font(.headline)

                Text("设置项会显示在这里")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    SettingsView()
}
