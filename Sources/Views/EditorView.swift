import SwiftUI
import Photos
import PhotosUI

/// 花影染：滤镜编辑器。滤镜条带实时缩略图（拿当前照片小图逐个渲染），
/// 强度滑杆防抖渲染，长按预览对比原图
struct EditorView: View {
    @StateObject private var luts = LUTStore()

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var source: UIImage?
    @State private var preview: UIImage?
    @State private var renderID = 0
    @State private var choice: EditorChoice = .original
    @State private var strength: Double = 1
    @State private var isWorking = false
    @State private var notice: String?
    @State private var failed = false
    @State private var showLUTImporter = false
    @State private var showingOriginal = false

    /// 滤镜缩略图：key 是 EditorChoice.title，渲染完成一个补一个
    @State private var thumbs: [String: UIImage] = [:]
    @State private var baseThumb: UIImage?
    @State private var thumbTask: Task<Void, Never>?
    @State private var renderTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 14) {
            if let source {
                previewArea(source)

                filterStrip

                if !choice.isOriginal {
                    strengthRow
                }

                actionRow
            } else {
                emptyState
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .animation(.snappy(duration: 0.3), value: notice)
        .animation(.snappy(duration: 0.3), value: choice.isOriginal)
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
                if failures.isEmpty { generateThumbnails() }
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
            // 渲染期间继续显示上一张，靠 renderID 换身份做淡入淡出，而不是插一个转圈把画面顶掉
            Image(uiImage: showingOriginal ? source : (preview ?? source))
                .resizable()
                .scaledToFit()
                .id(renderID)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.24), value: renderID)
        .animation(.easeOut(duration: 0.15), value: showingOriginal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.55))
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if !choice.isOriginal {
                badge(choice.title)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // 按住对比原图时的提示角标
            if showingOriginal {
                badge("原图")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        // 长按 = 看一眼没加滤镜的原图，松手回到效果
        .onLongPressGesture(minimumDuration: 0.12, pressing: { pressing in
            showingOriginal = pressing
        }, perform: {})
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.black.opacity(0.45)), in: Capsule())
            .padding(10)
    }

    // MARK: - 强度

    private var strengthRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "dial.min")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Slider(value: $strength, in: 0...1)
                .tint(.white)
            Text("\(Int((strength * 100).rounded()))%")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 42, alignment: .trailing)
                .contentTransition(.numericText(value: strength * 100))
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(.black.opacity(0.25)), in: Capsule())
        .frame(maxWidth: .infinity)
        .onChange(of: strength) { _, _ in refreshPreviewDebounced() }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItems) {
                actionLabel("换一张", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(PressableStyle())
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))

            Button {
                if let img = source { save(img) }
            } label: {
                actionLabel(choice.isOriginal ? "先选个风格" : "存为新照片",
                            systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PressableStyle())
            .glassEffect(.regular.tint(.black.opacity(0.30)).interactive(),
                         in: .rect(cornerRadius: 22))
            .disabled(isWorking || choice.isOriginal)
            .opacity(choice.isOriginal ? 0.45 : 1)
            .animation(.snappy(duration: 0.25), value: choice.isOriginal)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.filters")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color(red: 0.44, green: 0.66, blue: 1.0))
                .frame(width: 92, height: 92)
                .glassEffect(.regular.interactive(), in: Circle())
            VStack(spacing: 6) {
                Text("挑一张照片，套一个风格")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("自带多种胶片风格，也能导入 .cube LUT")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $pickerItems) {
                Label("选择照片", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.glassProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - 渲染

    /// 拖滑杆时别一格一渲染：停手 120ms 才真正重画，旧渲染直接作废
    private func refreshPreviewDebounced() {
        debounceTask?.cancel()
        isWorking = true
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            refreshPreview()
        }
    }

    private func refreshPreview() {
        renderTask?.cancel()
        guard let source else { preview = nil; return }
        guard !choice.isOriginal else {
            preview = source
            renderID += 1
            isWorking = false
            return
        }
        isWorking = true
        let picked = choice
        let level = strength
        renderTask = Task.detached(priority: .userInitiated) {
            let result = PhotoEffectEngine.render(source, choice: picked, strength: level, maxEdge: 1400)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                preview = result
                renderID += 1
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
                renderID += 1
                choice = .original
                notice = nil
                baseThumb = Self.downsample(image, maxEdge: 160)
                thumbs = [:]
                generateThumbnails()
            } else {
                notice = "这个不是能处理的图片，换一张"
            }
            isWorking = false
        }
    }

    /// 拿小图逐个渲染滤镜缩略图，一次生成一整条，渲染完一个亮一个
    private func generateThumbnails() {
        thumbTask?.cancel()
        guard let base = baseThumb else { return }
        let choices = EditorChoice.all(luts: luts.luts)
        let level = strength
        thumbTask = Task.detached(priority: .userInitiated) {
            for item in choices {
                guard !Task.isCancelled else { return }
                let title = item.title
                guard !item.isOriginal else {
                    await MainActor.run { self.thumbs[title] = base }
                    continue
                }
                let rendered = PhotoEffectEngine.render(base, choice: item, strength: level, maxEdge: 160)
                guard !Task.isCancelled else { return }
                await MainActor.run { self.thumbs[title] = rendered }
            }
        }
    }

    private static func downsample(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge, longest > 0 else { return image }
        let size = CGSize(width: image.size.width / longest * maxEdge,
                          height: image.size.height / longest * maxEdge)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - 滤镜条

    private var filterStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(EditorChoice.all(luts: luts.luts)) { item in
                        chip(item)
                            .id(item.title)
                    }
                    importLUTButton
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .onChange(of: choice) { _, newValue in
                // 选中谁就把谁滚到中间，不用手动划半天
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    proxy.scrollTo(newValue.title, anchor: .center)
                }
            }
        }
    }

    /// 圆形缩略图 + 名字在下，选中的亮描边（对齐主流修图 App 的滤镜条）
    private func chip(_ item: EditorChoice) -> some View {
        let selected = choice == item
        let accent = Color(red: 0.44, green: 0.66, blue: 1.0)
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                choice = item
            }
        } label: {
            VStack(spacing: 7) {
                // 有渲染好的就用，没赶上就先摆原图小图顶着
                Image(uiImage: thumbs[item.title] ?? baseThumb ?? UIImage())
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(selected ? accent : .white.opacity(0.16),
                                              lineWidth: selected ? 3 : 1)
                    )
                    .background(Circle().fill(Color(white: 0.12)))
                    .scaleEffect(selected ? 1.07 : 1)
                    .shadow(color: .black.opacity(selected ? 0.45 : 0.2), radius: 5, y: 3)
                Text(item.title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? accent : .white.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(width: 66)
            .contentShape(Rectangle())
            .animation(.spring(duration: 0.32, bounce: 0.22), value: selected)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
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
            VStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 58, height: 58)
                    .background(
                        Circle().fill(.white.opacity(0.08))
                    )
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.22),
                                              style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                Text("导入 LUT")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(width: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
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
