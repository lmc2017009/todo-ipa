import SwiftUI

// MARK: - 标签页

enum AppTab: Hashable {
    case chat
    case capabilities
    case settings
}

// MARK: - 液态玻璃

extension View {
    /// iOS 26 用真正的 Liquid Glass，低版本退化为毛玻璃
    func glassSurface(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// 页面级液态背景
    func liquidBackdrop() -> some View {
        background(LiquidBackdrop().ignoresSafeArea())
    }
}

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
    }
}

struct LiquidBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseGradient

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.35 : 0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -110, y: -230)

            Circle()
                .fill(Color.purple.opacity(colorScheme == .dark ? 0.30 : 0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 130, y: -60)

            Circle()
                .fill(Color.teal.opacity(colorScheme == .dark ? 0.22 : 0.16))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -60, y: 300)
        }
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.09, green: 0.08, blue: 0.16)]
                : [Color(red: 0.96, green: 0.97, blue: 1.0), Color(red: 0.91, green: 0.94, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 小组件

struct CapabilityBadge: View {
    var title: String
    var icon: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

struct SectionGlassCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22)
    }
}