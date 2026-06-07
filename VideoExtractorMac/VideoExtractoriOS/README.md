# VideoExtractoriOS

iOS 版是一个 SwiftUI 客户端。它不能像 macOS 版一样直接在手机里运行项目自带的 `yt-dlp` 和 `ffmpeg` 命令行工具，所以默认走“iPhone App + 本地下载服务”的架构：

- iPhone：粘贴链接、分析、选择视频/音频/图片、查看进度、保存完成文件。
- Mac 本地服务：调用 `yt-dlp` 和 `ffmpeg` 下载、合并、转码。

## 安装到 iPhone 需要准备什么

你不能直接把这里生成的源码无签名安装到 iPhone。iOS App 必须经过 Apple 签名和配置文件。

最简单的个人自用方式：

1. 一台 Mac，并安装完整 Xcode。
2. 一个 Apple ID。免费 Apple ID 可以通过 Xcode 跑到自己的 iPhone 上；如果要 TestFlight、给别人安装、长期分发或上架，需要 Apple Developer Program。
3. iPhone 连接 Mac，并在手机上信任这台电脑。
4. iPhone 开启 Developer Mode。
5. 用 Xcode 打开 `VideoExtractorMac.xcodeproj`，选择 `VideoExtractoriOS` target。
6. 在 `Signing & Capabilities` 里选择你的 Team，并把 Bundle Identifier 改成你自己的唯一值，例如 `com.yourname.VideoExtractoriOS`。
7. 选择你的 iPhone，点击 Run。

如果要给别人安装，推荐走 TestFlight；如果要公开上架，需要 App Store Review。公开视频下载类工具可能会因为版权、平台条款或内容授权问题被审核卡住，个人自用和只处理有权保存的内容会稳得多。

## 使用步骤

1. 在 Mac 上启动本地服务：

   ```bash
   python3 VideoExtractorServer/server.py --host 0.0.0.0 --port 8765
   ```

2. 找到 Mac 的局域网 IP：

   ```bash
   ipconfig getifaddr en0
   ```

3. 在 iPhone App 顶部填入：

   ```text
   http://你的Mac局域网IP:8765
   ```

4. 粘贴链接，先分析，再下载。

完成的文件会保存到 App 沙盒的 Documents/Downloads 目录，并可通过系统分享面板导出到“文件”、AirDrop 或其他 App。
