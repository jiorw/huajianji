import SwiftUI
import UIKit

enum Support {
    /// 想改称呼告诉我，比如换成你自己的名字
    static let assistantName = "暖暖"
}

// MARK: - 问题反馈

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var notice = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("联系\(Support.assistantName)")
                    .font(.title2.weight(.bold))
                Text("用起来哪里别扭、想要什么新功能，都写在这里。写完点复制，贴到你想发的地方。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 180)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                if !notice.isEmpty {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack(spacing: 12) {
                    Button {
                        text = ""
                        notice = ""
                    } label: {
                        Text("清空").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.glass)

                    Button {
                        copyAll()
                    } label: {
                        Text("复制").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer()
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            // 底下透一点 App 的模糊照片，玻璃卡片才有东西可折射
            .presentationBackground(.black.opacity(0.72))
        }
    }

    private func draft() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "花间集 v\(version) · iOS \(UIDevice.current.systemVersion)\n\n\(text)"
    }

    private func copyAll() {
        UIPasteboard.general.string = draft()
        notice = "已复制，直接去粘贴就行"
    }
}

// MARK: - 关于

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// CI 会把 GitHub 的 run 号写进 CFBundleVersion，用来确认手机上装的是哪一次构建
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 自绘页头：只固定这一条，下面所有内容（含标题和那句文案）整体滚动
            ZStack {
                Text("关于")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .glassEffect(.regular.interactive(), in: Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("花间集").font(.title2.weight(.bold))
                        Text("v\(version)（构建 \(build)） · 随机翻相册")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("花间集，是一本属于你的私人相册。\n它不只是存放照片，而是帮你把生活里的繁花，温柔地整理成回忆。")
                        .font(.callout)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))

                    block("怎么翻", [
                        "每次随机发一组，默认 20 张，数量在设置里改。",
                        "首页三张卡片叠着，往右滑看下一张，往左滑退回去，点中间那张看大图。",
                        "大图页往左往右翻，往上滑丢进待删，往下滑退出。手里有没确认的待删时，退出会先问你。",
                        "双击放大，两指捏合也行，放大了拖着看细节。",
                        "实况照片长按播放；视频有「全屏观看」，横过来看更舒服。",
                        "待删的照片在弹层里点一下就能反悔。"
                    ])

                    block("五个册", [
                        "花间册：相册里所有照片。",
                        "碎影集：只翻截图，跟花间册分开记。",
                        "花影染：给照片调色，黑金、青橙这些风格都有，也能导 .cube。",
                        "流光卷：只翻视频。",
                        "岁华簿：翻了多少、删了多少、腾出多少空间。"
                    ])

                    block("删除是两步", [
                        "上滑只是先放进待删，相册一点没变。",
                        "一组翻完会结算：左边「再来一组」什么都不动，右边「确认删除」才真删。",
                        "真删之后，30 天内系统相册「最近删除」里还能找回来。"
                    ])

                    block("别的", [
                        "收藏：大图页点个心，岁华簿里能翻收藏夹。",
                        "回到那天：专翻往年今天拍的照片。",
                        "投屏：视频可以投到电视上。",
                        "每日提醒：本地通知，不走网络。"
                    ])

                    block("隐私", [
                        "数据全在手机里，没有服务器，不上传照片。",
                        "换手机用设置里的「导出浏览记录」搬。"
                    ])
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        // 底下透一点 App 的模糊照片，玻璃卡片才有东西可折射
        .presentationBackground(.black.opacity(0.72))
    }

    private func block(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
