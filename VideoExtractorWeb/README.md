# 视频提取器在线版

这个目录是“视频提取器”的在线版本：

- `src/`：Vite + React 前端，部署到 Netlify。
- `api/`：FastAPI + Docker 后端，部署到 Render Free，用云端运行 `yt-dlp` 和 `FFmpeg`。

前端不会保存用户历史。后端只保存当前任务的临时文件，文件下载后会延迟删除，完成或失败的任务超过 `JOB_TTL_SECONDS` 也会自动清理。

## 免费版边界

Render Free 会在空闲后休眠，冷启动大约需要几十秒到一分钟。Render Free 的本地文件系统是临时的，服务重启、休眠或重新部署后，任务文件可能丢失。Netlify 和 Render 都有免费额度，超限后服务可能暂停。

当前默认限制：

- 共享访问码：通过 Render 环境变量 `ACCESS_CODE` 设置。
- 单任务超时：30 分钟，`JOB_TIMEOUT_SECONDS=1800`。
- 同时任务数：1 个。
- 临时文件过期：1 小时，`JOB_TTL_SECONDS=3600`。

## 本地开发

### 启动后端

```bash
cd VideoExtractorWeb/api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export ACCESS_CODE=dev-code
export ALLOWED_ORIGINS=http://localhost:5173
uvicorn app.main:app --host 0.0.0.0 --port 8765
```

本地机器需要能找到 `ffmpeg`。如果没有：

```bash
brew install ffmpeg
```

### 启动前端

```bash
cd VideoExtractorWeb
npm install
cp .env.example .env
npm run dev
```

默认前端会调用 `http://localhost:8765`。浏览器打开 `http://localhost:5173`，访问码输入 `dev-code`。

## 部署到 Render

1. 把整个仓库推到 GitHub。
2. 在 Render 新建 Web Service。
3. 选择同一个 GitHub 仓库。
4. 使用 Docker 部署，Root Directory 设置为：

   ```text
   VideoExtractorWeb/api
   ```

5. Dockerfile 路径保持：

   ```text
   ./Dockerfile
   ```

6. Plan 选择 Free。
7. 设置环境变量：

   ```text
   ACCESS_CODE=你的共享访问码
   ALLOWED_ORIGINS=https://你的-netlify-站点.netlify.app
   JOB_TIMEOUT_SECONDS=1800
   JOB_TTL_SECONDS=3600
   ```

8. 部署完成后，复制 Render 服务地址，例如：

   ```text
   https://video-extractor-api.onrender.com
   ```

## 部署到 Netlify

1. 在 Netlify 新建站点并连接同一个 GitHub 仓库。
2. Base directory 设置为：

   ```text
   VideoExtractorWeb
   ```

3. Build command：

   ```text
   npm run build
   ```

4. Publish directory：

   ```text
   VideoExtractorWeb/dist
   ```

   如果 Netlify UI 已经把 Base directory 设置成 `VideoExtractorWeb`，Publish directory 可填：

   ```text
   dist
   ```

5. 设置环境变量：

   ```text
   VITE_API_BASE_URL=https://你的-render-api.onrender.com
   ```

6. 部署完成后，把 Netlify 域名填回 Render 的 `ALLOWED_ORIGINS`，再 redeploy Render。

## API

所有下载相关接口都需要访问码。前端使用 `X-Access-Code` 请求头，文件下载也支持 `?access_code=` 查询参数。

- `GET /api/health`
- `POST /api/analyze`
- `POST /api/jobs`
- `GET /api/jobs/:jobID`
- `GET /api/jobs/:jobID/file`
- `DELETE /api/jobs/:jobID`

## 常见问题

### 打开网页后显示云端异常

检查 `VITE_API_BASE_URL` 是否指向 Render 服务，Render 服务是否已经部署成功，以及 Render 环境变量 `ACCESS_CODE` 是否已设置。

### 分析或下载提示访问码错误

前端输入的访问码必须和 Render 的 `ACCESS_CODE` 完全一致。

### 下载过程中突然文件不可用

免费实例重启、休眠、重新部署或任务过期都会清理临时文件。重新提交任务即可。

### 长视频失败

免费方案默认 30 分钟超时，而且 Render Free 资源有限。可降低清晰度，或后续升级到付费云容器。
