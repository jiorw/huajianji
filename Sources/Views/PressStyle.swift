import SwiftUI

/// 统一的按压反馈：按下去轻轻缩一下，松手弹回来。
/// 玻璃按钮自带的系统反馈各处不一致，自定义控件（底栏、工具列）都用这一个
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: configuration.isPressed)
    }
}
