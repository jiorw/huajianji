# 花间集

随机翻相册的 iOS App。每次从相册里随机发 **20 张**，一张张筛：**下滑删除、右滑下一张**。界面按参考图复刻，材质用苹果 iOS 26 的 **Liquid Glass**。

## 界面

| 位置 | 内容 |
| --- | --- |
| 左上胶囊 | 当前相册名 + 剩余数量徽标，点胶囊选相册 |
| 中间 | 三张扇形卡片堆（左后 / 右后 / 正中），白描边大圆角 |
| 背景 | 当前照片放大高斯模糊 + 暗色渐变，玻璃材质折射的就是它 |
| 底部 Dock | 照片 / 视频 / 统计 三个玻璃胶囊，静止时融成一条 |

交互：

- **下滑** → 这张进入待删队列，卡片飞出屏幕，底部弹「已移入待删 · 撤销」
- **右滑** → 保留并看下一张
- 20 张筛完自动发下一批
- 视频卡片点一下可以直接播放

## 删除是两段式的

下滑**不会**真的删照片，只是标记。要统计页点「立即删除 N 张」才会调用 PhotoKit 删除，删完还能在系统相册「最近删除」里找回 30 天。进度（哪些看过、哪些待删）存在本机 `UserDefaults`，App 没有任何网络请求。

## 环境要求

- **手机**：iOS 26 及以上（Liquid Glass 是 iOS 26 才有的材质，低于 26 装不上）。
- **打包**：Xcode 26 / iOS 26 SDK。Windows 本机出不了 IPA，走下面的云构建。

## 出包（不需要 Mac）

1. 在 GitHub 建一个仓库，把这个目录整个推上去：

   ```bash
   git init
   git add .
   git commit -m "花间集"
   git remote add origin https://github.com/你的用户名/你的仓库.git
   git push -u origin main
   ```

2. 打开仓库的 **Actions** 页，等 `构建无签名 IPA` 跑完（首次约 5–8 分钟）。
3. 点进那次运行，在 **Artifacts** 里下载 `HuajianJi-unsigned-ipa`，解压得到 `huajianji-1.0.ipa`。

流水线失败时先看第一步「确认工具链版本」的输出：runner 已钉在 `macos-26`（默认 Xcode 26.6 + iOS 26 SDK）。如果哪天这个 label 被 GitHub 下线，换成 `macos-latest` 前先确认它的默认 Xcode ≥ 26。

## 自签安装

把 `huajianji-1.0.ipa` 丢进你手机上/电脑上的自签工具（esign、各类自签助手都一样）：

1. 签名时如果提示 bundle id 冲突，改成你自己的（比如 `com.你名字.huajianji`）——改 bundle id 不影响运行。
2. 用你自己的证书 + 描述文件签，签完装到手机。
3. 免费 Apple ID 签的话 7 天过期，过期后重新签一次即可，进度不会丢（记录在 App 沙盒里，重装同 bundle id 会保留）。

## 有 Mac 的话本地出包

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -project HuajianJi.xcodeproj -target HuajianJi \
  -configuration Release -sdk iphoneos SYMROOT=$(pwd)/build_out \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
rm -rf Payload && mkdir Payload
cp -R build_out/Release-iphoneos/HuajianJi.app Payload/
ditto -c -k --keepParent Payload HuajianJi-unsigned.ipa
```

## 目录

```
project.yml                 XcodeGen 配置，xcodegen generate 生成 .xcodeproj
Support/Info.plist          相册权限文案等
Sources/App/                @main 入口 + 图片加载 + 模糊背景 + 视频预览
Sources/Model/PhotoStore.swift   随机发牌 / 标记 / 批量删除 / 进度持久化
Sources/Views/              卡片堆、Dock、统计、相册选择
Assets.xcassets/            App 图标
```
