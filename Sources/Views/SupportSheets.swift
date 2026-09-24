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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("花间集").font(.title2.weight(.bold))
                        Text("v\(version)（构建 \(build)） · 随机翻相册，边回忆边清理")
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
                        "每次从相册里随机发一组，默认 20 张，数量在设置里可调。",
                        "首页三张卡片扇形叠着，右滑下一张、左滑上一张、点中间那张进全屏。",
                        "大图页是一张圆角卡片：左滑上一张、右滑下一张、上滑进待删、下滑退出；手里还有没确认的待删时，退出会先问你一句。",
                        "双击放大，也可以两指捏合，放大后能拖着看细节。",
                        "顶上的细线是大图页的进度条，一眼能看到筛到第几张。"
                    ])

                    block("五个册", [
                        "花间册：相册里所有图片，包含截图。",
                        "碎影集：只有截图，跟花间册各筛各的，互不影响。",
                        "花影染：挑一张套滤镜——黑金、徕卡经典、赛博朋克、iOS 的鲜明系列、系统照片效果，还能导入 .cube LUT；长按预览能对比原图。",
                        "流光卷：只有视频，进全屏直接自动播放。",
                        "岁华簿：分册看浏览了多少、删了多少、腾出多少空间。"
                    ])

                    block("删除是两段式的", [
                        "上滑只是把这张放进入待删队列，相册不会有任何变化。",
                        "一组翻完弹结算页，左边「放弃 · 再来一组」什么都不动，右边「确认删除」才真的删。",
                        "真删之后还能在系统相册「最近删除」里找回 30 天。",
                        "设置里可以开演示模式：走完整流程但永远不碰相册文件。"
                    ])

                    block("其他", [
                        "收藏：全屏页右上角心形，岁华簿里能翻整个收藏夹。",
                        "回到那天：只抽往年今天的照片，一键切换。",
                        "投屏：视频可以直接投给 Apple TV，照片走屏幕镜像。",
                        "详细信息：拍摄时间、分类、尺寸、文件、GPS 位置、相机参数。",
                        "每日提醒：本地通知，不经过任何服务器。"
                    ])

                    block("隐私", [
                        "只在本机读取相册，没有任何网络请求，不上传照片。",
                        "浏览进度、收藏、统计全部存在 App 自己的沙盒里。",
                        "自签安装拿不到 CloudKit 权限，跨设备靠设置里的「导出浏览记录」。"
                    ])
                }
                .padding(20)
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .buttonStyle(.glass)
                }
            }
            // 底下透一点 App 的模糊照片，玻璃卡片才有东西可折射
            .presentationBackground(.black.opacity(0.72))
        }
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
