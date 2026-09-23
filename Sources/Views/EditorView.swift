import SwiftUI
import Photos
import PhotosUI

struct EditorView: View {
    @StateObject private var luts = LUTStore()

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var source: UIImage?
    @State private var preview: UIImage?
    @State private var choice: EditorChoice = .original
    @State private var strength: Double = 1
    @State private var isWorking = false
    @State private var notice: String?
    @State private var failed = false
    @State private var showLUTImporter = false

    var body: some View {
        VStack(spacing: 14) {
            if let source {
                previewArea(source)

                filterStrip

                if !choice.isOriginal {
                    HStack(spacing: 10) {
                        Text("强度")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Slider(value: $strength, in: 0...1)
                            .tint(.blue)
                        Text("\(Int((strength * 100).rounded()))")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .onChange(of: strength) { _, _ in refreshPreview() }
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItems) {
                        actionLabel("换一张", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))

                    Button {
                        save(source)
                    } label: {
                        actionLabel(choice.isOriginal ? "先选个风格" : "存为新照片",
                                    systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.blue.opacity(0.55)).interactive(),
                                 in: .rect(cornerRadius: 22))
                    .disabled(isWorking || choice.isOriginal)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
                VStack(spacing: 22) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 46))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("挑一张照片，套一个风格")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    PhotosPicker(selection: $pickerItems) {
                        Label("选择照片", systemImage: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 13)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.blue.opacity(0.42)).interactive(),
                                 in: .rect(cornerRadius: 24))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .onChange(of: pickerItems) { _, items in
            guard let item = items.last else { return }
            load(item)
        }
        .onChange(of: choice) { _, _ in refreshPreview() }
        .fileImporter(isPresented: $showLUTImporter,
                      allowedContentTypes: [.init(filenameExtension: "cube") ?? .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var failures: [String] = []
                for url in urls where luts.importCube(from: url) != nil {
                    failures.append(url.lastPathComponent)
                }
                notice = failures.isEmpty
                    ? "已导入 \(urls.count) 个 LUT"
                    : "这几个读不了：\(failures.joined(separator: "、"))"
            case .failure(let error):
                notice = error.localizedDescription
            }
        }
        .alert("没存进去", isPresented: $failed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("相册写入被拒了。检查一下是不是只给了「有限访问」权限。")
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private func previewArea(_ source: UIImage) -> some View {
        ZStack {
            if isWorking {
                ProgressView().tint(.white)
            } else if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(uiImage: source)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22)
            .strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .animation(.easeOut(duration: 0.18), value: choice)
        .overlay(alignment: .topLeading) {
            if !choice.isOriginal {
                Text("\(choice.title) · \(Int((strength * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(10)
            }
        }
    }

    private func actionLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }

    private func refreshPreview() {
        guard let source else { preview = nil; return }
        guard choice.isOriginal else {
            preview = source
            return
        }
        isWorking = true
        let picked = choice
        let level = strength
        Task.detached(priority: .userInitiated) {
            let result = PhotoEffectEngine.render(source, choice: picked, strength: level, maxEdge: 1400)
            await MainActor.run {
                preview = result
                isWorking = false
            }
        }
    }

    private func load(_ item: PhotosPickerItem) {
        isWorking = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                source = image
                preview = image
                choice = .original
                notice = nil
            } else {
                notice = "这个不是能处理的图片，换一张"
            }
            isWorking = false
        }
    }

    // MARK: - 滤镜条

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorChoice.all(luts: luts.luts)) { item in
                    chip(item)
                }
                importLUTButton
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ item: EditorChoice) -> some View {
        Button {
            choice = item
        } label: {
            Text(item.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(choice == item ? Color.blue.opacity(0.6) : Color.black.opacity(0.4),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(choice == item ? 0.4 : 0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if case .lut(let lut) = item {
                Button("删掉这个 LUT", role: .destructive) {
                    luts.remove(lut)
                    if choice == item { choice = .original }
                }
            }
        }
    }

    private var importLUTButton: some View {
        Button {
            showLUTImporter = true
        } label: {
            Label("导入 LUT", systemImage: "plus.rectangle.on.folder")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 保存

    private func save(_ image: UIImage) {
        isWorking = true
        let picked = choice
        let level = strength
        Task.detached(priority: .userInitiated) {
            let result = PhotoEffectEngine.render(image, choice: picked, strength: level, maxEdge: 2400)
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: result)
                    request.creationDate = Date()
                }
                await MainActor.run {
                    isWorking = false
                    notice = "已把「\(picked.title)」版本存进相册"
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
