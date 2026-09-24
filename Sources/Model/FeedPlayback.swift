import SwiftUI
import Photos
import AVFoundation
import UIKit

/// feed 内嵌播放器：换页时直接替换 item，自动播放并带声音
@MainActor
final class FeedPlayback: ObservableObject {
    let player = AVPlayer()

    @Published var isMuted = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private var requestID: PHImageRequestID?
    private var timeObserver: Any?

    init() {
        // 每 0.25s 同步一次播放进度，给底部进度条用
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            if let item = self.player.currentItem, item.duration.isNumeric {
                self.duration = CMTimeGetSeconds(item.duration)
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    var isPlaying: Bool { player.rate > 0.01 }

    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func load(_ asset: PHAsset) {
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        isLoading = true
        currentTime = 0
        duration = 0
        // AirPlay 视频输出要音频会话允许外部播放
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
        player.allowsExternalPlayback = true
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                guard let avAsset else { return }
                let item = AVPlayerItem(asset: avAsset)
                self.player.replaceCurrentItem(with: item)
                if item.duration.isNumeric {
                    self.duration = CMTimeGetSeconds(item.duration)
                }
                self.player.isMuted = self.isMuted
                self.player.play()
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    func stop() {
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
            self.requestID = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

struct PlayerUIView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIViewType {
        let view = PlayerUIViewType()
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerUIViewType, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerUIViewType: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
