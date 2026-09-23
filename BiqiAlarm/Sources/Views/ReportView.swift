import SwiftUI

// MARK: - 起床报告（原版 Report / DailyReportScore / Efficiency + Regularity）

struct ReportView: View {
    @Environment(AlarmStore.self) private var store
    @State private var days = 7
    @State private var report = WakeReport(events: [])
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(using: Palette.night) { Color.clear }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        picker
                        scoreCards
                        statCards
                        historyCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 26)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { Text("起床报告").fontWeight(.bold) }
            }
            .toolbarTitleDisplayMode(.inline)
        }
        .onAppear(perform: reload)
        .onChange(of: days) { _, _ in reload() }
        .alert("清空全部起床记录？", isPresented: $confirmClear) {
            Button("清", role: .destructive) {
                WakeLog.shared.clear()
                reload()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var picker: some View {
        Picker("区间", selection: $days) {
            Text("近 7 天").tag(7)
            Text("近 30 天").tag(30)
            Text("全部").tag(3650)
        }
        .pickerStyle(.segmented)
    }

    private var scoreCards: some View {
        HStack(spacing: 12) {
            ScoreDial(title: "效率", value: report.efficiency, note: "耗时短、贪睡少")
            ScoreDial(title: "规律", value: report.regularity, note: "钟点稳不稳")
        }
    }

    private var statCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "明细")
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCell(title: "成功率", value: "\(Int(report.successRate * 100))%")
                    StatCell(title: "平均起床", value: report.averageWakeText)
                }
                GridRow {
                    StatCell(title: "使命完成", value: "\(report.missionDoneCount) 次")
                    StatCell(title: "贪睡合计", value: "\(report.totalSnooze) 次")
                }
            }
            if report.relativeScore != 0 {
                Label(relativeText, systemImage: report.relativeScore > 0
                      ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(report.relativeScore > 0 ? Color.green : Color.orange)
            }
        }
        .glassPanel()
    }

    private var relativeText: String {
        report.relativeScore > 0
            ? "比上周快 \(report.relativeScore)% 起床"
            : "比上周慢 \(abs(report.relativeScore))% 起床"
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "记录", note: "共 \(report.events.count) 条")
                Spacer()
                Button("清空", role: .destructive) { confirmClear = true }.font(.footnote)
            }
            if report.events.isEmpty {
                Text("还没有记录。早上被闹钟叫醒并做完使命后，这里才会有东西。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(report.events.sorted { $0.fireDate > $1.fireDate }.prefix(40)) { event in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: event.kind))
                            .foregroundStyle(color(for: event.kind))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.alarmLabel).font(.subheadline)
                            Text(event.fireDate, format: .dateTime.month().day().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(title(for: event.kind)).font(.caption.weight(.semibold))
                            if event.costMinutes > 0 {
                                Text("花了 \(event.costMinutes) 分").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
        .glassPanel()
    }

    private func reload() {
        report = WakeLog.shared.report(in: days)
    }

    private func icon(for kind: WakeKind) -> String {
        switch kind {
        case .missionDone: return "checkmark.seal.fill"
        case .plain: return "figure.stand"
        case .snoozed: return "zzz"
        case .missed: return "moon.fill"
        }
    }

    private func color(for kind: WakeKind) -> Color {
        switch kind {
        case .missionDone: return .green
        case .plain: return Palette.cool
        case .snoozed: return .orange
        case .missed: return .gray
        }
    }

    private func title(for kind: WakeKind) -> String {
        switch kind {
        case .missionDone: return "使命完成"
        case .plain: return "直接关"
        case .snoozed: return "贪睡"
        case .missed: return "睡过去了"
        }
    }
}

private struct ScoreDial: View {
    let title: String
    let value: Int
    let note: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(min(max(value, 0), 100)) / 100.0)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 92, height: 92)
            Text(title).font(.subheadline.weight(.semibold))
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .glassPanel(tint: Color.white.opacity(0.06), cornerRadius: 22)
    }
}

private struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
