import SwiftUI
import Photos
import CoreLocation
import ImageIO

/// 照片 / 视频详细信息：时间、分类、尺寸、文件、位置、EXIF
struct PhotoInfoSheet: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    @State private var exif: [(String, String)] = []
    @State private var place: String = "读取中…"
    @State private var fileLines: [(String, String)] = []

    var body: some View {
        NavigationStack {
            List {
                Section("时间") {
                    LabeledContent("拍摄", value: TimeText.precise(asset.creationDate))
                    LabeledContent("距今", value: TimeText.since(asset.creationDate))
                    if let modified = asset.modificationDate {
                        LabeledContent("最后修改", value: TimeText.precise(modified))
                    }
                }

                Section("内容") {
                    LabeledContent("分类", value: category)
                    LabeledContent("像素", value: "\(asset.pixelWidth) × \(asset.pixelHeight)")
                    if asset.mediaType == .video {
                        LabeledContent("时长", value: Self.duration(asset.duration))
                    }
                }

                if !fileLines.isEmpty {
                    Section("文件") {
                        ForEach(fileLines, id: \.0) { key, value in
                            LabeledContent(key, value: value)
                        }
                    }
                }

                Section("位置") {
                    if let location = asset.location {
                        LabeledContent("坐标", value: String(
                            format: "%.5f, %.5f",
                            location.coordinate.latitude,
                            location.coordinate.longitude))
                        LabeledContent("地点", value: place)
                    } else {
                        Text("这张没有记录位置信息")
                            .foregroundStyle(.secondary)
                    }
                }

                if !exif.isEmpty {
                    Section("相机参数") {
                        ForEach(exif, id: \.0) { key, value in
                            LabeledContent(key, value: value)
                        }
                    }
                }
            }
            .navigationTitle("详细信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            fileLines = Self.fileInfo(of: asset)
            exif = await Self.readExif(of: asset)
            place = await Self.reverseGeocode(asset.location)
        }
    }

    private var category: String {
        if asset.mediaType == .video {
            return asset.mediaSubtypes.contains(.videoScreenRecording) ? "录屏" : "视频"
        }
        if asset.mediaSubtypes.contains(.photoScreenshot) { return "截屏" }
        if asset.mediaSubtypes.contains(.photoLive) { return "实况照片" }
        if asset.playbackStyle == .imageAnimated { return "动图" }
        return "照片"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60, s = total % 60
        if m >= 60 { return "\(m / 60) 小时 \(m % 60) 分" }
        return s < 10 ? "\(m):0\(s)" : "\(m):\(s)"
    }

    private static func fileInfo(of asset: PHAsset) -> [(String, String)] {
        guard let resource = PHAssetResource.assetResources(for: asset).first else { return [] }
        var lines: [(String, String)] = []
        let name = resource.originalFilename
        if !name.isEmpty { lines.append(("文件名", name)) }
        lines.append(("格式", resource.uniformTypeIdentifier.uppercased()))
        if let bytes = resource.value(forKey: "fileSize") as? NSNumber {
            lines.append(("大小", ByteCountFormatter.string(fromByteCount: bytes.int64Value, countStyle: .file)))
        }
        return lines
    }

    private static func readExif(of asset: PHAsset) async -> [(String, String)] {
        let options = PHImageRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let info: [String: Any]? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 400, height: 400),
                contentMode: .aspectFit,
                options: options
            ) { _, resultInfo in
                // Photos 没把这个键导出到 Swift，用字面量取，取不到就跳过相机参数
                continuation.resume(returning: resultInfo?["PHImageInfoKey"] as? [String: Any])
            }
        }
        guard let info else { return [] }
        let tiff = info[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = info[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]

        var lines: [(String, String)] = []
        if let make = tiff[kCGImagePropertyTIFFMake as String] as? String,
           let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
            lines.append(("设备", "\(make) \(model)"))
        } else if let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
            lines.append(("设备", model))
        }
        if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
           let first = iso.first {
            lines.append(("ISO", "\(first)"))
        }
        if let f = exif[kCGImagePropertyExifFNumber as String] as? Double {
            lines.append(("光圈", String(format: "f/%.1f", f)))
        }
        if let focal = exif[kCGImagePropertyExifFocalLength as String] as? Double {
            lines.append(("焦距", String(format: "%.0f mm", focal)))
        }
        if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double, exposure > 0 {
            lines.append(("快门", String(format: "1/%.0f s", 1 / exposure)))
        }
        return lines
    }

    private static func reverseGeocode(_ location: CLLocation?) async -> String {
        guard let location else { return "无位置信息" }
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let mark = marks.first else { return "查不到地名" }
            let parts = [mark.administrativeArea, mark.locality, mark.name]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? "查不到地名" : parts.joined(separator: " · ")
        } catch {
            return "需要联网才能查地名"
        }
    }
}
