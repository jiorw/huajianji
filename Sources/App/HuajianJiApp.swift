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
        cache.countLimit = 36
        cache.totalCostLimit = 110 * 1024 * 1024
        return cache
    }()

    private static func cost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }

    private static func key(_ id: String, _ size: CGSize, _ mode: ContentMode) -> NSString {
        "\(id)|\(Int(size.width))x\(Int(size.height))|\(mode == .fill ? "f" : "i")" as NSString
    }

    static func get(_ id: String, _ size: CGSize, _ mode: ContentMode) -> UIImage? {
        cache.object(forKey: key(id, size, mode))
    }

    static func set(_ image: UIImage, _ id: String, _ size: CGSize, _ mode: ContentMode) {
        cache.setObject(image, forKey: key(id, size, mode), cost: cost(image))
    }

    /// 提前把后面几张拉进缓存，翻到时才不会闪空白
    static func prefetch(_ assets: [PHAsset], size: CGSize,
                         mode: ContentMode = .fill, scale: CGFloat = 3) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let pixel = CGSize(width: size.width * scale, height: size.height * scale)
        for asset in assets {
            let id = asset.localIdentifier
            if get(id, size, mode) != nil { continue }
            PHImageManager.default().requestImage(
                for: asset, targetSize: pixel,
                contentMode: mode == .fill ? .aspectFill : .aspectFit, options: options
            ) { result, info in
                guard (info?[PHImageCancelledKey] as? Bool) != true, let result else { return }
                set(result, id, size, mode)
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
    @State private var slot = LoadSlot()

    /// PhotoKit 先回一张糊的再回清晰的，回调还可能迟到。用引用类型记住「现在到底要
    /// 哪张」：糊图只占位一次，清晰图到手后不会再被旧请求的糊图盖回去
    private final class LoadSlot {
        var wanted = ""
        var sharp = false
    }

    var body: some View {
        // 缓存命中就当帧出图：新开的视图 state 还是空的，等 onAppear 会闪一帧空白
        let shown = image ?? MediaCache.get(asset.localIdentifier, targetSize, contentMode)
        return ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: contentMode)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.28))
            }
        }
        .animation(.easeOut(duration: 0.22), value: shownID)
        .onAppear(perform: sync)
        .onDisappear(perform: drop)
        .onChange(of: asset.localIdentifier) { _, _ in sync() }
    }

    private func sync() {
        let id = asset.localIdentifier
        guard slot.wanted != id else { return }
        slot.wanted = id
        slot.sharp = false
        if let cached = MediaCache.get(id, targetSize, contentMode) {
            slot.sharp = true
            image = cached
            shownID = id
        } else {
            // 换资源时宁可先转圈，也绝不把上一张留在屏幕上，否则看起来像在重复翻同几张
            image = nil
            shownID = nil
            request(id)
        }
    }

    private func request(_ id: String) {
        cancel()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: max(targetSize.width, 120) * 3,
                          height: max(targetSize.height, 120) * 3)
        let slot = self.slot
        let target = targetSize
        let mode = contentMode
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: mode == .fill ? .aspectFill : .aspectFit,
            options: options
        ) { result, info in
            guard (info?[PHImageCancelledKey] as? Bool) != true, let result else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            DispatchQueue.main.async {
                guard slot.wanted == id else { return }
                if degraded {
                    guard !slot.sharp, self.shownID != id else { return }
                    self.image = result
                    self.shownID = id
                } else {
                    slot.sharp = true
                    self.image = result
                    self.shownID = id
                    MediaCache.set(result, id, target, mode)
                }
            }
        }
    }

    /// 卡片滑走时取消请求并让 sync 可以重跑（多数情况直接命中缓存）
    private func drop() {
        cancel()
        slot.wanted = ""
        slot.sharp = false
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
