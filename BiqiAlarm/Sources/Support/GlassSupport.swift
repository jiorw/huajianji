import SwiftUI

// MARK: - 配色：Liquid Glass 需要背后有东西可折射，所以底色一律给高饱和渐变

enum Palette {
    static let dawn = LinearGradient(
        colors: [Color(red: 0.13, green: 0.09, blue: 0.28),
                 Color(red: 0.42, green: 0.20, blue: 0.36),
                 Color(red: 0.95, green: 0.55, blue: 0.31)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let night = LinearGradient(
        colors: [Color(red: 0.04, green: 0.05, blue: 0.13),
                 Color(red: 0.10, green: 0.16, blue: 0.33),
                 Color(red: 0.05, green: 0.28, blue: 0.36)],
        startPoint: .top, endPoint: .bottom)

    static let alert = LinearGradient(
        colors: [Color(red: 0.72, green: 0.11, blue: 0.24),
                 Color(red: 0.98, green: 0.45, blue: 0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let accent = Color(red: 1.0, green: 0.55, blue: 0.22)
    static let cool = Color(red: 0.36, green: 0.72, blue: 1.0)
}

// MARK: - 统一的弹性曲线：玻璃形变全靠它

enum GlassMotion {
    /// 按下 / 弹起：轻微回弹
    static let tap = Animation.spring(duration: 0.32, bounce: 0.34)
    /// 卡片展开、数值变化
    static let settle = Animation.spring(duration: 0.5, bounce: 0.18)
    /// 快速状态提示（红框、勾选）
    static let snappy = Animation.spring(duration: 0.24, bounce: 0.5)
}

// MARK: - 可点击的玻璃卡片：按下会压缩、玻璃变亮，松手弹回

struct GlassCardButton: ButtonStyle {
    var tint: Color? = nil
    var cornerRadius: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular.interactive().tint(tint),
                         in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(configuration.isPressed ? GlassMotion.tap : GlassMotion.settle,
                       value: configuration.isPressed)
    }
}

/// 小胶囊按钮版的按压缩放
struct GlassPillButton: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular.interactive().tint(tint), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(GlassMotion.tap, value: configuration.isPressed)
    }
}

extension View {
    /// 标准玻璃面板：放进 ScrollView / VStack 里当卡片用
    func glassPanel(tint: Color? = nil, cornerRadius: CGFloat = 26, interactive: Bool = false) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(interactive ? .regular.interactive().tint(tint) : .regular.tint(tint),
                         in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func glassChip(tint: Color? = nil) -> some View {
        self
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.tint(tint), in: Capsule())
    }

    /// 数字变化时滚动过渡（贪睡次数、倒计时、进度）
    func glassNumber() -> some View {
        self.contentTransition(.numericText())
    }
}

// MARK: - 玻璃卡片 / 玻璃条

extension View {
    /// 标准玻璃面板：放进 ScrollView / VStack 里当卡片用
    func glassPanel(tint: Color? = nil, cornerRadius: CGFloat = 26) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint),
                         in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func glassChip(tint: Color? = nil) -> some View {
        self
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.tint(tint), in: Capsule())
    }
}

/// 一组按钮/入口做成会互相融合的玻璃，必须包在容器里
struct GlassBar<Content: View>: View {
    var spacing: CGFloat? = 14
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: 12) { content }
        }
    }
}

/// 整页背景：玻璃卡片浮在这层渐变 + 光斑上
struct GlassBackdrop<Overlay: View>: View {
    var using: LinearGradient
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack {
            using
                .ignoresSafeArea()
            Canvas { context, size in
                let blobs: [(CGFloat, CGFloat, CGFloat, Color)] = [
                    (0.18, 0.16, 0.42, Palette.accent.opacity(0.55)),
                    (0.86, 0.30, 0.36, Palette.cool.opacity(0.45)),
                    (0.52, 0.92, 0.52, Color.purple.opacity(0.40))
                ]
                for blob in blobs {
                    let center = CGPoint(x: size.width * blob.0, y: size.height * blob.1)
                    let radius = size.width * blob.2
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            Gradient(colors: [blob.3, blob.3.opacity(0)]),
                            center: center, startRadius: 0, endRadius: radius))
                }
            }
            .blur(radius: 26)
            .ignoresSafeArea()
            overlay
                .ignoresSafeArea()
        }
    }
}

/// 页面里的小标题
struct SectionHeader: View {
    let title: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.94))
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(.top, 6)
    }
}
