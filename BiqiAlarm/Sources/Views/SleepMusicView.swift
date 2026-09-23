import AVFoundation
import SwiftUI

// MARK: - 七种循环底噪（样本全部是代码现算的，工程里不需要音频文件）

private enum SleepNoiseKind: String, CaseIterable, Identifiable {
    case waves
    case rain
    case fire
    case forest
    case cafe
    case heartbeat
    case alpha

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waves: return "海浪"
        case .rain: return "下雨"
        case .fire: return "篝火"
        case .forest: return "森林"
        case .cafe: return "咖啡馆"
        case .heartbeat: return "心跳"
        case .alpha: return "Alpha 波"
        }
    }

    var note: String {
        switch self {
        case .waves: return "一浪推一浪的低频，4 秒一个来回"
        case .rain: return "密集白噪加零星的雨点声"
        case .fire: return "低沉火堆加木柴爆裂的噼啪"
        case .forest: return "夜里穿林的风，偶尔起伏"
        case .cafe: return "远处人声嗡嗡加杯盏轻响"
        case .heartbeat: return "每分钟 75 次的低频胸腔声"
        case .alpha: return "10 Hz 调制的低频嗡鸣"
        }
    }

    var symbol: String {
        switch self {
        case .waves: return "water.waves"
        case .rain: return "cloud.rain.fill"
        case .fire: return "flame.fill"
        case .forest: return "leaf.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .heartbeat: return "heart.fill"
        case .alpha: return "waveform"
        }
    }

    /// 生成参数：level 总音量、smooth 低通（越大越闷）、crackle 爆裂概率、
    /// swellCycles 起伏圈数（整数才能保证循环点不断）、tone/pulse 纯音与脉冲
    var recipe: NoiseRecipe {
        switch self {
        case .waves:
            return NoiseRecipe(level: 0.55, smooth: 0.99, crackle: 0,
                               swellCycles: 1, swellDepth: 0.88)
        case .rain:
            return NoiseRecipe(level: 0.34, smooth: 0.55, crackle: 0.00004)
        case .fire:
            return NoiseRecipe(level: 0.36, smooth: 0.9, crackle: 0.0006,
                               swellCycles: 2, swellDepth: 0.45)
        case .forest:
            return NoiseRecipe(level: 0.28, smooth: 0.96, crackle: 0,
                               swellCycles: 1, swellDepth: 0.65)
        case .cafe:
            return NoiseRecipe(level: 0.32, smooth: 0.85, crackle: 0.00002,
                               swellCycles: 3, swellDepth: 0.35)
        case .heartbeat:
            return NoiseRecipe(level: 0.14, smooth: 0.99, pulseHz: 1.25, pulseLevel: 0.9)
        case .alpha:
            return NoiseRecipe(level: 0.12, smooth: 0.998, toneHz: 60,
                               toneLevel: 0.32, modHz: 10)
        }
    }
}

private struct NoiseRecipe {
    var level: Float = 0.3
    var smooth: Float = 0.9
    var crackle: Float = 0
    var swellCycles: Int = 0
    var swellDepth: Double = 0
    var toneHz: Double = 0
    var toneLevel: Float = 0
    var modHz: Double = 0
    var pulseHz: Double = 0
    var pulseLevel: Float = 0
}

// MARK: - 播放器：AVAudioEngine + 自己填的 PCM buffer 循环

@MainActor
private final class SleepNoisePlayer {
    private static let sampleRate: Double = 44100
    private static let loopSeconds: Double = 4
    private static let outFormat: AVAudioFormat? = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                                sampleRate: 44100,
                                                                channels: 2,
                                                                interleaved: false)

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var wired = false
    private var level: Float = 0.7
    private var cache: [SleepNoiseKind: AVAudioPCMBuffer] = [:]

    private(set) var isPlaying = false

    func setVolume(_ value: Float) {
        level = min(max(value, 0), 1)
        if wired { engine.mainMixerNode.outputVolume = level }
    }

    /// 返回 false 表示引擎没能起来，界面上要提示
    @discardableResult
    func play(_ kind: SleepNoiseKind) -> Bool {
        stopPlayback()
        guard let format = Self.outFormat else { return false }
        let buffer: AVAudioPCMBuffer
        if let cached = cache[kind] {
            buffer = cached
        } else if let made = Self.makeBuffer(for: kind, format: format) {
            cache[kind] = made
            buffer = made
        } else {
            return false
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio,
                                 options: [.duckOthers, .mixWithOthers, .allowBluetooth])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        if !wired {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            wired = true
        }
        engine.mainMixerNode.outputVolume = level
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("睡眠声音引擎启动失败: \(error)")
            return false
        }
        node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        node.play()
        isPlaying = true
        return true
    }

    func stop() {
        stopPlayback()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopPlayback() {
        guard wired else { return }
        node.stop()
        engine.stop()
        isPlaying = false
    }

    /// 4 秒循环样本：滤波噪声 + 缓慢起伏 + 可选的爆裂/纯音/脉冲
    private static func makeBuffer(for kind: SleepNoiseKind,
                                   format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * loopSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              buffer.format.channelCount >= 2,
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount
        let left = channels[0]
        let right = channels[1]
        let recipe = kind.recipe
        var filtered: Float = 0
        var impulse: Float = 0

        for index in 0..<Int(frameCount) {
            let time = Double(index) / sampleRate
            let white = Float.random(in: -1...1)
            filtered = filtered * recipe.smooth + white * (1 - recipe.smooth)
            var sample = filtered * recipe.level

            if recipe.crackle > 0, Float.random(in: 0...1) < recipe.crackle { impulse = 0.9 }
            impulse *= 0.9
            sample += impulse * 0.3

            if recipe.swellCycles > 0 {
                let angle = 2.0 * .pi * Double(recipe.swellCycles) * time / loopSeconds
                let swell = 1.0 - recipe.swellDepth * 0.5 * (1.0 - cos(angle))
                sample *= Float(max(0.04, swell))
            }
            if recipe.toneHz > 0 {
                let carrier = Float(sin(2.0 * .pi * recipe.toneHz * time))
                let modulator = Float(0.55 + 0.45 * sin(2.0 * .pi * recipe.modHz * time))
                sample += recipe.toneLevel * carrier * modulator
            }
            if recipe.pulseHz > 0 {
                let phase = (time * recipe.pulseHz).truncatingRemainder(dividingBy: 1.0)
                let beat = bump(phase, at: 0.05) + 0.65 * bump(phase, at: 0.28)
                sample += recipe.pulseLevel * beat * Float(sin(2.0 * .pi * 42.0 * time))
            }

            let value = max(-1, min(1, sample))
            left[index] = value
            right[index] = max(-1, min(1, value * 0.94 + filtered * 0.06))
        }
        return buffer
    }

    /// 一拍里的高斯状包络，取环绕距离保证循环点连续
    private static func bump(_ phase: Double, at position: Double) -> Float {
        let distance = min(abs(phase - position), 1.0 - abs(phase - position))
        return Float(exp(-distance * 22.0))
    }
}

