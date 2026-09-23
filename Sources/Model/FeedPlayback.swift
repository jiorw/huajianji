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

    private var requestID: PHImageRequestID?

    func load(_ asset: PHAsset) {
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        isLoading = true
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                guard let avAsset else { return }
                self.player.replaceCurrentItem(with: AVPlayerItem(asset: avAsset))
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
