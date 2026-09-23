import CoreMotion
import Foundation
import SwiftUI
import UIKit

// MARK: - 起床使命：身体类任务（打字 / 朗读 / 摇一摇 / 走够步数）
//
// 契约与 MissionHost 一致：struct XxxMissionView: View { let config: MissionConfig; let done: () -> Void }
// 只靠成员初始化器创建，完成时调用 done()。

// MARK: - 打字

struct TypingMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var chosen = PhraseBook.random(from: PhraseBook.morning)
    @State private var input = ""
    @State private var mistakes = 0
    @State private var finished = false
    @FocusState private var keyboard: Bool

    private var sentence: String {
        let raw = config.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? chosen : raw
    }

    private var wantedChars: [Character] { Array(MissionText.plain(sentence)) }
    private var typedChars: [Character] { Array(MissionText.plain(input)) }

    /// 第一个打错的位置，nil 表示目前全对
    private var wrongIndex: Int? {
        let typed = typedChars
        let wanted = wantedChars
        let limit = min(typed.count, wanted.count)
        var index = 0
        while index < limit {
            if typed[index] != wanted[index] { return index }
            index += 1
        }
        return typed.count > wanted.count ? wanted.count : nil
    }

    private var matchedCount: Int {
        if let wrong = wrongIndex { return wrong }
        return typedChars.count
    }

    private var isPassed: Bool {
        !wantedChars.isEmpty && wrongIndex == nil && typedChars.count == wantedChars.count
    }

    var body: some View {
        let wanted = wantedChars
        let typed = typedChars
        let matched = matchedCount
        let wrong = wrongIndex
        VStack(spacing: 14) {
            Text("把下面这句一字不差地打出来")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            targetCard(wanted: wanted, matched: matched, wrong: wrong)
            inputField(prompt: wanted.isEmpty ? "起来" : String(wanted[matched < wanted.count ? matched : 0]))
            statusBar(matched: matched, typed: typed.count)

            HStack(spacing: 12) {
                MissionBigButton(title: "清空重打", systemImage: "delete.left", prominent: false) {
                    Task { @MainActor in restart() }
                }
                Button("复制句子") {
                    let copy = sentence
                    Task { @MainActor in UIPasteboard.general.string = copy }
                }
                .buttonStyle(.glass)
            }

            if finished {
                MissionDoneFlag(text: "全部打对了，起来吧")
            }
            Spacer(minLength: 0)
        }
        .modifier(MissionWiggle(tick: mistakes))
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                keyboard = true
            }
        }
    }

    private func targetCard(wanted: [Character], matched: Int, wrong: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            charLine(wanted: wanted, matched: matched, wrong: wrong)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let next = matched < wanted.count ? wanted[matched] : nil {
                    Text("下一个：\(String(next))").glassChip(tint: Palette.accent.opacity(0.4))
                }
                Spacer()
                Text("\(matched)/\(wanted.count) 字")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .glassPanel(tint: Color.white.opacity(0.06))
    }

    private func charLine(wanted: [Character], matched: Int, wrong: Int?) -> Text {
        var line = Text("")
        for (index, character) in wanted.enumerated() {
            let piece = Text(String(character))
            if index == wrong {
                line = line + piece.foregroundColor(.white).fontWeight(.heavy)
            } else if index < matched {
                line = line + piece.foregroundColor(Palette.cool)
            } else if index == matched {
                line = line + piece.foregroundColor(Palette.accent).fontWeight(.bold)
            } else {
                line = line + piece.foregroundColor(.white.opacity(0.4))
            }
        }
        return line
    }

    private func inputField(prompt: String) -> some View {
        TextField("照着打", text: $input, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .focused($keyboard)
            .submitLabel(.done)
            .textInputAutocapitalization(.none)
            .autocorrectionDisabled(true)
            .onSubmit { keyboard = false }
            .onChange(of: input) { _, _ in
                Task { @MainActor in checkInput() }
            }
            .glassPanel(tint: Color.white.opacity(0.08), cornerRadius: 20)
            .overlay(alignment: .topTrailing) {
                if let wrong = wrongIndex {
                    Text("第 \(wrong + 1) 个字不对")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.tint(Color.red.opacity(0.85)), in: Capsule())
                        .offset(y: -10)
                }
            }
    }

    private func statusBar(matched: Int, typed: Int) -> some View {
        HStack(spacing: 10) {
            Text("已输入 \(typed) 个字符").glassChip()
            if mistakes > 0 {
                Text("错 \(mistakes) 次").glassChip(tint: Color.red.opacity(0.4))
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.75))
    }

    @MainActor private func checkInput() {
        guard !finished else { return }
        if wrongIndex != nil {
            mistakes += 1
        } else if isPassed {
            finished = true
            keyboard = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.7))
                done()
            }
        }
    }

    @MainActor private func restart() {
        input = ""
        mistakes = 0
        finished = false
        keyboard = true
    }
}

