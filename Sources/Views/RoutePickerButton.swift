import SwiftUI
import AVKit
import AVFoundation

/// 系统 AirPlay 路由选择按钮：点开后既能选视频投放到电视，也能开屏幕镜像
struct RoutePickerButton: UIViewRepresentable {
    var activeColor: Color = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.delegate = context.coordinator
        view.activeColor = activeColor
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
    }
}

/// 监听当前音频路由，判断是不是已经投出去了
@MainActor
final class CastMonitor: ObservableObject {
    @Published var isCasting = false

    private var token: NSObjectProtocol?

    init() {
        refresh()
        token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    func refresh() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        isCasting = outputs.contains { output in
            output.portType == .airPlay ||
            output.portType.rawValue.contains("AirPlay") ||
            output.portType == .bluetoothA2DP
        }
    }
}
