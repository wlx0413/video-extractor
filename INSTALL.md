# 下载、安装与发布说明

## 普通用户：怎么下载

打开仓库首页后，在“立即下载”表格中选择自己的平台。也可以直接打开：

- 最新版本：https://github.com/wlx0413/video-extractor/releases/latest
- 所有版本：https://github.com/wlx0413/video-extractor/releases

不要点击 GitHub 的 `Source code (zip)` 作为安装包。它只是源码快照，不能直接安装应用。

macOS 用户请先判断自己的芯片类型，**架构选错会导致无法安装**：

| 你的 Mac | 下载哪一个 |
| --- | --- |
| Apple 芯片（关于本机里显示 Apple M1 / M2 / M3 / M4 等） | `VideoExtractor-macOS-3.0.dmg` |
| Intel / x86 芯片（关于本机里显示 Intel Core i5 / i7 等） | `VideoExtractor-macOS-Intel-3.1.dmg` |

> 查看方法：点屏幕左上角苹果菜单 → “关于本机”，在“芯片”或“处理器”一栏即可看到。

## macOS 安装

以 Intel / x86 版（`VideoExtractor-macOS-Intel-3.1.dmg`）为例：

1. 下载 DMG 后，双击打开安装镜像。
2. 打开后窗口里有 **视频提取器3.1** 应用图标和一个 **Applications** 文件夹。
3. 把 **视频提取器3.1** 图标拖到 **Applications** 文件夹上松开，即完成安装。
4. 到“应用程序”中打开应用。第一次启动时如果被系统拦截，在 Finder 的“应用程序”中按住 Control 点击应用，然后选择“打开”。
5. 如果仍被系统拦截，打开“系统设置 > 隐私与安全性”，找到拦截提示并选择“仍要打开”。

Apple 芯片用户下载 `VideoExtractor-macOS-3.0.dmg`，打开方式与上面完全相同，把“视频提取器”拖到“应用程序”即可。

也可以下载 ZIP，解压后把应用拖到“应用程序”。当前 macOS 包采用本地签名，未经过 Apple 公证，因此首次打开会出现安全提示。

## Android 安装

1. 下载 `VideoExtractor-Android-1.0.apk`。
2. 打开下载完成的 APK。
3. Android 提示时，允许当前浏览器或文件管理器“安装未知应用”。
4. 完成安装后，可以关闭该来源的安装权限。

发布页只提供已签名 APK。名称含 `unsigned` 或 `aligned` 的构建中间文件不要公开分发。

## 维护者：怎么上传新版本

安装包不要提交到普通 Git 历史。GitHub 对普通仓库文件有大小限制，Android APK 也已超过该限制；正式包应作为 GitHub Release 附件上传。

### 1. 上传源码和文档

```bash
git status
git add README.md INSTALL.md 下载一览.md
git commit -m "Add release downloads and installation guide"
git push
```

只提交源码、文档和配置示例。不要上传 `.env`、`*.jks`、`*.keystore`、`*.p12`、构建缓存、运行日志或临时下载目录。

### 2. 登录 GitHub CLI

```bash
gh auth login -h github.com
gh auth status
```

### 3. 创建 Release 并上传安装包

下面以 `v3.1.0` 为例，先把文件整理成清晰的英文文件名，再执行：

```bash
gh release create v3.1.0 \
  VideoExtractor-macOS-3.1.dmg \
  VideoExtractor-macOS-3.1.zip \
  VideoExtractor-Android-1.1.apk \
  --title "视频提取器 3.1" \
  --notes "本版本的主要更新内容"
```

如果 Release 已存在，可以补传附件：

```bash
gh release upload v3.1.0 VideoExtractor-macOS-3.1.dmg
```

### 4. 更新首页下载链接

把 `README.md` 和 `下载一览.md` 中的版本号、标签和附件文件名改成新版本，然后提交并推送。直接下载链接格式为：

```text
https://github.com/wlx0413/video-extractor/releases/download/标签名/附件文件名
```

### 5. 发布前检查

- macOS ZIP 能正常解压，DMG 能正常挂载，应用能启动。
- Android 上传的是已签名 APK，不是 `app-release-unsigned.apk`。
- Release 附件名称与 README 链接完全一致，包括大小写。
- 在未登录 GitHub 的浏览器窗口中测试所有下载链接。
