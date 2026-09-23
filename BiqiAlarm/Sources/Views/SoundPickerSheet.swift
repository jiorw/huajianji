import AVFoundation
import AudioToolbox
import MediaPlayer
import SwiftUI

// MARK: - 铃声来源的三个分组

private enum SoundPickerSection: Hashable {
    case builtIn
    case recording
    case library
}

/// 音乐库里的一行：留得住的只有 persistentID 和歌名
private struct MusicLibraryRow: Identifiable, Hashable {
    let id: String
    let title: String
}

// MARK: - 选铃声面板（内置 / 自己录的 / 资料库里的歌）

struct SoundPickerSheet: View {
    let choice: SoundChoice
    let onPicked: (SoundChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var section = SoundPickerSection.builtIn
    @State private var search = ""

    // 试听
    @State private var previewingID: String?
    @State private var previewTask: Task<Void, Never>?

    // 录音
    @State private var recordings: [RingtoneItem] = RingtoneLibrary.recordings
    @State private var recorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var recordTask: Task<Void, Never>?
    @State private var isRecording = false
    @State private var recordSeconds = 0
    @State private var recordNote: String?
    @State private var savedCategory = AVAudioSession.Category.playback
    @State private var savedMode = AVAudioSession.Mode.default
    @State private var savedOptions: AVAudioSession.CategoryOptions = []

    // 音乐库
    @State private var libraryAuthorized = MPMediaLibrary.authorizationStatus() == .authorized
    @State private var songs: [MusicLibraryRow] = []
    @State private var exportingID: String?
    @State private var libraryNote: String?

    private static let maxRecordSeconds = 20

    var body: some View {
        ZStack {
            GlassBackdrop(using: Palette.night) { Color.clear }

            NavigationStack {
                VStack(spacing: 10) {
                    Picker("铃声来源", selection: $section) {
                        Text("内置铃声").tag(SoundPickerSection.builtIn)
                        Text("我的录音").tag(SoundPickerSection.recording)
                        Text("音乐库").tag(SoundPickerSection.library)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 16)

                    switch section {
                    case .builtIn: builtInList
                    case .recording: recordingPanel
                    case .library: libraryList
                    }
                }
                .padding(.top, 6)
                .navigationTitle("选择铃声")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            stopPreview()
                            dismiss()
                        }
                    }
                }
                .searchable(text: $search, prompt: Text("搜索名称"))
            }
        }
        .onAppear { reloadLibrary() }
        .onDisappear {
            stopPreview()
            cancelRecording()
        }
    }

    // MARK: 内置铃声

    private var builtInList: some View {
        List {
            ForEach(filteredBuiltIn) { item in
                row(title: item.title,
                    note: item.note,
                    selected: item.choice == choice,
                    busy: false,
                    previewing: previewingID == item.id,
                    showPreview: true,
                    pick: { pick(item.choice, id: item.id) },
                    preview: { togglePreview(item.choice, id: item.id) })
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    private var filteredBuiltIn: [RingtoneItem] {
        keep(RingtoneLibrary.builtInItems) { "\($0.title) \($0.note)" }
    }

    // MARK: 我的录音

    private var recordingPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "录一段自己的声音",
                              note: "最长 \(Self.maxRecordSeconds) 秒，存进「我的录音」，既能当铃声也能当使命提示音")

                GlassBar(spacing: 12) {
                    Button(action: { toggleRecording() }) {
                        Text(isRecording ? "停止录音" : "开始录音")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: { stopPreview() }) {
                        Text("停止试听")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .disabled(previewingID == nil)
                }

                if isRecording {
                    Text("正在录制 \(recordSeconds) 秒 / \(Self.maxRecordSeconds) 秒")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
                if let recordNote {
                    Text(recordNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .glassPanel()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            List {
                if filteredRecordings.isEmpty {
                    Text("还没有录音，点上面的「开始录音」试一段")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(filteredRecordings) { item in
                    row(title: item.title,
                        note: item.note,
                        selected: item.choice == choice,
                        busy: false,
                        previewing: previewingID == item.id,
                        showPreview: true,
                        pick: { pick(item.choice, id: item.id) },
                        preview: { togglePreview(item.choice, id: item.id) })
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }

    private var filteredRecordings: [RingtoneItem] {
        keep(recordings) { "\($0.title) \($0.note)" }
    }

    // MARK: 音乐库

    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !libraryAuthorized {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "还没有音乐库权限",
                                  note: "只读取你资料库里的歌名，不会上传任何东西")
                    Button(action: { reloadLibrary() }) {
                        Text("授权音乐库")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                }
                .glassPanel()
                .padding(.horizontal, 16)
            }

            if let libraryNote {
                Text(libraryNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            List {
                if songs.isEmpty {
                    Text(libraryAuthorized ? "资料库里没有可列出的歌曲" : "授权之后这里才会列出你的歌")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(filteredSongs) { song in
                    row(title: song.title,
                        note: exportingID == song.id ? "正在导出…" : "来自音乐库",
                        selected: isSelectedMusic(song),
                        busy: exportingID == song.id,
                        previewing: false,
                        showPreview: false,
                        pick: { exportAndPick(song) },
                        preview: {})
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }

    private var filteredSongs: [MusicLibraryRow] {
        keep(songs) { $0.title }
    }

    private func isSelectedMusic(_ song: MusicLibraryRow) -> Bool {
        if case .musicLibrary(let itemID, _) = choice { return itemID == song.id }
        return false
    }

    // MARK: 通用行：整行点选，右侧「试听」是独立按钮

    private func row(title: String, note: String, selected: Bool, busy: Bool, previewing: Bool,
                     showPreview: Bool, pick: @escaping () -> Void,
                     preview: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView().tint(.white)
            } else if showPreview {
                Button(action: { preview() }) {
                    Text(previewing ? "停止" : "试听")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .glassChip(tint: Color.black.opacity(0.35))
            }
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.12))
    }

    private func keep<T>(_ items: [T], _ text: (T) -> String) -> [T] {
        let key = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return items }
        return items.filter { text($0).contains(key) }
    }

    // MARK: - 选择 / 试听

    private func pick(_ newChoice: SoundChoice, id: String) {
        onPicked(newChoice)
        startPreview(newChoice, id: id)
    }

    private func togglePreview(_ newChoice: SoundChoice, id: String) {
        if previewingID == id {
            stopPreview()
        } else {
            startPreview(newChoice, id: id)
        }
    }

    /// 试听 3 秒后自动停。参数依次是：音量 / 渐强秒数 / 震动 / 静音档下是否仍循环
    private func startPreview(_ newChoice: SoundChoice, id: String) {
        previewTask?.cancel()
        RingPlayer.shared.start(choice: newChoice, volume: 0.9, fadeInSeconds: 0,
                                vibrate: false, loopWhileSilent: true)
        previewingID = id
        previewTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            RingPlayer.shared.stop()
            previewingID = nil
        }
    }

    private func stopPreview() {
        guard previewingID != nil else { return }
        previewTask?.cancel()
        previewTask = nil
        previewingID = nil
        RingPlayer.shared.stop()
    }

    // MARK: - 录音

    private func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            Task { await beginRecording() }
        }
    }

    /// 文件名带上时间戳，录音列表里一眼认得出是哪段
    private func newRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH-mm-ss"
        let name = "录音 \(formatter.string(from: Date())).m4a"
        return RingtoneLibrary.recordingDirectory.appendingPathComponent(name)
    }

    private func beginRecording() async {
        recordNote = nil
        stopPreview()
        guard await PermissionCentre.ensureMicrophone() else {
            recordNote = "没有麦克风权限，去系统设置里允许「必起闹钟」使用麦克风"
            return
        }

        let url = newRecordingURL()
        let session = AVAudioSession.sharedInstance()
        savedCategory = session.category
        savedMode = session.mode
        savedOptions = session.categoryOptions

        do {
            // 录音必须切到 .playAndRecord，用完在 restoreSession() 里还原
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let newRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1
            ], delegate: nil)
            guard newRecorder.record() else {
                recordNote = "录音没启动起来，看看是不是别的 App 正占着麦克风"
                restoreSession()
                return
            }
            recorder = newRecorder
            recordingURL = url
            isRecording = true
            recordSeconds = 0
            recordTask = Task { await countdownRecording() }
        } catch {
            recordNote = "录音失败：\(error.localizedDescription)"
            restoreSession()
        }
    }

    /// 数到 20 秒自己停，顺便刷新界面上的秒数
    private func countdownRecording() async {
        while !Task.isCancelled, isRecording {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            recordSeconds += 1
            if recordSeconds >= Self.maxRecordSeconds {
                finishRecording()
                return
            }
        }
    }

    private func finishRecording() {
        guard isRecording || recorder != nil else { return }
        recordTask?.cancel()
        recordTask = nil
        isRecording = false

        let seconds = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        restoreSession()

        if seconds < 1, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordNote = "录音太短了，没有保存"
        } else if let url = recordingURL {
            recordNote = "已保存「\(url.deletingPathExtension().lastPathComponent)」，点这一行就选它"
        }
        recordingURL = nil
        recordings = RingtoneLibrary.recordings
    }

    private func cancelRecording() {
        recordTask?.cancel()
        recordTask = nil
        guard isRecording || recorder != nil else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        restoreSession()
        recordings = RingtoneLibrary.recordings
    }

    private func restoreSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(savedCategory, mode: savedMode, options: savedOptions)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 音乐库

    private func reloadLibrary() {
        Task { await prepareLibrary() }
    }

    private func prepareLibrary() async {
        let status = MPMediaLibrary.authorizationStatus()
        if status == .notDetermined {
            let granted: Bool = await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { result in
                    DispatchQueue.main.async {
                        continuation.resume(returning: result == .authorized)
                    }
                }
            }
            libraryAuthorized = granted
        } else {
            libraryAuthorized = (status == .authorized)
        }

        if libraryAuthorized {
            loadSongs()
        } else {
            songs = []
            libraryNote = "没有媒体与 Apple Music 权限，只能用内置铃声或自己录的"
        }
    }

    private func loadSongs() {
        let items = MPMediaQuery.songs().items ?? []
        var rows: [MusicLibraryRow] = []
        rows.reserveCapacity(items.count)
        for item in items {
            rows.append(MusicLibraryRow(id: String(item.persistentID),
                                        title: item.title ?? "未知歌曲"))
        }
        rows.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        songs = rows
    }

    /// DRM 曲目导出必然失败，这是系统限制，直接告诉用户换一首
    private func exportAndPick(_ song: MusicLibraryRow) {
        guard exportingID == nil else { return }
        stopPreview()
        exportingID = song.id
        libraryNote = "正在从音乐库导出「\(song.title)」…"
        MusicFileExporter.export(itemId: song.id) { ok in
            self.exportingID = nil
            guard ok else {
                self.libraryNote = "「\(song.title)」有版权保护，用不了"
                return
            }
            self.libraryNote = nil
            self.onPicked(.musicLibrary(itemID: song.id, title: song.title))
        }
    }
}
