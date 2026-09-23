import AVFoundation
import CoreGraphics
import SwiftUI
import UIKit

// MARK: - 起床使命：相机类任务（拍照 / 识别物体 / 扫码 / 深蹲）
//
// 契约与 MissionHost 一致：struct XxxMissionView: View { let config: MissionConfig; let done: () -> Void }
// 只靠成员初始化器创建，完成时调用 done()。
// 相机底座：拍照/识别/深蹲走 CameraMissionShell（视频模式 + onFrame），
// 扫码需要 metadata 模式，所以自己持有 CameraRunner + CameraPreview。

// MARK: - 拍照

struct PhotoMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var latest: CGImage?
    @State private var shot: CGImage?
    @State private var message = ""
    @State private var finished = false

    /// 参考图只解析一次：解不出来就当没设参考图
    private var reference: CGImage? {
        guard let data = config.referenceImage else { return nil }
        return UIImage(data: data)?.cgImage
    }

    private var requiresMatch: Bool { reference != nil }

    var body: some View {
        VStack(spacing: 12) {
            CameraMissionShell(backCamera: true, guide: guide, onFrame: { frame in
                keep(frame)
            }) {
                reticle
            }
            controls
        }
    }

    private var guide: String {
        if shot != nil { return "已经拍下一张，看看能不能用" }
        return requiresMatch ? "拍到和参考图一样的地方才算起床" : "拍一张你现在的样子，随便什么都行"
    }

    /// 预览上的取景提示：定格后直接用这张图当拍到的照片
    private var reticle: some View {
        ZStack {
            if let shot {
                Image(uiImage: UIImage(cgImage: shot))
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 2)
                    .padding(22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            if !message.isEmpty {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(Color.red.opacity(0.45)),
                                 in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 12) {
                if shot == nil {
                    MissionBigButton(title: "拍一张", systemImage: "camera.fill",
                                     prominent: true) {
                        capture()
                    }
                } else {
                    MissionBigButton(title: "重拍", systemImage: "arrow.counterclockwise") {
                        redo()
                    }
                    MissionBigButton(title: "就用这张", systemImage: "checkmark",
                                     prominent: true) {
                        accept()
                    }
                }
            }
            if finished {
                MissionPassFlag(text: "拍好了，这个使命算过了")
            }
        }
    }

    private func keep(_ frame: CGImage) {
        guard shot == nil, !finished else { return }
        latest = frame
    }

    /// 不额外接一次 AVCapturePhotoOutput，直接把当前帧当照片，够用且零风险
    private func capture() {
        guard let frame = latest else {
            message = "相机还在启动，等一秒再按"
            return
        }
        shot = frame
        message = ""
    }

    private func accept() {
        guard shot != nil else { return }
        guard let reference, let shot else {
            pass()
            return
        }
        let score = ImageHasher.similarity(shot, reference)
        if score >= 0.62 {
            message = ""
            pass()
        } else {
            message = "不太像，再靠近一点拍（像度 \(Int((score * 100).rounded()))%）"
            self.shot = nil
        }
    }

    private func redo() {
        shot = nil
        message = ""
    }

    private func pass() {
        guard !finished else { return }
        finished = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            done()
        }
    }
}

// MARK: - 识别指定物体