// MARK: - 朗读

struct WordbeatMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var transcriber = SpeechTranscriber()
    @State private var chosen = PhraseBook.random(from: PhraseBook.morning)
    @State private var heard = ""
    @State private var holding = false
    @State private var stopRequested = false
    @State private var blocked = false
    @State private var finished = false

    private static let passThreshold = 0.7

    private var sentence: String {
        let raw = config.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? chosen : raw
    }

    var body: some View {
        let rate = SpeechCheck.hitRate(target: sentence, heard: heard)
        let percent = Int((rate * 100).rounded())
        VStack(spacing: 14) {
            Text("点下面的按钮开始，照着句子大声读一遍")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            VStack(alignment: .leading, spacing: 8) {
                Text("要读的句子")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                Text(sentence)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassPanel(tint: Palette.accent.opacity(0.10))

            VStack(alignment: .leading, spacing: 8) {
                Text("我听到的")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                Text(heard.isEmpty ? "还没有声音，点了开始就一直念" : heard)
                    .font(.body)
                    .foregroundStyle(heard.isEmpty ? Color.white.opacity(0.4) : Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassPanel(tint: Color.white.opacity(0.06))

            VStack(spacing: 8) {
                ProgressView(value: min(1, rate))
                    .tint(Palette.accent)
                Text("关键词命中 \(percent)%，到 \(Int((Self.passThreshold * 100).rounded()))% 才算过")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            MissionBigButton(title: buttonTitle, systemImage: "mic.fill", prominent: true) {
                Task { @MainActor in toggle() }
            }

            MissionHint(text: "读快读慢都行，把句子里的字都念到就够了。")

            if blocked {
                MissionPermissionGate(title: "需要用麦克风和语音识别",
                                      detail: "朗读使命要听你说话，识别只在本机完成。如果刚才拒绝过，请到 设置 - 隐私与安全 里打开麦克风与语音识别。",
                                      actionTitle: "再试一次",
                                      retry: { Task { @MainActor in blocked = false } })
            }
            if finished {
                MissionDoneFlag(text: "念得清楚，过关")
            }
            Spacer(minLength: 0)
        }
        .task { await setUp() }
        .onDisappear { Task { @MainActor in transcriber.stop() } }
    }

    private var buttonTitle: String {
        if finished { return "已经读完了" }
        return holding ? "我说完了" : "开始朗读"
    }

    @MainActor private func setUp() async {
        transcriber.onPartial = { text in
            Task { @MainActor in
                heard = text
                if !finished,
                   SpeechCheck.hitRate(target: sentence, heard: text) >= Self.passThreshold {
                    holding = false
                    transcriber.stop()
                    celebrate()
                }
            }
        }
        transcriber.onFinished = {
            Task { @MainActor in
                holding = false
                evaluate()
            }
        }
    }

    @MainActor private func toggle() {
        if holding || transcriber.isListening {
            requestStop()
        } else {
            requestStart()
        }
    }

    @MainActor private func requestStart() {
        guard !holding, !transcriber.isListening, !finished else { return }
        guard transcriber.isAvailable else {
            blocked = true
            return
        }
        holding = true
        blocked = false
        stopRequested = false
        Task { @MainActor in
            let ok = await transcriber.start()
            guard ok else {
                holding = false
                blocked = true
                return
            }
            if stopRequested {
                stopRequested = false
                requestStop()
            }
        }
    }

    @MainActor private func requestStop() {
        if transcriber.isListening {
            transcriber.stop()
            holding = false
            stopRequested = false
            evaluate()
        } else {
            // start() 还没回来：保持 holding，等它启动完成后立刻停掉，避免重复开录音
            stopRequested = true
        }
    }

    @MainActor private func evaluate() {
        guard !finished else { return }
        if SpeechCheck.hitRate(target: sentence, heard: heard) >= Self.passThreshold {
            celebrate()
        }
    }

    @MainActor private func celebrate() {
        guard !finished else { return }
        finished = true
        transcriber.stop()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            done()
        }
    }
}

// MARK: - 摇一摇

struct ShakeMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var detector = ShakeDetector()
    @State private var shown = 0
    @State private var wobble = false
    @State private var blocked = false
    @State private var finished = false

    private var target: Int { max(5, config.targetCount) }

    var body: some View {
        VStack(spacing: 14) {
            Text("拿起手机，用力摇满 \(target) 次")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            Image(systemName: MissionKind.shake.icon)
                .font(.system(size: 72))
                .foregroundStyle(Palette.accent)
                .rotationEffect(.degrees(wobble ? 11 : -11))
                .animation(.easeInOut(duration: 0.09).repeatCount(5, autoreverses: true), value: wobble)
                .padding(.vertical, 6)

            MissionCounter(current: shown, target: target, unit: "次")

            MissionHint(text: hint)

            if blocked {
                MissionPermissionGate(title: "读不到动作数据",
                                      detail: "这台设备的加速度计用不了，摇动没法被计成次数。换一台 iPhone 再试。",
                                      actionTitle: "再试一次",
                                      retry: { Task { @MainActor in await startDetector() } })
            }
            if finished {
                MissionDoneFlag(text: "摇够了，人应该已经站起来了")
            }
            Spacer(minLength: 0)
        }
        .task { await startDetector() }
        .onDisappear { Task { @MainActor in detector.stop() } }
    }

    private var hint: String {
        if shown == 0 { return "别躺着不动，把手机拿在手里左右甩。" }
        if shown * 2 < target { return "已经摇到 \(shown) 次了，继续别停。" }
        return "还剩 \(max(0, target - shown)) 次，甩快点就过了。"
    }

    @MainActor private func startDetector() async {
        guard detector.isAvailable else {
            blocked = true
            return
        }
        blocked = false
        detector.onCount = { value in
            Task { @MainActor in register(value) }
        }
        detector.start()
    }

    @MainActor private func register(_ value: Int) {
        shown = value
        wobble.toggle()
        guard value >= target, !finished else { return }
        finished = true
        detector.stop()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            done()
        }
    }
}

