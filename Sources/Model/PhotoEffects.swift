import UIKit
import CoreImage

// MARK: - 系统内置照片效果

enum SystemFilter: String, CaseIterable, Identifiable {
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

    private var ciName: String {
        switch self {
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

    func filtered(_ input: CIImage) -> CIImage {
        guard let filter = CIFilter(name: ciName) else { return input }
        filter.setValue(input, forKey: "inputImage")
        return filter.outputImage ?? input
    }
}

// MARK: - 我自己推的调色

/// 用 Core Image 原语现搭的四个通用调色配方，不含任何第三方 LUT 数据
enum ColorGrade: String, CaseIterable, Identifiable {
    case tealOrange
    case fadedFilm
    case cineWarm
    case contrastMono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tealOrange: "青橙"
        case .fadedFilm: "褪色胶片"
        case .cineWarm: "暖调电影"
        case .contrastMono: "高反差黑白"
        }
    }

    func filtered(_ input: CIImage) -> CIImage {
        switch self {
        case .tealOrange:
            // 高光偏橙、暗部偏青
            return matrix(input,
                          r: (1.14, -0.06, -0.06, 0.000),
                          g: (-0.04, 1.05, 0.00, 0.010),
                          b: (-0.06, 0.02, 0.95, 0.020),
                          contrast: 1.16, saturation: 1.08, brightness: 0)
        case .fadedFilm:
            // 掉色感 = 抬黑 + 压对比 + 降饱和
            return matrix(input,
                          r: (0.86, 0, 0, 0.070),
                          g: (0, 0.87, 0, 0.062),
                          b: (0, 0, 0.89, 0.055),
                          contrast: 0.88, saturation: 0.70, brightness: 0.01)
        case .cineWarm:
            return matrix(input,
                          r: (1.12, 0, 0, 0.014),
                          g: (0, 1.02, 0, 0.006),
                          b: (0, 0, 0.86, 0.000),
                          contrast: 1.14, saturation: 0.90, brightness: 0)
        case .contrastMono:
            let gray = SystemFilter.mono.filtered(input)
            return controls(gray, contrast: 1.5, saturation: 0, brightness: -0.03)
        }
    }

    private func matrix(_ input: CIImage,
                        r: (CGFloat, CGFloat, CGFloat, CGFloat),
                        g: (CGFloat, CGFloat, CGFloat, CGFloat),
                        b: (CGFloat, CGFloat, CGFloat, CGFloat),
                        contrast: Double, saturation: Double, brightness: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return input }
        filter.setValue(input, forKey: "inputImage")
        filter.setValue(CIVector(x: r.0, y: r.1, z: r.2, w: r.3), forKey: "inputRVector")
        filter.setValue(CIVector(x: g.0, y: g.1, z: g.2, w: g.3), forKey: "inputGVector")
        filter.setValue(CIVector(x: b.0, y: b.1, z: b.2, w: b.3), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        guard let tinted = filter.outputImage else { return input }
        return controls(tinted, contrast: contrast, saturation: saturation, brightness: brightness)
    }

    private func controls(_ input: CIImage, contrast: Double, saturation: Double,
                          brightness: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return input }
        filter.setValue(input, forKey: "inputImage")
        filter.setValue(contrast, forKey: "inputContrast")
        filter.setValue(saturation, forKey: "inputSaturation")
        filter.setValue(brightness, forKey: "inputBrightness")
        return filter.outputImage ?? input
    }
}

// MARK: - .cube LUT

struct CubeLUT: Identifiable, Hashable {
    let name: String
    let dimension: Int
    let data: Data
    var fileURL: URL?

    var id: String { name }
}

enum CubeParser {
    /// 解析标准 .cube（LUT_3D_SIZE + 每行 R G B）
    static func parse(url: URL) -> CubeLUT? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var size = 0
        var title = url.deletingPathExtension().lastPathComponent
        var values: [Float] = []

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("TITLE") {
                let parts = line.split(separator: "\"")
                if parts.count >= 2 { title = String(parts[1]) }
                continue
            }
            if line.hasPrefix("LUT_3D_SIZE") || line.hasPrefix("LUT_1D_SIZE") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 2, let n = Int(parts[1]) { size = n }
                continue
            }
            if line.hasPrefix("DOMAIN_MIN") || line.hasPrefix("DOMAIN_MAX") { continue }
            let numbers = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Float($0) }
            if numbers.count == 3 { values.append(contentsOf: numbers) }
        }

        guard size >= 2, size <= 128, values.count == size * size * size * 3 else { return nil }
        var rgba: [Float] = []
        rgba.reserveCapacity(values.count / 3 * 4)
        var index = 0
        while index + 2 < values.count {
            rgba.append(contentsOf: [values[index], values[index + 1], values[index + 2], 1])
            index += 3
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return CubeLUT(name: title, dimension: size, data: data, fileURL: url)
    }
}

