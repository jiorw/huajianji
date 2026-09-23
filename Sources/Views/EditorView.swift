import SwiftUI
import Photos
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// 系统内置的照片效果滤镜（Core Image 的 CIPhotoEffect 系列，
/// 也就是照片 App 滤镜面板用的同一套引擎——苹果不允许第三方直接唤起那个面板）
enum SystemFilter: String, CaseIterable, Identifiable {
    case original
    case instant
    case process
    case transfer
    case chrome
    case fade
    case tonal
    case mono
    case noir
    case silvertone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原图"
        case .instant: "瞬间"
        case .process: "处理"
        case .transfer: "转移"
        case .chrome: "铬黄"
        case .fade: "褪色"
        case .tonal: "色调"
        case .mono: "单色"
        case .noir: "黑色"
        case .silvertone: "银色"
        }
    }

    private var ciName: String? {
        switch self {
        case .original: nil
        case .instant: "CIPhotoEffectInstant"
        case .process: "CIPhotoEffectProcess"
        case .transfer: "CIPhotoEffectTransfer"
        case .chrome: "CIPhotoEffectChrome"
        case .fade: "CIPhotoEffectFade"
        case .tonal: "CIPhotoEffectTonal"
        case .mono: "CIPhotoEffectMono"
        case .noir: "CIPhotoEffectNoir"
        case .silvertone: "CIPhotoEffectSilvertone"
        }
    }

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    func apply(to image: UIImage, maxEdge: CGFloat = 2400) -> UIImage {
        guard let name = ciName,
              let cg = image.cgImage,
              let filter = CIFilter(name: name) else { return image }

        var input = CIImage(cgImage: cg)
        let longest = max(input.extent.width, input.extent.height)
        if longest > maxEdge {
            input = input.transformed(by: CGAffineTransform(scaleX: maxEdge / longest, y: maxEdge / longest))
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        guard let output = filter.outputImage,
              let rendered = Self.context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }
}

struct EditorView: View {
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var source: UIImage?
    @State private var filter: SystemFilter = .original
    @State private var isWorking = false
    @State private var notice: String?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 14) {
            if let source {
                filteredPreview(source)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1))

                filterStrip

                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItems) {
                        Label("换一张", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.glass)

                    Button {
                        save(source)
                    } label: {
                        Label("存为新照片", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isWorking || filter == .original)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 46))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("挑一张照片，套系统的照片效果")
                        .font(.title3.weight(.semibold))
                    Text("这十个效果就是照片 App 滤镜面板用的同一套引擎。苹果不允许第三方直接打开那个面板，所以滤镜在这里自己挑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    PhotosPicker(selection: $pickerItems) {
                        Label("选择照片", systemImage: "photo.badge.plus")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.glassProminent)
                }
                Spacer()
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .onChange(of: pickerItems) { _, items in
            guard let item = items.last else { return }
            load(item)
        }
        .alert("没存进去", isPresented: $failed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("相册写入被拒了。检查一下是不是只给了「有限访问」权限。")
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private func filteredPreview(_ image: UIImage) -> some View {
        if filter == .original {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            // 预览也走一遍滤镜，切效果时所见即所得
            Image(uiImage: previewCache(image))
                .resizable()
                .scaledToFit()
                .id(filter)
                .transition(.opacity)
        }
    }

    private func previewCache(_ image: UIImage) -> UIImage {
        // 预览用缩小尺寸，切滤镜才不卡
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > 1400, let cg = image.cgImage else { return image.apply(filter: filter) }
        let factor = 1400 / longest
        let resized = UIImage(
            cgImage: cg,
            scale: image.scale / factor,
            orientation: image.imageOrientation
        )
        return resized.apply(filter: filter)
    }

    private func load(_ item: PhotosPickerItem) {
        isWorking = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    source = image
                    filter = .original
                    isWorking = false
                    notice = nil
                }
            } else {
                await MainActor.run {
                    isWorking = false
                    notice = "这个不是能处理的图片，换一张"
                }
            }
        }
    }

    // MARK: - 滤镜条

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SystemFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        VStack(spacing: 5) {
                            Text(item.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(filter == item ? Color.blue.opacity(0.55) : Color.black.opacity(0.35),
                                             in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 保存

    private func save(_ image: UIImage) {
        isWorking = true
        let result = filter.apply(to: image)
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: result)
                    request.creationDate = Date()
                }
                await MainActor.run {
                    isWorking = false
                    notice = "已把「\(filter.title)」版本存进相册"
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    failed = true
                }
            }
        }
    }
}

private extension UIImage {
    func apply(filter: SystemFilter) -> UIImage {
        filter.apply(to: self, maxEdge: 1400)
    }
}
