import SwiftUI
import Photos
import PhotosUI

/// 演示模式设置：自选 5-15 张照片或视频，按所选顺序演示完整流程，
/// 删除不会真的执行，一组结束自动关闭。
struct DemoModeView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItems: [PhotosPickerItem] = []
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
                PhotosPicker(selection: $photoItems, matching: .images) {
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

                PhotosPicker(selection: $videoItems, matching: .videos) {
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
        .onChange(of: photoItems) { _, items in handle(items, isVideo: false) }
        .onChange(of: videoItems) { _, items in handle(items, isVideo: true) }
    }

    private func handle(_ items: [PhotosPickerItem], isVideo: Bool) {
        guard !items.isEmpty else { return }
        isWorking = true
        let ids = items.compactMap { $0.assetIdentifier }
        photoItems = []
        videoItems = []
        Task { @MainActor in
            var assets: [PHAsset] = []
            PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                .enumerateObjects { asset, _, _ in assets.append(asset) }
            guard assets.count >= minCount else {
                notice = "至少要选 \(minCount) 张，刚才只选了 \(assets.count) 张"
                isWorking = false
                return
            }
            if assets.count > maxCount {
                assets = Array(assets.prefix(maxCount))
                notice = "最多演示 \(maxCount) 张，已取前 \(maxCount) 张"
            } else {
                notice = nil
            }
            store.startDemo(with: assets, isVideoDemo: isVideo)
            try? await Task.sleep(for: .milliseconds(400))
            dismiss()
            isWorking = false
        }
    }
}
