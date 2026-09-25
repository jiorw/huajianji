import SwiftUI
import Photos
import PhotosUI

/// 演示模式设置：自选 5-15 张照片或视频，按所选顺序演示完整流程，
/// 删除不会真的执行，一组结束自动关闭。
struct DemoModeView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPhotoPicker = false
    @State private var showVideoPicker = false
    @State private var notice: String?
    @State private var isWorking = false

    private let minCount = 5
    private let maxCount = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: Circle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("演示模式")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 18)

                    Text("请选择照片或视频来进行演示\n照片和视频会按照你选择的顺序排序\n你可以选择 5-\(maxCount) 张照片或视频用来进行一组的演示\n选择之后会自动跳转对应页面\n你可以截屏或录屏\n一组演示结束之后，会自动关闭演示模式\n演示删除的照片不会被真的删除")
                        .font(.callout)
                        .lineSpacing(6)
                        .foregroundStyle(Color(white: 0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    if store.demoMode {
                        Button {
                            store.endDemo()
                            dismiss()
                        } label: {
                            Text("退出演示模式")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        .glassEffect(.regular.tint(.red.opacity(0.55)).interactive(), in: Capsule())
                        .padding(.top, 8)
                    }

                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 14) {
                Button {
                    showPhotoPicker = true
                } label: {
                    Text("选择演示照片")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .glassEffect(.regular.interactive(), in: Capsule())
                .disabled(isWorking)

                Button {
                    showVideoPicker = true
                } label: {
                    Text("选择演示视频")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .glassEffect(.regular.interactive(), in: Capsule())
                .disabled(isWorking)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color(red: 0.045, green: 0.045, blue: 0.055).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPhotoPicker) {
            AssetPicker(filter: .images) { assets in
                handle(assets, isVideo: false)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showVideoPicker) {
            AssetPicker(filter: .videos) { assets in
                handle(assets, isVideo: true)
            }
            .ignoresSafeArea()
        }
    }

    private func handle(_ assets: [PHAsset], isVideo: Bool) {
        guard !assets.isEmpty else { return }
        var picked = assets
        if picked.count < minCount {
            notice = "至少要选 \(minCount) 张，刚才只选了 \(picked.count) 张"
            return
        }
        if picked.count > maxCount {
            picked = Array(picked.prefix(maxCount))
            notice = "最多演示 \(maxCount) 张，已取前 \(maxCount) 张"
        } else {
            notice = nil
        }
        store.startDemo(with: picked, isVideoDemo: isVideo)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            dismiss()
        }
    }
}

/// PHPicker 包装：能拿到 PHAsset，且按用户点选顺序返回
struct AssetPicker: UIViewControllerRepresentable {
    let filter: PHPickerFilter
    let onPicked: ([PHAsset]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = filter
        config.selectionLimit = 15
        if #available(iOS 17, *) {
            config.selection = .ordered
        }
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: AssetPicker
        init(_ parent: AssetPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let ids = results.compactMap { $0.assetIdentifier }
            var assets: [PHAsset] = []
            if !ids.isEmpty {
                PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                    .enumerateObjects { asset, _, _ in assets.append(asset) }
            }
            parent.onPicked(assets)
        }
    }
}
