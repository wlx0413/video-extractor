# VideoExtractorServer

这个本地服务给 iOS 版使用。iPhone 端负责界面和文件保存，下载、合并、转码仍在你的 Mac 上通过 `yt-dlp` 和 `ffmpeg` 完成。

## 启动

```bash
python3 VideoExtractorServer/server.py --host 0.0.0.0 --port 8765
```

真机和 Mac 需要在同一个 Wi-Fi 下。iPhone App 里把服务地址填成：

```text
http://你的Mac局域网IP:8765
```

模拟器可以使用：

```text
http://127.0.0.1:8765
```

如果系统防火墙提示是否允许 Python 接收连接，请选择允许。

## 工具路径

服务会按顺序寻找：

1. 环境变量 `YTDLP_PATH` 和 `FFMPEG_PATH`
2. 项目内的 `Tools/yt-dlp/yt-dlp` 和 `Tools/ffmpeg/ffmpeg`
3. 系统 `PATH` 里的 `yt-dlp` 和 `ffmpeg`

只下载你有权保存、备份、学习或获得授权的公开内容。服务不会读取浏览器 cookies、密码或登录状态。
