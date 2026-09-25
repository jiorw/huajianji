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

// MARK: - 网红调色 + iOS 照片效果同款

/// 滤镜条最前排的一组：黑金 / 徕卡经典 / 赛博朋克，加上 iOS 相册自带的
/// 「鲜明 / 反差」家族。全部用 Core Image 原语现搭，不依赖第三方 LUT
enum PhotoStyle: String, CaseIterable, Identifiable {
    case blackGold
    case leicaClassic
    case cyberpunk
    case vivid
    case vividWarm
    case vividCool
    case dramatic
    case dramaticWarm
    case dramaticCool
    case warmTone
    case coolTone
    case sunset
    case hongKong
    case filmGreen
    case cream
    case insCold
    case dusk

    /// iOS 相册自带的那套（放最前）
    static let iosFamily: [PhotoStyle] = [.vivid, .vividWarm, .vividCool,
                                          .dramatic, .dramaticWarm, .dramaticCool]
    /// 我自己推的调色（垫在 iOS 家族后面）
    static let customFamily: [PhotoStyle] = [.blackGold, .leicaClassic, .cyberpunk,
                                             .warmTone, .coolTone, .sunset, .hongKong,
                                             .filmGreen, .cream, .insCold, .dusk]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blackGold: "黑金"
        case .leicaClassic: "徕卡经典"
        case .cyberpunk: "赛博朋克"
        case .vivid: "鲜明"
        case .vividWarm: "鲜暖色"
        case .vividCool: "鲜冷色"
        case .dramatic: "反差色"
        case .dramaticWarm: "反差暖色"
        case .dramaticCool: "反差冷色"
        case .warmTone: "暖色调"
        case .coolTone: "冷色调"
        case .sunset: "日落金"
        case .hongKong: "港风"
        case .filmGreen: "胶片绿"
        case .cream: "奶油感"
        case .insCold: "冷白"
        case .dusk: "蓝调"
        }
    }

    func filtered(_ input: CIImage) -> CIImage {
        switch self {
        case .blackGold:
            // 灰度当遮罩：暗部压到纯黑，亮部镀金，中间调落在金色坡道上
            let gray = controls(input, contrast: 1.32, saturation: 0, brightness: -0.03)
            let gold = flat(CIColor(red: 1.0, green: 0.80, blue: 0.45), extent: input.extent)
            let black = flat(CIColor(red: 0.03, green: 0.02, blue: 0.01), extent: input.extent)
            return controls(blend(light: gold, dark: black, mask: gray),
                            contrast: 1.10, saturation: 1.05, brightness: 0)
        case .leicaClassic:
            // 德味：红中间调浓郁偏暖、蓝被压一点、黑位微抬
            return matrix(input,
                          r: (1.10, 0.04, 0.00, 0.010),
                          g: (0.01, 1.04, 0.00, 0.004),
                          b: (0.00, 0.02, 0.92, 0.006),
                          contrast: 1.20, saturation: 1.22)
        case .cyberpunk:
            // 分离色调：亮部染洋红、暗部染青，再把饱和度顶上去
            let soft = controls(input, contrast: 0.55, saturation: 0, brightness: 0.02)
            let magenta = flat(CIColor(red: 0.98, green: 0.25, blue: 0.85), extent: input.extent)
            let cyan = flat(CIColor(red: 0.10, green: 0.85, blue: 0.95), extent: input.extent)
            let highlights = blend(light: magenta, dark: input, mask: scaled(soft, 0.42))
            let shadows = blend(light: cyan, dark: highlights, mask: scaled(invert(soft), 0.42))
            return controls(shadows, contrast: 1.15, saturation: 1.50, brightness: 0)
        case .vivid:
            // 自然饱和度（CIVibrance）比硬拉 saturation 更接近苹果「鲜明」的观感
            return vibrance(controls(input, contrast: 1.06, saturation: 1.0, brightness: 0.01), amount: 0.6)
        case .vividWarm:
            return temperature(vibrance(controls(input, contrast: 1.06, saturation: 1.0, brightness: 0.01), amount: 0.55),
                               kelvin: 1000, tint: 6)
        case .vividCool:
            return temperature(vibrance(controls(input, contrast: 1.06, saturation: 1.0, brightness: 0.01), amount: 0.55),
                               kelvin: -1000, tint: -6)
        case .dramatic:
            return controls(input, contrast: 1.42, saturation: 0.88, brightness: -0.025)
        case .dramaticWarm:
            return temperature(controls(input, contrast: 1.42, saturation: 0.90, brightness: -0.025),
                               kelvin: 900, tint: 5)
        case .dramaticCool:
            return temperature(controls(input, contrast: 1.42, saturation: 0.90, brightness: -0.025),
                               kelvin: -900, tint: -5)
        case .warmTone:
            return temperature(controls(input, contrast: 1.05, saturation: 1.12, brightness: 0.012),
                               kelvin: 1200, tint: 8)
        case .coolTone:
            return temperature(controls(input, contrast: 1.06, saturation: 1.10, brightness: 0.008),
                               kelvin: -1200, tint: -8)
        case .sunset:
            // 黄昏金：橙红提亮、蓝被收走，适合逆光和天色
            return temperature(matrix(input,
                                      r: (1.16, 0.02, 0.00, 0.015),
                                      g: (0.00, 1.02, 0.00, 0.005),
                                      b: (0.00, 0.00, 0.78, 0.010),
                                      contrast: 1.08, saturation: 1.15),
                               kelvin: 500, tint: 4)
        case .hongKong:
            // 港风：掉色的绿黄调、黑位抬起，旧海报的味道
            return matrix(input,
                          r: (0.94, 0.06, 0.00, 0.020),
                          g: (0.00, 1.02, 0.00, 0.015),
                          b: (0.00, 0.04, 0.82, 0.020),
                          contrast: 0.94, saturation: 0.78)
        case .filmGreen:
            // 富士胶片感：绿味暗部、中等对比、微降饱和
            return matrix(input,
                          r: (0.98, 0.00, 0.02, 0.008),
                          g: (0.02, 1.06, 0.02, 0.008),
                          b: (0.00, 0.03, 0.94, 0.012),
                          contrast: 1.06, saturation: 0.92)
        case .cream:
            // 奶油感：整体提亮、低反差、一点点粉调
            return matrix(input,
                          r: (1.06, 0.02, 0.00, 0.035),
                          g: (0.00, 1.00, 0.00, 0.030),
                          b: (0.02, 0.00, 0.98, 0.032),
                          contrast: 0.88, saturation: 0.82)
        case .insCold:
            // 冷白：干净提亮、去饱和、微冷，ins 风
            return temperature(controls(input, contrast: 1.04, saturation: 0.78, brightness: 0.045),
                               kelvin: -900, tint: -5)
        case .dusk:
            // 蓝调时刻：暗部沉进蓝里，亮部的灯光还留着暖
            let soft = controls(input, contrast: 0.55, saturation: 0, brightness: 0)
            let blue = flat(CIColor(red: 0.12, green: 0.28, blue: 0.55), extent: input.extent)
            let shadowed = blend(light: input, dark: blue, mask: scaled(soft, 0.55))
            return temperature(controls(shadowed, contrast: 1.18, saturation: 1.12, brightness: 0),
                               kelvin: -600, tint: -4)
        }
    }

    // MARK: 搭配用的小工具

    private func flat(_ color: CIColor, extent: CGRect) -> CIImage {
        CIImage(color: color).cropped(to: extent)
    }

    /// CIBlendWithMask：mask 越亮取 light，越暗取 dark
    private func blend(light: CIImage, dark: CIImage, mask: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return dark }
        filter.setValue(light, forKey: "inputImage")
        filter.setValue(dark, forKey: "inputBackgroundImage")
        filter.setValue(mask, forKey: "inputMaskImage")
        return filter.outputImage ?? dark
    }

    /// 把遮罩明度整体压到 amount，控制染色浓度
    private func scaled(_ image: CIImage, _ amount: CGFloat) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: "inputImage")
        filter.setValue(CIVector(x: amount, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: amount, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: amount, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        return filter.outputImage ?? image
    }

    private func invert(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorInvert") else { return image }
        filter.setValue(image, forKey: "inputImage")
        return filter.outputImage ?? image
    }

    /// 色温偏移：kelvin 正=偏暖，负=偏冷
    private func temperature(_ input: CIImage, kelvin: Double, tint: Double = 0) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else { return input }
        filter.setValue(input, forKey: "inputImage")
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: 6500 + kelvin, y: tint), forKey: "inputTargetNeutral")
        return filter.outputImage ?? input
    }

    private func matrix(_ input: CIImage,
                        r: (CGFloat, CGFloat, CGFloat, CGFloat),
                        g: (CGFloat, CGFloat, CGFloat, CGFloat),
                        b: (CGFloat, CGFloat, CGFloat, CGFloat),
                        contrast: Double, saturation: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return input }
        filter.setValue(input, forKey: "inputImage")
        filter.setValue(CIVector(x: r.0, y: r.1, z: r.2, w: r.3), forKey: "inputRVector")
        filter.setValue(CIVector(x: g.0, y: g.1, z: g.2, w: g.3), forKey: "inputGVector")
        filter.setValue(CIVector(x: b.0, y: b.1, z: b.2, w: b.3), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        guard let tinted = filter.outputImage else { return input }
        return controls(tinted, contrast: contrast, saturation: saturation, brightness: 0)
    }

    /// 自然饱和度：只提不够鲜艳的颜色，已经饱和的不动
    private func vibrance(_ input: CIImage, amount: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIVibrance") else { return input }
        filter.setValue(input, forKey: "inputImage")
        filter.setValue(amount, forKey: "inputAmount")
        return filter.outputImage ?? input
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
    case style(PhotoStyle)
    case builtin(SystemFilter)
    case grade(ColorGrade)
    case lut(CubeLUT)

    var id: String {
        switch self {
        case .original: "original"
        case .style(let s): "style-\(s.rawValue)"
        case .builtin(let f): "builtin-\(f.rawValue)"
        case .grade(let g): "grade-\(g.rawValue)"
        case .lut(let l): "lut-\(l.name)"
        }
    }

    var title: String {
        switch self {
        case .original: "原图"
        case .style(let s): s.title
        case .builtin(let f): f.title
        case .grade(let g): g.title
        case .lut(let l): l.name
        }
    }

    var isOriginal: Bool {
        if case .original = self { return true }
        return false
    }

    /// 滤镜条顺序：iOS 自带的鲜明/反差家族 + 系统效果打头，自创调色和 LUT 垫后
    static func all(luts: [CubeLUT]) -> [EditorChoice] {
        [.original]
            + PhotoStyle.iosFamily.map { EditorChoice.style($0) }
            + SystemFilter.allCases.map { EditorChoice.builtin($0) }
            + PhotoStyle.customFamily.map { EditorChoice.style($0) }
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
        case .style(let style):
            effect = style.filtered(input)
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
