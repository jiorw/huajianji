import UIKit
import SwiftUI

/// 帧率监视：在设置里打开后，屏幕左上角显示实时 FPS，滑动卡不卡一眼可见
@MainActor
final class FrameMeter: NSObject, ObservableObject {
    @Published var fps: Double = 0

    private var link: CADisplayLink?
    private var frames = 0
    private var anchor = CACurrentMediaTime()

    func start() {
        guard link == nil else { return }
        frames = 0
        anchor = CACurrentMediaTime()
        let next = CADisplayLink(target: self, selector: #selector(tick(_:)))
        next.add(to: .main, forMode: .common)
        link = next
    }

    func stop() {
        link?.invalidate()
        link = nil
        fps = 0
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        frames += 1
        let now = displayLink.timestamp
        let span = now - anchor
        guard span >= 0.5 else { return }
        fps = Double(frames) / span
        frames = 0
        anchor = now
    }
}
