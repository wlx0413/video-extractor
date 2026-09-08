# VideoExtractorMac

一个现代化 macOS SwiftUI 桌面 App，用于在用户有权保存、学习、备份或获得授权的前提下，分析公开视频链接并下载视频或音频。

## 合规边界

- 仅用于公开且用户有权保存的内容。
- 不绕过 DRM、付费墙、会员限制、登录限制、私密视频限制或地区限制。
- 不自动读取、上传或盗取浏览器 cookies、登录信息、密码、token。
- 链接需要登录、会员或权限时，App 会显示友好错误并停止。
- 平台支持为“尽力支持”，网站规则变化时会优雅失败。

## 功能

- 支持输入单个或多个链接，每行一个。
- 自动识别 YouTube、Bilibili、小红书、抖音和未知平台。
- 使用 `yt-dlp -J` 获取标题、作者、时长、缩略图和格式列表。
- 支持最佳质量、1080p、720p、480p 和自定义格式。
- 支持仅音频导出为 `m4a`、`mp3`、`wav`。
- 使用 FFmpeg 合并分离音视频流或转换音频。
- 下载队列显示状态、进度、速度、剩余时间和输出路径。
- 支持跟随系统、浅色模式、深色模式。
- 下载页和设置页都可以自定义保存路径。
- 小红书图文内容会尽力从 `yt-dlp` 公开元数据中提取图片并下载。
- 历史记录保存到本地 JSON。
- 日志保存到 `Logs/app.log`，文件操作保存到 `Logs/file_operations.log`。
- 清理历史和日志轮转不会删除旧文件，会移动到 `要删除的/`。
- YouTube 公开链接遇到临时机器人/出口风控时，会自动尝试默认、`web_embedded`、`web_safari` 三种公开解析策略；Intel x86_64 和 Apple Silicon 使用同一套逻辑。

## 2.0 内置工具版

2.0 版本会把 `yt-dlp` 和 `FFmpeg` 放进 `.app/Contents/Resources/Tools/`，普通用户不需要安装 Homebrew，也不需要手动配置工具路径。

App 默认只需要：

- 网络访问：解析和下载公开视频。
- 写入 App 自己的工作目录：保存日志、历史和默认下载文件。
- 用户主动选择输出目录时，才访问该目录。

App 不会请求管理员权限、全盘访问权限、浏览器 cookies、密码、token 或登录信息。

## 项目结构

```text
VideoExtractorMac/
├── VideoExtractorMac.xcodeproj
├── VideoExtractorMac/
│   ├── App/
│   ├── Views/
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   ├── Resources/
│   └── Utilities/
├── Tools/
│   ├── yt-dlp/
│   └── ffmpeg/
├── Downloads/
├── Temp/
├── Logs/
└── 要删除的/
```

## 运行方式

1. 用 Xcode 打开：

   ```bash
   open VideoExtractorMac.xcodeproj
   ```

2. 选择 `VideoExtractorMac` scheme。
3. 运行到 My Mac。

构建 Intel 版本时，在 Xcode 的 Build Settings 中将 `Architectures` 设为 `x86_64`，然后重新 Archive。发布给用户的 `.app`、DMG 或 ZIP 必须来自这次重新构建；仓库源码更新不会自动修改已经上传的旧安装包。

如果不想使用 Xcode 图形界面，也可以构建：

```bash
xcodebuild -project VideoExtractorMac.xcodeproj -scheme VideoExtractorMac -configuration Debug build
```

## iOS 版本

项目里已经加入 `VideoExtractoriOS` target。iOS 版采用“iPhone App + 本地下载服务”架构：

- iPhone App 负责粘贴链接、分析、选择视频/音频/图片、查看进度和保存文件。
- `VideoExtractorServer/server.py` 在 Mac 上运行，继续调用 `yt-dlp` 和 `ffmpeg` 完成下载、合并和转码。

iOS 不能像 macOS 版一样直接在 App 内运行这里打包的命令行工具，所以真机使用前需要先启动本地服务：

```bash
python3 VideoExtractorServer/server.py --host 0.0.0.0 --port 8765
```

然后在 iPhone App 里填写：

```text
http://你的Mac局域网IP:8765
```

安装到 iPhone 需要完整 Xcode、Apple ID、手机开启 Developer Mode，并在 Xcode 的 `Signing & Capabilities` 里选择自己的 Team。个人自用可以通过 Xcode 直接 Run 到自己的设备；TestFlight、给别人安装或上架需要加入 Apple Developer Program。

## 配置 yt-dlp 和 FFmpeg

推荐使用 Homebrew 安装：

```bash
brew install yt-dlp ffmpeg
```

常见路径：

```text
/opt/homebrew/bin/yt-dlp
/opt/homebrew/bin/ffmpeg
```

App 会按以下顺序解析工具：

1. 设置页手动选择的自定义路径。
2. App bundle 内置的 `Tools/yt-dlp/yt-dlp` 和 `Tools/ffmpeg/ffmpeg`。
3. 当前项目里的 `Tools/yt-dlp/yt-dlp` 和 `Tools/ffmpeg/ffmpeg`。
4. 常见 Homebrew 路径 `/opt/homebrew/bin`、`/usr/local/bin`。

## 文件安全策略

- App 默认只操作当前项目或 App 自己创建的工作目录，以及用户在设置页明确选择的输出目录。
- 不使用 shell 字符串拼接，所有命令参数都通过 `Process.arguments` 传入。
- URL 只允许 `http` 和 `https`。
- 下载文件名会做非法字符清理。
- 文件名冲突时自动添加时间戳或短 UUID。
- 历史清理会把旧 `history.json` 移动到 `要删除的/`。
- 日志过大时，旧日志会移动到 `要删除的/`。
- 每次移动文件都会写入 `Logs/file_operations.log`。

## 打包成 .app

开发验证完成后：

1. 在 Xcode 中选择 `Product > Archive`。
2. 使用 `Distribute App` 导出 Developer ID 或本地 App。
3. 如果要内置工具，把可执行文件放到：

   ```text
   Tools/yt-dlp/yt-dlp
   Tools/ffmpeg/ffmpeg
   ```

4. 确认两个工具有执行权限：

   ```bash
   chmod +x Tools/yt-dlp/yt-dlp Tools/ffmpeg/ffmpeg
   ```

5. 如果要分发给其他用户，需要处理 Developer ID 签名、公证，以及第三方工具的许可证说明。

## 后续建议

- 给下载队列增加暂停和恢复能力。
- 增加完整的书签权限保存，用于 App Sandbox 下访问用户选择的目录。
- 为工具版本检查和错误映射增加单元测试。
- 增加 App 图标和下载完成通知。