// MARK: - 选择项

enum EditorChoice: Identifiable, Hashable {
    case original
    case builtin(SystemFilter)
    case grade(ColorGrade)
    case lut(CubeLUT)

    var id: String {
        switch self {
        case .original: "original"
        case .builtin(let f): "builtin-\(f.rawValue)"
        case .grade(let g): "grade-\(g.rawValue)"
        case .lut(let l): "lut-\(l.name)"
        }
    }

    var title: String {
        switch self {
        case .original: "原图"
        case .builtin(let f): f.title
        case .grade(let g): g.title
        case .lut(let l): l.name
        }
    }

    var isOriginal: Bool {
        if case .original = self { return true }
        return false
    }

    static func all(luts: [CubeLUT]) -> [EditorChoice] {
        [.original]
            + SystemFilter.allCases.map { EditorChoice.builtin($0) }
            + ColorGrade.allCases.map { EditorChoice.grade($0) }
            + luts.map { EditorChoice.lut($0) }
    }
}

// MARK: - 渲染

enum PhotoEffectEngine {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// strength 0 = 原图，1 = 全效果
    static func render(_ image: UIImage, choice: EditorChoice, strength: Double,
                       maxEdge: CGFloat) -> UIImage {
        guard !choice.isOriginal, let cg = image.cgImage else { return image }

        var input = CIImage(cgImage: cg)
        let longest = max(input.extent.width, input.extent.height)
        if longest > maxEdge {
            let factor = maxEdge / longest
            input = input.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        }
        let extent = input.extent

        let effect: CIImage
        switch choice {
        case .original:
            return image
        case .builtin(let filter):
            effect = filter.filtered(input)
        case .grade(let grade):
            effect = grade.filtered(input)
        case .lut(let lut):
            guard let result = apply(lut: lut, to: input) else { return image }
            effect = result
        }

        let blended = mix(effect: effect, base: input, strength: strength).cropped(to: extent)
        guard let rendered = Self.context.createCGImage(blended, from: blended.extent) else {
            return image
        }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 用一张均匀 alpha 的遮罩把效果和原图按比例混合
    private static func mix(effect: CIImage, base: CIImage, strength: Double) -> CIImage {
        let clamped = min(max(strength, 0), 1)
        guard clamped < 0.999 else { return effect }
        guard clamped > 0.001 else { return base }

        guard let generator = CIFilter(name: "CIConstantColorGenerator") else { return effect }
        generator.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: clamped), forKey: "inputColor")
        guard let solid = generator.outputImage?.cropped(to: base.extent),
              let blend = CIFilter(name: "CIBlendWithAlphaMask") else { return effect }
        blend.setValue(effect, forKey: "inputImage")
        blend.setValue(solid, forKey: "inputMaskImage")
        blend.setValue(base, forKey: "inputBackgroundImage")
        return blend.outputImage ?? effect
    }

    private static func apply(lut: CubeLUT, to input: CIImage) -> CIImage? {
        if let filter = CIFilter(name: "CIColorCubeWithColorSpace") {
            filter.setValue(lut.dimension, forKey: "inputCubeDimension")
            filter.setValue(lut.data, forKey: "inputCubeData")
            filter.setValue(CGColorSpaceCreateDeviceRGB(), forKey: "inputColorSpace")
            filter.setValue(input, forKey: "inputImage")
            if let result = filter.outputImage { return result }
        }
        guard let fallback = CIFilter(name: "CIColorCube") else { return nil }
        fallback.setValue(lut.dimension, forKey: "inputCubeDimension")
        fallback.setValue(lut.data, forKey: "inputCubeData")
        fallback.setValue(input, forKey: "inputImage")
        return fallback.outputImage
    }
}

// MARK: - LUT 存放

@MainActor
final class LUTStore: ObservableObject {
    @Published var luts: [CubeLUT] = []

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LUTs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    init() { reload() }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        luts = files.filter { $0.pathExtension.lowercased() == "cube" }
            .compactMap { CubeParser.parse(url: $0) }
            .sorted { $0.name < $1.name }
    }

    /// 返回 nil 表示成功
    @discardableResult
    func importCube(from url: URL) -> String? {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let lut = CubeParser.parse(url: url) else {
            return "这个 .cube 读不了：格式不对，或数据条数跟 LUT_3D_SIZE 对不上"
        }
        let target = Self.folder.appendingPathComponent(safeName(lut.name) + ".cube")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            return "拷贝失败：\(error.localizedDescription)"
        }
        reload()
        return nil
    }

    func remove(_ lut: CubeLUT) {
        let url = lut.fileURL ?? Self.folder.appendingPathComponent(safeName(lut.name) + ".cube")
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private func safeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return String(cleaned.prefix(40))
    }
}