// MARK: - 走够步数

struct WalkMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var tracker = StepTracker()
    @State private var shown = 0
    @State private var authorized = false
    @State private var waiting = true
    @State private var finished = false

    private var target: Int { max(10, config.targetCount) }
    private var remain: Int { max(0, target - shown) }

    var body: some View {
        let deniedHard = authorized ? false : PermissionCentre.motionStatus() == .denied
        VStack(spacing: 14) {
            Text("必须下床走满 \(target) 步才能关")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            Image(systemName: MissionKind.walk.icon)
                .font(.system(size: 64))
                .foregroundStyle(Palette.cool)
                .offset(y: shown % 2 == 0 ? 0 : -7)
                .animation(.easeOut(duration: 0.16), value: shown)
                .padding(.vertical, 4)

            MissionCounter(current: shown, target: target, unit: "步")

            VStack(alignment: .leading, spacing: 6) {
                Text("已经走了 \(shown) 步")
                    .font(.title3.weight(.bold))
                Text(remain > 0 ? "还差 \(remain) 步" : "步数够了，可以回去了")
                    .font(.subheadline)
                    .foregroundStyle(remain > 0 ? Color.white.opacity(0.7) : Palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(tint: Color.white.opacity(0.06))

            MissionHint(text: nudge)

            if waiting && !authorized {
                ProgressView().tint(Palette.accent)
                MissionHint(text: "正在等运动权限…")
            }
            if !waiting && !authorized {
                MissionPermissionGate(title: "需要「运动与健身」权限",
                                      detail: deniedHard
                                        ? "计步被系统拒绝了。请到 设置 - 隐私与安全 - 运动与健身 里允许本 App，再回来点重试。"
                                        : "起床使命要读计步数据，才能确认你真的下床走过。数据只在本机统计。",
                                      actionTitle: "重新检查",
                                      retry: { Task { @MainActor in await recheck() } })
            }
            if finished {
                MissionDoneFlag(text: "走到 \(shown) 步了，人也清醒了")
            }
            Spacer(minLength: 0)
        }
        .task { await openGate() }
        .onDisappear { Task { @MainActor in tracker.stop() } }
    }

    private var nudge: String {
        if remain == 0 { return "好了，原路走回去关掉闹钟。" }
        if shown == 0 { return "先把脚放到地上，站起来再说。" }
        if remain > target / 2 { return "才走了这么点，去客厅绕一圈回来。" }
        return "就差 \(remain) 步，别现在就放弃。"
    }

    @MainActor private func openGate() async {
        waiting = true
        let granted = await PermissionCentre.ensureMotion()
        authorized = granted
        waiting = false
        guard granted, tracker.isAvailable else {
            authorized = false
            return
        }
        tracker.onSteps = { value in
            Task { @MainActor in register(value) }
        }
        tracker.start()
    }

    @MainActor private func recheck() async {
        await openGate()
    }

    @MainActor private func register(_ value: Int) {
        shown = value
        guard value >= target, !finished else { return }
        finished = true
        tracker.stop()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            done()
        }
    }
}

