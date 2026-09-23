import PhotosUI
import SwiftUI

// MARK: - 使命挑选（原版 EditAlarmMissionFeature / HabitMissionPick，多任务不锁会员）

struct MissionPickerView: View {
    let existing: [MissionConfig]
    let onPicked: ([MissionConfig]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: [MissionConfig]
    @State private var previewKind: MissionKind?

    init(existing: [MissionConfig], onPicked: @escaping ([MissionConfig]) -> Void) {
        self.existing = existing
        self.onPicked = onPicked
        _picked = State(initialValue: existing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(using: Palette.night) { Color.clear }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Text("挑一个或几个，按顺序做完才让关。原版里多种使命连做要开会员，这里不用。")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .glassPanel(tint: Color.white.opacity(0.06))

                        if !picked.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: "已选顺序")
                                ForEach(Array(picked.enumerated()), id: \.element.id) { index, mission in
                                    HStack {
                                        Text("\(index + 1)").font(.caption.bold()).foregroundStyle(Palette.accent)
                                        Image(systemName: mission.kind.icon)
                                        Text(mission.kind.title)
                                        Spacer()
                                        Text(mission.summary).font(.caption2).foregroundStyle(.secondary)
                                        Button {
                                            remove(mission)
                                        } label: {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                }
                            }
                            .glassPanel()
                        }

                        SectionHeader(title: "全部使命", note: "点一下加入，右上可以试做")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                                  spacing: 10) {
                            ForEach(MissionKind.allCases) { kind in
                                kindCard(kind)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 26)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("好了") {
                        onPicked(picked)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .sheet(item: $previewKind) { kind in
            MissionTrySheet(config: MissionConfig.default(kind))
        }
    }

    private func kindCard(_ kind: MissionKind) -> some View {
        Button {
            append(kind)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: kind.icon)
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                Text(kind.title).font(.subheadline.weight(.semibold))
                Text(kind.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !kind.permissions.isEmpty {
                    Text(kind.permissions.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .glassPanel(tint: contains(kind) ? Palette.accent.opacity(0.22) : Color.white.opacity(0.06),
                        cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("试做一次", systemImage: "play") { previewKind = kind }
        }
    }

    private func contains(_ kind: MissionKind) -> Bool {
        picked.contains { $0.kind == kind }
    }

    private func append(_ kind: MissionKind) {
        guard !contains(kind) else {
            removeFirst(kind)
            return
        }
        picked.append(MissionConfig.default(kind))
    }

    private func removeFirst(_ kind: MissionKind) {
        picked.removeAll { $0.kind == kind }
    }

    private func remove(_ mission: MissionConfig) {
        picked.removeAll { $0.id == mission.id }
    }
}

// MARK: - 单个使命的参数

struct MissionConfigSheet: View {
    let config: MissionConfig
    let onSave: (MissionConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MissionConfig
    @State private var trying = false

    init(config: MissionConfig, onSave: @escaping (MissionConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        _draft = State(initialValue: config)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(using: Palette.night) { Color.clear }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(config.kind.title, systemImage: config.kind.icon)
                                .font(.title3.bold())
                            Text(config.kind.subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassPanel(tint: Palette.accent.opacity(0.18))

                        commonControls
                        specificControls

                        if !config.kind.permissions.isEmpty {
                            Text("这个使命会用到：" + config.kind.permissions.joined(separator: "、")
                                 + "。第一次做的时候会弹系统授权。")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .glassPanel(cornerRadius: 18)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 26)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .sheet(isPresented: $trying) {
            MissionTrySheet(config: draft)
        }
    }

    private var commonControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "强度")
            if showsRounds {
                Stepper(value: $draft.rounds, in: 1...6) {
                    LabeledContent("连做几轮", value: "\(draft.rounds)")
                }
            }
            if showsDifficulty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("难度：\(MissionConfig.difficultyName(draft.difficulty))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(draft.difficulty) },
                                          set: { draft.difficulty = Int($0) }), in: 1...5, step: 1)
                        .tint(Palette.accent)
                }
            }
            if showsCount {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(countLabel)：\(draft.targetCount)").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(draft.targetCount) },
                                          set: { draft.targetCount = Int($0) }),
                           in: countRange, step: countStep)
                        .tint(Palette.accent)
                }
            }
        }
        .glassPanel()
    }

    @ViewBuilder
    private var specificControls: some View {
        switch draft.kind {
        case .typing, .wordbeat:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "要念/要打的句子", note: "留空则每轮换一句")
                TextField("句子", text: $draft.phrase, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Menu("从句子库挑一句") {
                    Button("清晨打气") { draft.phrase = PhraseBook.random(from: PhraseBook.morning, excluding: draft.phrase) }
                    Button("爱自己") { draft.phrase = PhraseBook.random(from: PhraseBook.love, excluding: draft.phrase) }
                    Button("念书") { draft.phrase = PhraseBook.random(from: PhraseBook.study, excluding: draft.phrase) }
                    Button("短句") { draft.phrase = PhraseBook.random(from: PhraseBook.short, excluding: draft.phrase) }
                }
                .buttonStyle(.glass)
            }
            .glassPanel()
        case .barcode:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "指定码", note: "留空 = 扫任意码都行")
                TextField("比如 ISBN 或快递单号", text: $draft.barcodeValue)
                    .autocorrectionDisabled()
                Toggle("优先二维码", isOn: $draft.preferQR).tint(Palette.accent)
                MissionBigButton(title: "现在去扫一个填进来", systemImage: "qrcode.viewfinder") {
                    draft.barcodeValue = "SCAN-NOW"
                }
            }
            .glassPanel()
        case .photo:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "参考图", note: "设了参考图就要拍得像才算过")
                if draft.referenceImage != nil {
                    HStack {
                        Text("已设置：\(draft.referenceName.isEmpty ? "参考图" : draft.referenceName)")
                        Spacer()
                        Button("清掉", role: .destructive) {
                            draft.referenceImage = nil
                            draft.referenceName = ""
                        }
                        .font(.footnote)
                    }
                }
                NavigationLink {
                    ReferencePhotoPicker { data, name in
                        draft.referenceImage = data
                        draft.referenceName = name
                    }
                } label: {
                    Label(draft.referenceImage == nil ? "从相册选一张" : "换一张", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .glassPanel()
        case .recognize:
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "要拍到的东西")
                Picker("目标", selection: $draft.referenceName) {
                    ForEach(VisionLabelMap.titles, id: \.self) { title in
                        Text(title).tag(title)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.accent)
            }
            .glassPanel()
        default:
            EmptyView()
        }
    }

    private var showsRounds: Bool {
        switch draft.kind {
        case .math, .memory, .symbol, .typing, .wordbeat, .tap: return true
        default: return false
        }
    }

    private var showsDifficulty: Bool {
        switch draft.kind {
        case .math, .memory, .symbol, .tap, .squat: return true
        default: return false
        }
    }

    private var showsCount: Bool {
        switch draft.kind {
        case .math, .shake, .walk, .squat, .tap: return true
        default: return false
        }
    }

    private var countLabel: String {
        switch draft.kind {
        case .math: return "题数"
        case .shake: return "摇几次"
        case .walk: return "步数"
        case .squat: return "深蹲个数"
        case .tap: return "点击次数"
        default: return "数量"
        }
    }

    private var countRange: ClosedRange<Double> {
        switch draft.kind {
        case .math: return 1...10
        case .walk: return 20...600
        case .squat: return 5...50
        case .tap: return 20...200
        default: return 5...120
        }
    }

    private var countStep: Double {
        draft.kind == .walk ? 10 : 1
    }
}

