import SwiftUI
import Photos
import AVFoundation
import AVKit

@main
struct ZhaoHuaXiShiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - 图片加载

struct MediaImageView: View {
    let asset: PHAsset
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: contentMode)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white.opacity(0.7))
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: cancel)
        .onChange(of: asset.localIdentifier) { _, _ in
            cancel()
            image = nil
            load()
        }
    }

    private func load() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: max(targetSize.width, 120) * 3,
                          height: max(targetSize.height, 120) * 3)
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
            options: options
        ) { result, info in
            guard (info?[PHImageCancelledKey] as? Bool) != true, let result else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            DispatchQueue.main.async {
                if self.image == nil || !degraded { self.image = result }
            }
        }
    }

    private func cancel() {
        guard let requestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        self.requestID = nil
    }
}

// MARK: - 背景：把当前照片放大高斯模糊，玻璃效果才有东西可折射

struct BackdropView: View {
    let asset: PHAsset?

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.10)
            if let asset {
                MediaImageView(asset: asset, targetSize: CGSize(width: 260, height: 460))
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 46, opaque: false)
                    .scaleEffect(1.3)
                    .id(asset.localIdentifier)
            }
        }
    }
}

// MARK: - 视频预览

struct VideoPreview: UIViewControllerRepresentable {
    let asset: PHAsset

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        controller.allowsPictureInPicturePlayback = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
