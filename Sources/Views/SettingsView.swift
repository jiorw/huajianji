import SwiftUI
import Photos

struct SettingsView: View {
    @ObservedObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    @State private var showFeedback = false
    @State private var showAbout = false
    @State private var backupURL: URL?
    @State private var showImporter = false

    private let card = Color(red: 0.082, green: 0.082, blue: 0.09)
    private let hair = Color.white.opacity(0.07)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                batchCard

                Card {
                    ToggleRow(title: "每日提醒", isOn: $store.reminderOn)
                    if store.reminderOn {
                        Hairline()
                        TimeRow(date: reminderDate, onChange: applyReminderDate)
                    }
                }

                Card {
                    ToggleRow(title: "震动反馈", isOn: $store.hapticsEnabled)
                    Hairline()
                    MenuRow(title: "双击手势",
                            value: store.doubleTapAction.title,
                            options: DoubleTapAction.allCases.map { ($0.title, $0.rawValue) }) { pick in
                        store.doubleTapAction = DoubleTapAction(rawValue: pick) ?? .zoom
                    }
                    Hairline()
                    MenuRow(title: "时间格式",
                            value: store.timeFormat.title,
                            options: TimeFormat.allCases.map { ($0.title, $0.rawValue) }) { pick in
                        store.timeFormat = TimeFormat(rawValue: pick) ?? .relative
                    }
                    Hairline()
                    MenuRow(title: "回顾模式",
                            value: store.mode.title,
                            options: BrowseMode.allCases.map { ($0.title, $0.rawValue) }) { pick in
                        store.mode = BrowseMode(rawValue: pick) ?? .blindBox
                    }
                }

                Card {
                    ToggleRow(title: "演示模式", isOn: $store.demoMode)
                    if store.demoMode {
                        Hairline()
                        CaptionRow(text: "开启后走完整流程，但确认删除不会动相册里的任何文件，统计数字也不计入。")
                    }
                }

                Card {
                    ActionRow(title: "导出浏览记录", systemImage: "arrow.down.doc",
                              value: backupURL == nil ? "" : "已生成") {
                        backupURL = store.exportBackup()
                    }
                    if let backupURL {
                        Hairline()
                        ShareRow(url: backupURL)
                    }
                    Hairline()
                    ActionRow(title: "从文件导入", systemImage: "arrow.up.doc") {
                        showImporter = true
                    }
                }

                Card {
                    ActionRow(title: "问题反馈", systemImage: nil) { showFeedback = true }
                    Hairline()
                    ActionRow(title: "关于", systemImage: nil, value: "v\(Self.appVersion)") { showAbout = true }
                }

                Text("花间集只在本机读取相册，不联网、不上传，所有记录存在 App 自己的沙盒里。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFeedback) { FeedbackSheet() }
        .sheet(isPresented: $showAbout) { AboutSheet() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.importBackup(from: url) }
            case .failure(let error):
                store.errorMessage = "读取文件失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack(alignment: .center) {
            Text("设置")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(Color(white: 0.16), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - 每组数量

    private var batchCard: some View {
        Card {
            StepperRow(title: "照片", value: $store.photoBatchSize, step: 5, range: 5...60, unit: "张")
            Hairline()
            StepperRow(title: "视频", value: $store.videoBatchSize, step: 1, range: 5...40, unit: "个")
        }
    }

    private var reminderDate: Date {
        var components = DateComponents()
        components.hour = store.reminderHour
        components.minute = store.reminderMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func applyReminderDate(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        store.reminderHour = components.hour ?? store.reminderHour
        store.reminderMinute = components.minute ?? store.reminderMinute
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - 卡片与行

    private struct Card<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            VStack(spacing: 0) { content }
                .background(Color(red: 0.082, green: 0.082, blue: 0.09),
                            in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(.white.opacity(0.045), lineWidth: 1))
        }
    }

    private struct Hairline: View {
        var body: some View {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.6)
                .padding(.leading, 18)
        }
    }

    private struct TitleText: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
    }

    private struct ValueText: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private struct ToggleRow: View {
        let title: String
        @Binding var isOn: Bool

        var body: some View {
            HStack {
                TitleText(text: title)
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
        }
    }

    private struct TimeRow: View {
        let date: Date
        var onChange: (Date) -> Void

        var body: some View {
            HStack {
                TitleText(text: "提醒时间")
                Spacer()
                DatePicker("", selection: Binding(get: { date }, set: onChange),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
        }
    }

    private struct CaptionRow: View {
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private struct MenuRow: View {
        let title: String
        let value: String
        let options: [(String, String)]
        var onPick: (String) -> Void

        var body: some View {
            Menu {
                ForEach(options, id: \.1) { option in
                    Button {
                        onPick(option.1)
                    } label: {
                        if option.0 == value {
                            Label(option.0, systemImage: "checkmark")
                        } else {
                            Text(option.0)
                        }
                    }
                }
            } label: {
                HStack {
                    TitleText(text: title)
                    Spacer()
                    ValueText(text: value)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
            }
            .buttonStyle(.plain)
        }
    }

    private struct ActionRow: View {
        let title: String
        let systemImage: String?
        var value: String = ""
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 15))
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                    }
                    TitleText(text: title)
                    Spacer()
                    if !value.isEmpty { ValueText(text: value) }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private struct ShareRow: View {
        let url: URL

        var body: some View {
            HStack {
                ShareLink(item: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15))
                        Text("分享这个文件")
                            .font(.system(size: 17))
                    }
                    .foregroundStyle(.blue)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
        }
    }

    private struct StepperRow: View {
        let title: String
        @Binding var value: Int
        let step: Int
        let range: ClosedRange<Int>
        let unit: String

        var body: some View {
            HStack {
                TitleText(text: title)
                Spacer()
                ValueText(text: "\(value) \(unit)")
                HStack(spacing: 8) {
                    roundButton("minus", enabled: value - step >= range.lowerBound) {
                        value = max(range.lowerBound, value - step)
                    }
                    roundButton("plus", enabled: value + step <= range.upperBound) {
                        value = min(range.upperBound, value + step)
                    }
                }
                .padding(.leading, 10)
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .animation(.snappy, value: value)
        }

        private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(enabled ? 0.12 : 0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
    }
}
