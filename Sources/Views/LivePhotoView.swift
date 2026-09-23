import SwiftUI
import Photos
import PhotosUI

/// 实况照片：不播放时显示静帧，长按播放
struct LivePhotoView: UIViewRepresentable {
    let asset: PHAsset
    var playing: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        context.coordinator.load(asset, into: view)
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if playing {
            uiView.startPlayback(with: .full)
        } else {
            uiView.stopPlayback()
        }
    }

    final class Coordinator {
        private var requestID: PHImageRequestID?

        func load(_ asset: PHAsset, into view: PHLivePhotoView) {
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            requestID = PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: CGSize(width: 1400, height: 1400),
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, _ in
                guard let livePhoto else { return }
                DispatchQueue.main.async { view.livePhoto = livePhoto }
            }
        }

        deinit {
            if let requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
}
