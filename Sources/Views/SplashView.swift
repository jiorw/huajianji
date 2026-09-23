import SwiftUI

/// 启动页：花瓣飘落 + 文案逐层浮现，点任意处或等一会儿进入
struct SplashView: View {
    var onFinish: () -> Void

    @State private var stage = 0
    private let started = Date()

    private struct Petal {
        let x: Double
        let speed: Double
        let sway: Double
        let swayAmount: Double
        let size: Double
        let spin: Double
        let tilt: Double
        let phase: Double
        let color: Color
    }

    private static let petals: [Petal] = (0..<22).map { i in
        let palette: [Color] = [
            Color(red: 0.98, green: 0.76, blue: 0.83),
            Color(red: 0.96, green: 0.62, blue: 0.72),
            Color(red: 1.00, green: 0.90, blue: 0.72),
            Color(red: 0.86, green: 0.79, blue: 0.98),
            Color(red: 0.99, green: 0.97, blue: 0.94),
        ]
        return Petal(x: .random(in: 0.02...0.98),
                     speed: .random(in: 0.055...0.11),
                     sway: .random(in: 0.7...1.9),
                     swayAmount: .random(in: 12...46),
                     size: .random(in: 9...20),
                     spin: .random(in: 1.2...4.2) * (Bool.random() ? 1 : -1),
                     tilt: .random(in: 0...(.pi * 2)),
                     phase: .random(in: 0...1),
                     color: palette[i % palette.count])
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.07, blue: 0.085),
                         Color(red: 0.05, green: 0.05, blue: 0.06),
                         Color(red: 0.02, green: 0.02, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            glow

            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSince(started)
                    for petal in Self.petals {
                        let raw = petal.phase + t * petal.speed
                        let progress = raw - floor(raw)
                        let y = -30 + progress * (size.height + 60)
                        let x = petal.x * size.width
                            + sin(progress * .pi * 2 * petal.sway) * petal.swayAmount
                        var layer = context
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(petal.tilt + progress * petal.spin))
                        let rect = CGRect(x: -petal.size / 2, y: -petal.size / 3,
                                          width: petal.size, height: petal.size * 0.66)
                        layer.opacity = progress < 0.08 ? progress / 0.08
                            : (progress > 0.9 ? (1 - progress) / 0.1 : 1)
                        layer.fill(Path(ellipseIn: rect), with: .color(petal.color))
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                Text("繁花落下，记忆仍在册中。")
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .opacity(stage >= 1 ? 1 : 0)
                    .blur(radius: stage >= 1 ? 0 : 8)
                    .offset(y: stage >= 1 ? 0 : 12)

                Text("花间集 · 你的私人相册")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(stage >= 2 ? 1 : 0)
                    .offset(y: stage >= 2 ? 0 : 8)
            }
            .padding(.horizontal, 30)

            VStack {
                Spacer()
                Text("轻触任意处进入")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(stage >= 2 ? 0.32 : 0))
                    .padding(.bottom, 42)
            }
        }
        .animation(.easeOut(duration: 0.9), value: stage)
        .onAppear { run() }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
    }

    private var glow: some View {
        VStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.98, green: 0.72, blue: 0.80).opacity(0.22), .clear],
                    center: .center, startRadius: 2, endRadius: 240))
                .frame(width: 460, height: 460)
                .blur(radius: 30)
                .offset(y: -110)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func run() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            stage = 1
            try? await Task.sleep(for: .milliseconds(760))
            stage = 2
            try? await Task.sleep(for: .milliseconds(1500))
            finish()
        }
    }

    private func finish() {
        onFinish()
    }
}
