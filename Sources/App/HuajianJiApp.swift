import SwiftUI
import Photos
import AVFoundation
import AVKit

@main
struct HuajianJiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - 图片缓存

enum MediaCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        return cache
    }()

    private static func key(_ id: String, _ size: CGSize, _ mode: ContentMode) -> NSString {
        "\(id)|\(Int(size.width))x\(Int(size.height))|\(mode == .fill ? "f" : "i")" as NSString
    }

    static func get(_ id: String, _ size: CGSize, _ mode: ContentMode) -> UIImage? {
        cache.object(forKey: key(id, size, mode))
    }

    static func set(_ image: UIImage, _ id: String, _ size: CGSize, _ mode: ContentMode) {
        cache.setObject(image, forKey: key(id, size, mode))
    }

    /// 提前把后面几张拉进缓存，翻到时才不会转圈
    static func prefetch(_ assets: [PHAsset], size: CGSize) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let pixel = CGSize(width: size.width * 3, height: size.height * 3)
        for asset in assets {
            let id = asset.localIdentifier
            if get(id, size, .fill) != nil { continue }
            PHImageManager.default().requestImage(
                for: asset, targetSize: pixel, contentMode: .aspectFill, options: options
            ) { result, info in
                guard (info?[PHImageCancelledKey] as? Bool) != true, let result else { return }
                set(result, id, size, .fill)
            }
        }
    }
}

// MARK: - 图片加载

struct MediaImageView: View {
    let asset: PHAsset
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var shownID: String?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            // 新图到达前继续显示旧图，避免每次换卡都闪一下转圈
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
        .animation(.easeOut(duration: 0.22), value: shownID)
        .onAppear(perform: sync)
        .onDisappear(perform: cancel)
        .onChange(of: asset.localIdentifier) { _, _ in sync() }
    }

    private func sync() {
        let id = asset.localIdentifier
        guard shownID != id else { return }
        if let cached = MediaCache.get(id, targetSize, contentMode) {
            shownID = id
            image = cached
        } else {
            request()
        }
    }

    private func request() {
        cancel()
        let id = asset.localIdentifier
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
                if self.shownID != id, self.image == nil || !degraded {
                    self.image = result
                    self.shownID = id
                    if !degraded { MediaCache.set(result, id, self.targetSize, self.contentMode) }
                }
            }
        }
    }

    private func cancel() {
        guard let requestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        self.requestID = nil
    }
}

// MARK: - 背景：小图 + 轻模糊，玻璃效果才有东西可折射

struct BackdropView: View {
    let asset: PHAsset?

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.10)
            if let asset {
                MediaImageView(asset: asset, targetSize: CGSize(width: 150, height: 260))
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 22, opaque: false)
                    .scaleEffect(1.35)
            }
        }
    }
}

// MARK: - 视频预览

struct VideoPreview: UIViewControllerRepresentable {
    let asset: PHAsset

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        // PHAsset 不是 AVAsset，要先异步导出可播放的资源
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let avAsset else { return }
            DispatchQueue.main.async {
                controller.player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                controller.player?.play()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
