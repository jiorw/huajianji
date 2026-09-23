import SwiftUI
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

/// 取一张图的平均色。放在非隔离的 enum 里，PhotoKit 回调线程可以直接调
enum PaletteMath {
    static let context = CIContext(options: nil)

    static func averageColor(of cg: CGImage) -> (red: Double, green: Double, blue: Double) {
        let input = CIImage(cgImage: cg)
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = CIVector(cgRect: input.extent)
        guard let output = filter.outputImage else { return (0.12, 0.12, 0.12) }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(output,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(bitmap[0]) / 255, Double(bitmap[1]) / 255, Double(bitmap[2]) / 255)
    }
}

/// 背景基调跟着当前照片走（对应原版的 BackdropPalette）
@MainActor
final class BackdropPalette: ObservableObject {
    @Published var color: Color = Color(red: 0.10, green: 0.11, blue: 0.11)

    private var requestID: PHImageRequestID?

    func update(from asset: PHAsset?) {
        guard let asset else { return }
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 32, height: 32),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let cg = image?.cgImage else { return }
            let rgb = PaletteMath.averageColor(of: cg)
            Task { @MainActor in self.apply(rgb) }
        }
    }

    /// 压暗，保证白字和玻璃材质都读得清
    private func apply(_ rgb: (red: Double, green: Double, blue: Double)) {
        let dim = 0.45
        color = Color(red: rgb.red * dim, green: rgb.green * dim, blue: rgb.blue * dim)
    }
}