struct RecognizeMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var target = ""
    @State private var ready = false
    @State private var busy = false
    @State private var lastScan = Date.distantPast
    @State private var hits = 0
    @State private var best = 0.0
    @State private var matchedLabel = ""
    @State private var finished = false

    private static let wanted = 2

    var body: some View {
        VStack(spacing: 12) {
            CameraMissionShell(backCamera: true, guide: "把镜头对准：\(shown)", onFrame: { frame in
                scan(frame)
            }) {
                overlay
            }
            panel
        }
        .onAppear {
            if !ready {
                target = MissionWords.clean(config.referenceName, fallback: "牙刷")
                ready = true
            }
        }
    }

    private var shown: String {
        target.isEmpty ? "指定物体" : target
    }

    private var overlay: some View {
        VStack {
            Text("对准目标：\(shown)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(Palette.cool.opacity(0.45)), in: Capsule())
                .padding(.top, 52)
            Spacer()
        }
    }

    private var panel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("目标 \(shown)").glassChip(tint: Palette.accent.opacity(0.35))
                Text("连中 \(min(Self.wanted, hits))/\(Self.wanted)").glassChip()
                Spacer()
                Menu {
                    ForEach(VisionLabelMap.titles, id: \.self) { title in
                        Button(title) {
                            Task { @MainActor in pick(title) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("换一个")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.bold())
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
            MissionHint(text: hint)
            if !matchedLabel.isEmpty {
                Text("看到的：\(matchedLabel)（\(Int((best * 100).rounded()))%）")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            if finished {
                MissionPassFlag(text: "拍到\(shown)了，起来")
            }
        }
    }

    private var hint: String {
        if finished { return "好了，使命完成。" }
        if hits > 0 { return "已经认出来了，再稳一秒别动。" }
        return "把镜头凑近一点，把这个东西完整放进画面里。"
    }

    private func pick(_ title: String) {
        target = title
        hits = 0
        best = 0
        matchedLabel = ""
    }

    private func scan(_ frame: CGImage) {
        guard !busy, !finished else { return }
        let now = Date()
        guard now.timeIntervalSince(lastScan) >= 0.4 else { return }
        lastScan = now
        busy = true
        let wanted = target
        VisionLab.classify(frame) { scores in
            scanBack(wanted, scores)
        }
    }

    private func scanBack(_ wanted: String, _ scores: [String: Double]) {
        busy = false
        guard !finished else { return }
        // 换目标之后旧结果作废
        guard wanted == target else {
            hits = 0
            return
        }
        if VisionLabelMap.matches(target: wanted, scores: scores, threshold: 0.1) {
            hits += 1
            best = scores.values.max() ?? best
        } else {
            hits = 0
        }
        if let top = topLabel(in: scores) { matchedLabel = top }
        guard hits >= Self.wanted else { return }
        finished = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            done()
        }
    }

    /// 置信度最高、而且在目标关键词里的那个标签，只用来做提示
    private func topLabel(in scores: [String: Double]) -> String? {
        let keys = VisionLabelMap.keywords(for: target)
        guard !keys.isEmpty else { return nil }
        var found: String?
        var foundScore = 0.0
        for (label, confidence) in scores where confidence >= 0.1 {
            guard keys.contains(where: { key in label.contains(key) || key.contains(label) }) else { continue }
            guard confidence > foundScore else { continue }
            found = label
            foundScore = confidence
        }
        return found
    }
}

// MARK: - 扫码

struct BarcodeMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var runner = CameraRunner()
    @State private var granted = false
    @State private var blocked = false
    @State private var backCamera = true
    @State private var matched = ""
    @State private var miss = ""
    @State private var finished = false

    private var wanted: String {
        config.barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 12) {
            stage
            controls
        }
        .task { await open() }
        .onDisappear { runner.stop() }
    }

    @ViewBuilder
    private var stage: some View {
        if granted {
            CameraPreview(runner: runner)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay { reticle }
                .overlay(alignment: .top) { banner }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MissionPermissionGate(title: "需要用一下相机",
                                  detail: "起床使命要扫到你放好的那个码才能关闹钟，扫码完全在本机完成。",
                                  actionTitle: "重新授权") {
                Task { @MainActor in await open() }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 取景框：整片压暗 + 一个描边方框
    private var reticle: some View {
        ZStack {
            Color.black.opacity(0.35)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Palette.accent, lineWidth: 3)
                .frame(width: 228, height: 228)
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 1)
                .frame(width: 256, height: 256)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var banner: some View {
        Text(topGuide)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.tint(Color.black.opacity(0.4)), in: Capsule())
            .padding(.horizontal, 22)
            .padding(.top, 8)
    }

    private var topGuide: String {
        if finished { return "扫到了，可以起来了" }
        return wanted.isEmpty ? "对准任意一个码" : "必须扫到指定的码"
    }

    private var controls: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(wanted.isEmpty ? "扫到任意码就行" : "目标码：\(wanted)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(tint: Color.white.opacity(0.06))

            HStack(spacing: 10) {
                Text(backCamera ? "后置镜头" : "前置镜头").glassChip()
                MissionBigButton(title: "换镜头", systemImage: "camera.rotate") {
                    Task { @MainActor in flipCamera() }
                }
                .frame(maxWidth: 150)
            }
            MissionHint(text: guide, systemImage: config.preferQR ? "qrcode.viewfinder" : "barcode.viewfinder")
            if finished {
                MissionPassFlag(text: "码对上了")
            }
        }
    }

    private var statusLine: String {
        if finished { return "已确认：\(matched)" }
        if !matched.isEmpty { return "刚扫到：\(matched)" }
        if !miss.isEmpty { return "扫到的是 \(miss)，不是你要的那个" }
        return "还没扫到，慢慢移动手机找焦点"
    }

    private var guide: String {
        if !wanted.isEmpty {
            return "把闹钟放到设码的位置旁边，对准了别动，扫到会自动过关。"
        }
        return config.preferQR
            ? "找个二维码对准框，比如书背面、包装上的方格码。"
            : "对准商品上的条形码，一条一条黑白那种。"
    }

    @MainActor private func open() async {
        blocked = false
        guard await PermissionCentre.ensureCamera() else {
            granted = false
            blocked = true
            return
        }
        granted = true
        runner.onCode = { value, type in
            Task { @MainActor in receive(value, type) }
        }
        runner.start(mode: .metadata, backCamera: backCamera)
    }

    @MainActor private func flipCamera() {
        backCamera.toggle()
        runner.stop()
        runner.start(mode: .metadata, backCamera: backCamera)
    }

    @MainActor private func receive(_ value: String, _ type: String) {
        guard !finished else { return }
        if wanted.isEmpty {
            matched = value
            buzz()
            finished = true
            runner.stop()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                done()
            }
            return
        }
        let left = MissionWords.key(value)
        let right = MissionWords.key(wanted)
        if left == right || left.contains(right) {
            matched = value
            miss = ""
            buzz()
            finished = true
            runner.stop()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                done()
            }
        } else {
            miss = value
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    private func buzz() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - 深蹲计数

struct SquatMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var busy = false
    @State private var lastCheck = Date.distantPast
    @State private var down = false
    @State private var count = 0
    @State private var empty = false
    @State private var finished = false

    private var target: Int { max(3, config.targetCount) }

    var body: some View {
        VStack(spacing: 12) {
            CameraMissionShell(backCamera: false, guide: "站到镜头前，退后一点露出全身", onFrame: { frame in
                judge(frame)
            }) {
                overlay
            }
            VStack(spacing: 10) {
                MissionCounter(current: count, target: target, unit: "个")
                MissionHint(text: guide, systemImage: "figure.cooldown")
            }
            if finished {
                MissionPassFlag(text: "蹲够 \(count) 个，腿应该已经醒了")
            }
        }
    }

    private var overlay: some View {
        VStack {
            Spacer()
            Text(cue)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular.tint(cueTint), in: Capsule())
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var cue: String {
        if finished { return "做完了" }
        if empty { return "没看到你" }
        if down { return "起来" }
        return "下蹲"
    }

    private var cueTint: Color {
        if finished { return Palette.accent.opacity(0.55) }
        if empty { return Color.white.opacity(0.30) }
        return down ? Palette.cool.opacity(0.55) : Palette.accent.opacity(0.45)
    }

    private var guide: String {
        if finished { return "够了，使命完成。" }
        if empty { return "站到镜头前，退后一点露出全身，脚别出画面。" }
        if count == 0 { return "跟着大字做：蹲下去再站起来，就算一个。" }
        if count >= target { return "数量够了。" }
        return "已经做了 \(count) 个，还差 \(target - count) 个，别偷靠墙。"
    }

    private func judge(_ frame: CGImage) {
        guard !busy, !finished else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCheck) >= 0.35 else { return }
        lastCheck = now
        busy = true
        VisionLab.bodyPose(frame) { pose in
            judgeBack(pose)
        }
    }

    private func judgeBack(_ pose: BodyPose?) {
        busy = false
        guard !finished else { return }
        guard let pose else {
            empty = true
            return
        }
        empty = false
        if pose.isSquatting {
            down = true
        } else if down {
            down = false
            count += 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        guard count >= target else { return }
        finished = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            done()
        }
    }
}

// MARK: - 私有零件

/// 过关提示条
private struct MissionPassFlag: View {
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

/// 文案与比对用的文本清洗
private enum MissionWords {
    /// 比对用：去掉首尾空白并转小写
    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 配置里读到的名字：清洗后为空就给个兜底值
    static func clean(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
