import SwiftUI

// MARK: - 全屏响铃 + 使命关卡（原版的 DismissAlarmScreen / MissionContainer）

struct RingingView: View {
    @Environment(AlarmStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var breathing = false

    private var state: RingingState? { store.ringing }

    var body: some View {
        ZStack {
            GlassBackdrop(using: Palette.alert) {
                RadialGradient(colors: [.black.opacity(0.55), .clear], center: .center,
                               startRadius: 20, endRadius: 520)
            }

            if let state {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.3), .clear],
                                             center: .center, startRadius: 6, endRadius: 250))
                        .frame(width: 500, height: 500)
                        .scaleEffect(breathing ? 1.1 : 0.85)
                        .opacity(breathing ? 0.9 : 0.3)
                        .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                                   value: breathing)
                        .allowsHitTesting(false)

                    VStack(spacing: 16) {
                        header(state)
                        if state.alarm.missions.isEmpty {
                            emptyMission(state)
                        } else {
                            MissionStage(config: currentConfig(state),
                                         round: state.missionIndex + 1,
                                         totalRounds: state.alarm.missions.count,
                                         timeLimitSeconds: state.alarm.missionTimeLimitSeconds,
                                         onFailed: { store.lastError = "超时了，重新做" },
                                         done: { store.completeMission() })
                                .id(state.missionIndex)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
                        }
                        controls(state)
                    }
                    .animation(GlassMotion.settle, value: state.missionIndex)
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
                .task(id: state.alarm.id) { await watch(timeout: state) }
            }
        }
        .interactiveDismissDisabled()
        .transition(.opacity)
    }

    private func currentConfig(_ state: RingingState) -> MissionConfig {
        let index = min(state.missionIndex, max(0, state.alarm.missions.count - 1))
        guard state.alarm.missions.indices.contains(index) else { return MissionConfig.default(.math) }
        return state.alarm.missions[index]
    }

    private func header(_ state: RingingState) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(ringingElapsed(context.date, from: state.startedAt))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Text(state.alarm.displayName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                if settings.motivationalQuotes {
                    Text(MorningGreeting.quote(category: settings.quoteCategory))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                if state.snoozeCount > 0 {
                    Text("已贪睡 \(state.snoozeCount) 次")
                        .glassNumber()
                        .glassChip(tint: Color.black.opacity(0.3))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if !state.alarm.missions.isEmpty {
                    Text("使命 \(min(state.missionIndex + 1, state.alarm.missions.count))/\(state.alarm.missions.count)")
                        .glassNumber()
                        .glassChip(tint: Color.black.opacity(0.35))
                }
                Text(settings.unbeatable ? "必起模式" : "普通模式").glassChip()
            }
        }
        .padding(.horizontal, 20)
    }

    private func emptyMission(_ state: RingingState) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 74))
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("这条闹钟没设使命")
                .font(.title3.bold())
            Text("原版里这叫「最容易被关掉」的闹钟。回编辑页加一个使命，会有效得多。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            MissionBigButton(title: "我起来了", systemImage: "checkmark.seal.fill",
                             prominent: true) {
                store.dismissWithoutMission()
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controls(_ state: RingingState) -> some View {
        VStack(spacing: 12) {
            volumeRow(state)
            GlassBar(spacing: 12) {
                if state.alarm.snooze.enabled {
                    Button {
                        store.snoozeCurrent()
                    } label: {
                        Label(snoozeTitle(state), systemImage: "zzz")
                            .glassNumber()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .disabled(snoozeBlocked(state))
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 520)
        }
    }

    private func volumeRow(_ state: RingingState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").foregroundStyle(.white.opacity(0.7))
            Slider(value: Binding(
                get: { Double(RingPlayer.shared.currentVolume) },
                set: { RingPlayer.shared.setVolume(Float($0)) }
            ), in: 0.05...1)
            .tint(.white)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .opacity(state.alarm.sound.isSilent ? 0.35 : 1)
    }

    private func snoozeTitle(_ state: RingingState) -> String {
        guard state.alarm.snooze.limit > 0 else { return "贪睡 \(state.alarm.snooze.minutes) 分" }
        let left = max(0, state.alarm.snooze.limit - state.snoozeCount)
        return left == 0 ? "贪睡已用完" : "贪睡 \(state.alarm.snooze.minutes) 分（剩 \(left)）"
    }

    private func snoozeBlocked(_ state: RingingState) -> Bool {
        state.alarm.snooze.limit > 0 && state.snoozeCount >= state.alarm.snooze.limit
    }

    /// 自动收起 / 响铃上限：没人理就记一次「睡过去了」
    private func watch(timeout state: RingingState) async {
        let alarm = state.alarm
        let hardLimit = max(60, alarm.ringLimitMinutes * 60)
        let window = alarm.autoDismissSeconds > 0 ? min(alarm.autoDismissSeconds, hardLimit) : hardLimit
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard let current = store.ringing, current.alarm.id == alarm.id else { return }
            if Int(Date().timeIntervalSince(current.startedAt)) >= window {
                store.dismissWithoutMission(kind: .missed)
                return
            }
        }
    }

    private func ringingElapsed(_ now: Date, from start: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return "已经响了 \(seconds / 60) 分 \(String(format: "%02d", seconds % 60)) 秒"
    }
}

private extension SoundChoice {
    var isSilent: Bool {
        if case .silence = self { return true }
        return false
    }
}
