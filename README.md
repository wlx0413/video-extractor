# 视频提取器

视频提取器是一个多端视频/音频提取工具集合，用于在用户有权保存、学习、备份或获得授权的前提下，分析公开视频链接并下载视频、提取音频或保存图文图片。

## 立即下载

不需要编译源码，直接下载对应安装包：

| 设备 | 推荐下载 | 备用格式 |
| --- | --- | --- |
| macOS · Apple 芯片（M1/M2/M3/M4 等） | [下载 VideoExtractor-macOS-3.0.dmg](https://github.com/wlx0413/video-extractor/releases/download/v3.0.0/VideoExtractor-macOS-3.0.dmg) | [ZIP 压缩包](https://github.com/wlx0413/video-extractor/releases/download/v3.0.0/VideoExtractor-macOS-3.0.zip) |
| macOS · Intel（x86 芯片） | [下载 VideoExtractor-macOS-Intel-3.1.dmg](https://github.com/wlx0413/video-extractor/releases/download/v3.1.0/VideoExtractor-macOS-Intel-3.1.dmg) | - |
| Android | [下载 VideoExtractor-Android-1.0.apk](https://github.com/wlx0413/video-extractor/releases/download/v3.0.0/VideoExtractor-Android-1.0.apk) | - |

- [查看最新版本和发布说明](https://github.com/wlx0413/video-extractor/releases/latest)
- [查看安装教程](INSTALL.md)
- [查看全部历史安装包](%E4%B8%8B%E8%BD%BD%E4%B8%80%E8%A7%88.md)

### 怎么选 macOS 版本

点屏幕左上角苹果菜单 → “关于本机”，看“芯片”一栏：

- 显示 **Apple M1 / M2 / M3 / M4** 等 → 下载 **Apple 芯片版（3.0）**。
- 显示 **Intel** 或 “Intel Core i5 / i7 ...” → 下载 **Intel / x86 版（3.1）**。

架构选错会无法打开或提示“已损坏”，请按自己电脑的芯片选择对应链接。Intel 版要求 macOS 13（Ventura）或更高。

### macOS 安装教程（DMG 拖拽安装）

1. 点击上面自己设备对应的下载链接，下载 `.dmg` 安装镜像。
2. 双击打开 DMG，窗口里会出现 **视频提取器3.1** 应用图标和一个 **Applications** 文件夹。
3. 用鼠标把 **视频提取器3.1** 图标拖到 **Applications** 文件夹上松开，就完成安装了。
4. 到“应用程序”里找到并打开应用。第一次启动若被系统拦截：按住 Control 点击应用图标 → 选择“打开”；若仍被拦截，到“系统设置 → 隐私与安全性”点“仍要打开”。

> macOS 安装包目前未经过 Apple 公证。如果系统拦截，请按 `INSTALL.md` 中的步骤从“隐私与安全性”允许打开。Android 首次安装 APK 时需要允许当前浏览器或文件管理器安装未知来源应用。

## 项目内容

- `VideoExtractorWeb/`：Vite + React 前端和 FastAPI 后端，适合部署到 Netlify + Render。
- `VideoExtractorMac/`：macOS SwiftUI 桌面应用，并包含 iOS 客户端和本地下载服务。
- `VideoExtractorAndroid/`：Android 原生应用源码。
- `视频提取器使用说明书.md`：macOS、Android、iOS 客户端使用说明。

## 合规边界

- 仅处理公开且用户有权保存的内容。
- 不用于绕过 DRM、付费墙、会员、登录、私密内容或地区限制。
- 不读取、上传或窃取浏览器 cookies、登录信息、密码或 token。
- 平台规则可能变化，解析能力属于尽力支持。

## 快速开始

### Web 版

```bash
cd VideoExtractorWeb
npm install
cp .env.example .env
npm run dev
```

后端本地启动方式见 `VideoExtractorWeb/README.md`。

### macOS 版

```bash
cd VideoExtractorMac
open VideoExtractorMac.xcodeproj
```

选择 `VideoExtractorMac` scheme 后运行到 My Mac。

### Android 版

```bash
cd VideoExtractorAndroid
./gradlew assembleDebug
```

如果本地没有 Gradle Wrapper，可使用已安装的 Gradle/Android Studio 打开项目构建。

## 说明

源码、配置示例和使用文档保存在 Git 仓库中；正式安装包保存在 [GitHub Releases](https://github.com/wlx0413/video-extractor/releases)，避免 GitHub 仓库的单文件大小限制。签名密钥、真实环境变量、构建缓存、临时下载文件和运行日志不会公开上传。
