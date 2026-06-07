# 视频提取器

视频提取器是一个多端视频/音频提取工具集合，用于在用户有权保存、学习、备份或获得授权的前提下，分析公开视频链接并下载视频、提取音频或保存图文图片。

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

公开仓库默认不包含签名密钥、构建缓存、安装包、DMG/ZIP 发布包、临时下载文件和运行日志。需要分发安装包时，建议使用 GitHub Releases 单独上传构建产物。