// MARK: - 立刻试做一次（设置页/编辑页都能用）

struct MissionTrySheet: View {
    let config: MissionConfig

    @Environment(\.dismiss) private var dismiss
    @State private var index = 1
    @State private var finished = false

    private var total: Int { max(1, config.rounds) }

    var body: some View {
        ZStack {
            GlassBackdrop(using: Palette.dawn) { Color.black.opacity(0.35) }
            if finished {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Palette.accent)
                    Text("通过了").font(.title2.bold())
                    Text("真到早上，这个过程会比现在更难糊弄。")
                        .font(.footnote).foregroundStyle(.secondary)
                    MissionBigButton(title: "知道了", prominent: true) { dismiss() }
                        .frame(maxWidth: 220)
                }
                .padding(30)
                .glassPanel(tint: Color.black.opacity(0.4))
                .padding(30)
            } else {
                MissionStage(config: config, round: index, totalRounds: total) {
                    if index >= total {
                        finished = true
                    } else {
                        index += 1
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 参考图选取

struct ReferencePhotoPicker: View {
    let onPicked: (Data, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            GlassBackdrop(using: Palette.night) { Color.clear }
            VStack(spacing: 14) {
                SectionHeader(title: "参考图", note: "闹钟响的时候必须拍出和它相似的画面")
                Button {
                    showLibrary = true
                } label: {
                    Label("从相册里选", systemImage: "photo.stack")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(" ")
        .sheet(isPresented: $showLibrary) {
            PhotoLibraryPick { data in
                onPicked(data, "参考图")
                dismiss()
            }
        }
    }
}

struct PhotoLibraryPick: View {
    let onPicked: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("选一张当参考")
                    .font(.headline)
                PhotosPicker("从相册选择", selection: $items, maxSelectionCount: 1,
                             matching: .images)
                    .buttonStyle(.glassProminent)
                    .tint(Palette.accent)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .task(id: items.count) {
            guard let item = items.first,
                  let data = try? await item.loadTransferable(type: Data.self) else { return }
            onPicked(data)
            dismiss()
        }
    }
}