// MARK: - 睡眠声音（原版 Listen To 这一栏，免费全开）

struct SleepMusicView: View {
    @State private var player = SleepNoisePlayer()
    @State private var playingKind: SleepNoiseKind?
    @State private var volume = AppSettings.shared.defaultVolume
    @State private var timerMinutes = 30
    @State private var timerTask: Task<Void, Never>?
    @State private var timerEndsAt: Date?
    @State private var note: String?

    private static let timerOptions = [15, 30, 45, 60, 90]

    var body: some View {
        ZStack {
            GlassBackdrop(using: Palette.night) { Color.clear }

            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let note {
                        Text(note)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    noiseCard
                    timerCard
                    volumeCard
                    footerCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
        }
        .onChange(of: volume) { _, newValue in
            player.setVolume(Float(newValue))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("睡眠声音")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("七种循环底噪，由本机实时合成，不占存储也不联网。听着听着就睡，不用起来关。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    // MARK: 底噪列表

    private var noiseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "循环底噪",
                          note: "点一下开始循环，再点一下停。切去别的页面也会继续放。")

            GlassEffectContainer(spacing: 10) {
                LazyVStack(spacing: 10) {
                    ForEach(SleepNoiseKind.allCases) { kind in
                        Button(action: { toggle(kind) }) {
                            HStack(spacing: 12) {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 20))
                                    .frame(width: 28)
                                    .foregroundStyle(playingKind == kind ? Palette.accent
                                                                          : Color.white.opacity(0.8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(kind.note)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.62))
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 6)
                                Text(playingKind == kind ? "播放中" : "播放")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }

            Button(action: { stopAll() }) {
                Text("停止播放")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .disabled(playingKind == nil)
        }
        .glassPanel()
    }

    // MARK: 睡眠定时

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "睡眠定时", note: "到点自动停止播放，不会整夜占着电池")

            Picker("定时长度", selection: $timerMinutes) {
                ForEach(Self.timerOptions, id: \.self) { minutes in
                    Text("\(minutes) 分").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            GlassBar(spacing: 12) {
                Button(action: { startTimer() }) {
                    Text("开始定时")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)

                Button(action: { cancelTimer() }) {
                    Text("取消定时")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .disabled(timerEndsAt == nil)
            }

            if let endsAt = timerEndsAt {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(endsAt, style: .relative)
                    Text("之后停止播放")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .glassPanel()
    }

    // MARK: 音量

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "音量", note: "只调睡眠声音本身，不动系统音量")
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.white.opacity(0.7))
                Slider(value: $volume, in: 0.05...1)
                    .tint(Palette.accent)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(Int(volume * 100))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .glassPanel()
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这些底噪是怎么来的")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.94))
            Text("由 App 用代码实时算出 4 秒循环样本（滤波噪声、缓慢起伏、低频脉冲），存在内存里循环，不占存储也不联网。闹钟响铃时优先级永远高于这里。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(tint: Color.indigo.opacity(0.25))
    }

    // MARK: 行为

    private func toggle(_ kind: SleepNoiseKind) {
        if playingKind == kind {
            stopAll()
        } else {
            start(kind)
        }
    }

    private func start(_ kind: SleepNoiseKind) {
        if RingPlayer.shared.isRinging {
            note = "闹钟正在响，先把使命做完再来放睡眠声音"
            return
        }
        player.setVolume(Float(volume))
        guard player.play(kind) else {
            note = "音频引擎没能起来，杀掉 App 再试一次"
            return
        }
        playingKind = kind
        note = nil
    }

    private func stopAll() {
        player.stop()
        playingKind = nil
        cancelTimer()
    }

    private func startTimer() {
        cancelTimerTask()
        if playingKind == nil {
            start(.rain)
            if playingKind == nil { return }
        }
        timerTask = Task {
            try? await Task.sleep(for: .seconds(TimeInterval(timerMinutes * 60)))
            guard !Task.isCancelled else { return }
            stopAll()
            note = "定时到了，睡眠声音已经停止"
        }
        timerEndsAt = Date().addingTimeInterval(TimeInterval(timerMinutes * 60))
    }

    private func cancelTimer() {
        cancelTimerTask()
        timerEndsAt = nil
    }

    private func cancelTimerTask() {
        timerTask?.cancel()
        timerTask = nil
    }
}
