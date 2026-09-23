import SwiftUI
import Photos
import CoreLocation
import ImageIO
import MapKit

/// 照片详情：顶部照片条 + 相片信息 + 拍摄位置，样式照着系统相册的信息面板做
struct PhotoInfoSheet: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    @State private var meta = PhotoMeta()
    @State private var place = ""
    @State private var address = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                banner
                DashedRule().padding(.top, 18)
                photoSection
                DashedRule().padding(.top, 20)
                locationSection
                dismissButton.padding(.top, 28)
            }
            .padding(.bottom, 20)
        }
        .background(Color.black)
        .presentationBackground(.black)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task { await load() }
    }

    // MARK: - 顶部：照片本身当背景，压暗后叠时间

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            MediaImageView(asset: asset, targetSize: CGSize(width: 360, height: 230))
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipped()

            LinearGradient(colors: [Color.black.opacity(0.15), Color.black.opacity(0.72)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                Text(TimeText.since(asset.creationDate))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text(Self.weekdayTime(asset.creationDate))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    // MARK: - 相片信息

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead(symbol: "camera", title: "相片信息")

            if !meta.device.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("设备")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.62))
                    Spacer(minLength: 12)
                    Text(meta.device)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                }
            }

            let chips = meta.chips
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        MetricChip(value: chip.value, label: chip.label)
                    }
                }
            }

            VStack(spacing: 12) {
                BulletRow(label: "文件名", value: meta.fileName)
                BulletRow(label: "分辨率", value: meta.resolution)
                BulletRow(label: "文件大小", value: meta.fileSize)
                if !meta.format.isEmpty {
                    BulletRow(label: "格式", value: meta.format)
                }
                if !meta.duration.isEmpty {
                    BulletRow(label: "时长", value: meta.duration)
                }
                BulletRow(label: "类型", value: category)
            }
        }
        .padding(.horizontal, 20)
    }

    private var category: String {
        if asset.mediaType == .video {
            return asset.mediaSubtypes.contains(.videoScreenRecording) ? "屏幕录制" : "视频"
        }
        if asset.mediaSubtypes.contains(.photoScreenshot) { return "截屏" }
        if asset.mediaSubtypes.contains(.photoLive) { return "实况照片" }
        if asset.playbackStyle == .imageAnimated { return "动图" }
        return "照片"
    }

    // MARK: - 拍摄位置

    @ViewBuilder
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead(symbol: "location.north.line.fill", title: "拍摄位置")

            if let location = asset.location {
                PhotoMapView(coordinate: location.coordinate)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1))

                HStack(alignment: .firstTextBaseline) {
                    Text(place.isEmpty ? "拍摄地" : place)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 12)
                    Text(address)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.trailing)
                }
            } else {
                Text("这张没有记录位置信息")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
    }

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 150, height: 52)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .frame(maxWidth: .infinity)
    }

    // MARK: - 数据

    private func load() async {
        var m = PhotoMeta(resolution: "\(asset.pixelWidth) × \(asset.pixelHeight)")
        if asset.mediaType == .video { m.duration = Self.duration(asset.duration) }
        Self.applyFile(&m, of: asset)
        let raw = await Self.readExif(of: asset)
        Self.applyExif(&m, raw)
        meta = m
        guard let location = asset.location else { return }
        let marks = await Self.reverseGeocode(location)
        place = marks.short
        address = marks.full
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60, s = total % 60
        if m >= 60 { return "\(m / 60) 小时 \(m % 60) 分" }
        return s < 10 ? "\(m):0\(s)" : "\(m):\(s)"
    }

    private static func weekdayTime(_ date: Date?) -> String {
        guard let date else { return "时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return formatter.string(from: date)
    }

    private static func applyFile(_ meta: inout PhotoMeta, of asset: PHAsset) {
        guard let resource = PHAssetResource.assetResources(for: asset).first else { return }
        meta.fileName = resource.originalFilename
        meta.format = resource.uniformTypeIdentifier.uppercased()
        if let bytes = resource.value(forKey: "fileSize") as? NSNumber {
            meta.fileSize = ByteCountFormatter.string(fromByteCount: bytes.int64Value,
                                                      countStyle: .file)
        }
    }

    private static func applyExif(_ meta: inout PhotoMeta, _ raw: [String: String]) {
        meta.device = raw["device"] ?? ""
        meta.aperture = raw["aperture"] ?? ""
        meta.shutter = raw["shutter"] ?? ""
        meta.iso = raw["iso"] ?? ""
        meta.focal = raw["focal"] ?? ""
    }

    private static func readExif(of asset: PHAsset) async -> [String: String] {
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
                // Photos 没把这个键导出到 Swift，用字面量取，取不到就没有相机参数
                continuation.resume(returning: resultInfo?["PHImageInfoKey"] as? [String: Any])
            }
        }
        guard let info else { return [:] }
        let tiff = info[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = info[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        var out: [String: String] = [:]

        let make = tiff[kCGImagePropertyTIFFMake as String] as? String
        let model = tiff[kCGImagePropertyTIFFModel as String] as? String
        if let make, let model {
            out["device"] = "\(make) \(model)"
        } else if let model {
            out["device"] = model
        }
        if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
           let first = iso.first {
            out["iso"] = "ISO \(first)"
        }
        if let f = exif[kCGImagePropertyExifFNumber as String] as? Double {
            out["aperture"] = String(format: "f%.2f", f)
        }
        if let focal = exif[kCGImagePropertyExifFocalLength as String] as? Double {
            out["focal"] = String(format: "%.0f mm", focal)
        }
        if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double,
           exposure > 0 {
            out["shutter"] = String(format: "1/%.0f s", 1 / exposure)
        }
        return out
    }

    private static func reverseGeocode(_ location: CLLocation) async -> (short: String, full: String) {
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let mark = marks.first else { return ("", "查不到地名，可能要联网") }
        let short = mark.name ?? ""
        let full = [mark.administrativeArea, mark.locality, mark.subLocality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "")
        return (short, full.isEmpty ? (mark.locality ?? "") : full)
    }
}