// MARK: - 私有零件

/// 打错时整块内容左右抖一下
private struct MissionWiggle: ViewModifier {
    let tick: Int
    @State private var tilted = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(tilted ? 2.5 : -2.5))
            .animation(.easeInOut(duration: 0.05).repeatCount(9, autoreverses: true), value: tilted)
            .onChange(of: tick) { _, _ in
                tilted.toggle()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.55))
                    tilted = false
                }
            }
    }
}

/// 过关提示条
private struct MissionDoneFlag: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
            Text(text).fontWeight(.semibold)
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Palette.accent.opacity(0.5)), in: Capsule())
    }
}

/// 文本归一化与分词：忽略大小写、空格和标点
private enum MissionText {
    static func plain(_ text: String) -> String {
        var kept: [Character] = []
        for scalar in text.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            kept.append(Character(scalar))
        }
        return String(kept).lowercased()
    }

    /// 中文按字切，英数按连续段整体当一个词
    static func tokens(of text: String) -> [String] {
        var runs: [[Character]] = []
        var current: [Character] = []
        var currentASCII = false

        for scalar in text.unicodeScalars {
            guard CharacterSet.alphanumerics.contains(scalar) else {
                if !current.isEmpty { runs.append(current); current = [] }
                continue
            }
            let character = Character(scalar)
            let ascii = scalar.isASCII
            if !current.isEmpty, ascii != currentASCII {
                runs.append(current)
                current = []
            }
            currentASCII = ascii
            current.append(character)
        }
        if !current.isEmpty { runs.append(current) }

        var keys: [String] = []
        for run in runs {
            if run.count == 1 || run.allSatisfy({ $0.isASCII }) {
                keys.append(String(run).lowercased())
            } else {
                keys.append(contentsOf: run.map { String($0) })
            }
        }
        return Array(Set(keys))
    }
}

/// 朗读使命的关键词命中率
private enum SpeechCheck {
    static func hitRate(target: String, heard: String) -> Double {
        let keys = MissionText.tokens(of: target)
        guard !keys.isEmpty else { return 0 }
        let haystack = MissionText.plain(heard)
        guard !haystack.isEmpty else { return 0 }
        var hits = 0
        for key in keys where haystack.range(of: key) != nil { hits += 1 }
        return Double(hits) / Double(keys.count)
    }
}
