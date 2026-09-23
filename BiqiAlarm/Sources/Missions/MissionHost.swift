import AVFoundation
import Speech
import SwiftUI

// MARK: - 使命舞台：统一外壳 + 分发到具体任务
//
// 每个任务视图的契约：
//   struct XxxMissionView: View { let config: MissionConfig; let done: () -> Void }
// 完成任务时调用 done()；外壳负责标题、轮数、限时和失败提示。

struct MissionStage: View {
    let config: MissionConfig
    var round: Int = 1
    var totalRounds: Int = 1
    var timeLimitSeconds: Int = 0
    var onFailed: (() -> Void)?
    let done: () -> Void

    @State private var remaining: Int = 0

    private var clock: String {
        guard timeLimitSeconds > 0 else { return "" }
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .onAppear { remaining = timeLimitSeconds }
        .task { await runTimer() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.kind.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(config.kind.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if totalRounds > 1 {
                    Text("第 \(round)/\(totalRounds) 轮").glassChip(tint: Palette.cool.opacity(0.5))
                }
                if timeLimitSeconds > 0 {
                    Text(clock)
                        .glassChip(tint: remaining <= 10 ? Color.red.opacity(0.6) : nil)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch config.kind {
        case .photo: PhotoMissionView(config: config, done: finish)
        case .recognize: RecognizeMissionView(config: config, done: finish)
        case .barcode: BarcodeMissionView(config: config, done: finish)
        case .math: MathMissionView(config: config, done: finish)
        case .memory: MemoryMissionView(config: config, done: finish)
        case .symbol: SymbolMissionView(config: config, done: finish)
        case .shake: ShakeMissionView(config: config, done: finish)
        case .walk: WalkMissionView(config: config, done: finish)
        case .squat: SquatMissionView(config: config, done: finish)
        case .tap: TapMissionView(config: config, done: finish)
        case .typing: TypingMissionView(config: config, done: finish)
        case .wordbeat: WordbeatMissionView(config: config, done: finish)
        }
    }

    private func finish() {
        done()
    }

    private func runTimer() async {
        guard timeLimitSeconds > 0 else { return }
        while remaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            remaining -= 1
        }
        onFailed?()
    }
}

// MARK: - 任务视图共用的零件

struct MissionCounter: View {
    let current: Int
    let target: Int
    var unit: String = ""

    private var ratio: Double { target == 0 ? 0 : min(1, Double(current) / Double(target)) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(AngularGradient(colors: [Palette.accent, Palette.cool, Palette.accent],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.4), value: ratio)
                VStack(spacing: 2) {
                    Text("\(current)")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("/ \(target) \(unit)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 168, height: 168)
            ProgressView(value: ratio)
                .tint(Palette.accent)
        }
    }
}

struct MissionHint: View {
    let text: String
    var systemImage: String = "lightbulb"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MissionBigButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .modifier(GlassButtonChoice(prominent: prominent))
        .tint(Palette.accent)
        .controlSize(.large)
    }
}

private struct GlassButtonChoice: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

struct MissionPermissionGate: View {
    let title: String
    let detail: String
    var actionTitle: String = "去开启"
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 42))
                .foregroundStyle(Palette.accent)
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            MissionBigButton(title: actionTitle, systemImage: "arrow.up.forward", prominent: true,
                             action: retry)
                .frame(maxWidth: 240)
        }
        .glassPanel(tint: Color.white.opacity(0.06))
    }
}

/// 相机任务的通用底座：预览 + 遮罩 + 权限
struct CameraMissionShell<Overlay: View>: View {
    @State private var model = CameraMissionModel()
    let backCamera: Bool
    var guide: String?
    @ViewBuilder var overlay: () -> Overlay
    let onFrame: (CGImage) -> Void
    let onCode: ((String, String) -> Void)?

    init(backCamera: Bool = true,
         guide: String? = nil,
         onFrame: @escaping (CGImage) -> Void,
         onCode: ((String, String) -> Void)? = nil,
         @ViewBuilder overlay: @escaping () -> Overlay) {
        self.backCamera = backCamera
        self.guide = guide
        self.onFrame = onFrame
        self.onCode = onCode
        self.overlay = overlay
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if model.granted {
                    CameraPreview(runner: model.runner)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.28), lineWidth: 1)
                        }
                        .overlay { overlay() }
                    if let guide {
                        VStack {
                            Text(guide)
                                .font(.footnote.weight(.semibold))
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .glassEffect(.regular.tint(Color.black.opacity(0.35)), in: Capsule())
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                            Spacer()
                        }
                    }
                } else {
                    MissionPermissionGate(
                        title: "需要用一下相机",
                        detail: "起床使命要拍到真实画面，图片只在本机比对，不会上传。",
                        retry: { Task { await model.prepare(backCamera: backCamera) } }
                    )
                    .padding(24)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task { await model.prepare(backCamera: backCamera) }
            .onDisappear { model.tearDown() }
            .onChange(of: model.frameTick) { _, _ in
                if let image = model.latestFrame { onFrame(image) }
            }
            .onChange(of: model.codeTick) { _, _ in
                if let code = model.lastCode, let type = model.lastCodeType { onCode?(code, type) }
            }
        }
    }
}

@MainActor
@Observable
final class CameraMissionModel {
    let runner = CameraRunner()
    var granted = false
    var frameTick = 0
    var codeTick = 0
    var latestFrame: CGImage?
    var lastCode: String?
    var lastCodeType: String?

    func prepare(backCamera: Bool) async {
        guard !granted else { return }
        let ok = await PermissionCentre.ensureCamera()
        granted = ok
        guard ok else { return }
        runner.onFrame = { [weak self] image in
            Task { @MainActor in
                self?.latestFrame = image
                self?.frameTick += 1
            }
        }
        runner.onCode = { [weak self] value, type in
            Task { @MainActor in
                self?.lastCode = value
                self?.lastCodeType = type
                self?.codeTick += 1
            }
        }
        runner.start(mode: .video, backCamera: backCamera)
    }

    func tearDown() {
        runner.stop()
    }
}

// MARK: - 语音转文字（朗读使命用）

@MainActor
final class SpeechTranscriber: NSObject {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var onPartial: ((String) -> Void)?
    var onFinished: (() -> Void)?
    private(set) var isListening = false

    override init() {
        super.init()
        for identifier in ["zh-CN", "en-US", "ja-JP", "ko-KR"] {
            if let candidate = SFSpeechRecognizer(locale: Locale(identifier: identifier)) {
                recognizer = candidate
                break
            }
        }
    }

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func start() async -> Bool {
        guard !isListening, let recognizer, recognizer.isAvailable else { return false }
        guard await PermissionCentre.ensureSpeech() else { return false }
        guard await PermissionCentre.ensureMicrophone() else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("语音引擎启动失败: \(error)")
            return false
        }
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in self.onPartial?(text) }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.stop()
                    self.onFinished?()
                }
            }
        }
        return true
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