// MARK: - 数据壳

struct PhotoMeta {
    var device = ""
    var aperture = ""
    var shutter = ""
    var iso = ""
    var focal = ""
    var fileName = ""
    var resolution = ""
    var fileSize = ""
    var format = ""
    var duration = ""

    struct Chip: Identifiable {
        let id: String
        let value: String
        let label: String
    }

    var chips: [Chip] {
        var list: [Chip] = []
        if !aperture.isEmpty { list.append(.init(id: "a", value: aperture, label: "光圈")) }
        if !shutter.isEmpty { list.append(.init(id: "s", value: shutter, label: "快门")) }
        if !iso.isEmpty { list.append(.init(id: "i", value: iso, label: "感光度")) }
        if !focal.isEmpty { list.append(.init(id: "f", value: focal, label: "焦距")) }
        return list
    }
}

// MARK: - 小组件

private struct SectionHead: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
    }
}

private struct MetricChip: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct BulletRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 4, height: 4)
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DashedRule: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(path, with: .color(.white.opacity(0.16)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
        }
        .frame(height: 1)
        .padding(.horizontal, 20)
    }
}

// MARK: - 地图卡片

/// 用 MKMapView 而不是 SwiftUI 的 Map：API 老而稳定，绿色水滴针也能直接控制
struct PhotoMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D

    func makeCoordinator() -> PinDelegate { PinDelegate() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.mapType = .standard
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: 1400,
                                        longitudinalMeters: 1400)
        map.setRegion(region, animated: false)
        if map.annotations.isEmpty {
            let pin = MKPointAnnotation()
            pin.coordinate = coordinate
            map.addAnnotation(pin)
        }
    }
}

final class PinDelegate: NSObject, MKMapViewDelegate {
    func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        let id = "pin"
        let view: MKMarkerAnnotationView
        if let reused = map.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView {
            view = reused
            view.annotation = annotation
        } else {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.canShowCallout = false
            view.markerTintColor = .systemGreen
            view.glyphImage = UIImage(systemName: "camera.fill")
        }
        return view
    }
}
