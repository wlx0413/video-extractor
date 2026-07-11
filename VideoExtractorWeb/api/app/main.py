from __future__ import annotations

import json
import mimetypes
import os
import re
import selectors
import shutil
import signal
import subprocess
import threading
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, PlainTextResponse
from pydantic import BaseModel, Field
from starlette.background import BackgroundTask


DOWNLOAD_ROOT = Path(os.getenv("DOWNLOAD_ROOT", "/tmp/video-extractor/jobs"))
JOB_TIMEOUT_SECONDS = int(os.getenv("JOB_TIMEOUT_SECONDS", "1800"))
JOB_TTL_SECONDS = int(os.getenv("JOB_TTL_SECONDS", "3600"))
MAX_MEDIA_SIZE = os.getenv("MAX_MEDIA_SIZE", "500M")
MAX_IMAGE_BYTES = int(os.getenv("MAX_IMAGE_BYTES", str(25 * 1024 * 1024)))
MAX_IMAGE_JOB_BYTES = int(os.getenv("MAX_IMAGE_JOB_BYTES", str(250 * 1024 * 1024)))
ALLOWED_ORIGINS = [
    item.strip()
    for item in os.getenv("ALLOWED_ORIGINS", "*").split(",")
    if item.strip()
]

SUPPORTED_HOST_SUFFIXES = (
    "youtube.com",
    "youtu.be",
    "bilibili.com",
    "b23.tv",
    "xiaohongshu.com",
    "xhslink.com",
    "douyin.com",
    "iesdouyin.com",
)

TERMINAL_STATUSES = {"completed", "failed", "cancelled"}
analyze_slots = threading.BoundedSemaphore(value=2)


class AnalyzeRequest(BaseModel):
    url: str = Field(min_length=8, max_length=4096)


class CreateJobRequest(BaseModel):
    url: str = Field(min_length=8, max_length=4096)
    kind: Literal["video", "audio", "images"] = "video"
    mode: Literal["best", "video1080p", "video720p", "video480p", "custom"] = "best"
    audioFormat: Literal["m4a", "mp3", "wav"] = "m4a"
    customFormatID: Optional[str] = Field(default=None, max_length=80)


@dataclass
class DownloadJob:
    job_id: str
    raw_url: str
    kind: str
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    title: str = "等待中"
    status: str = "waiting"
    progress: dict[str, Any] = field(
        default_factory=lambda: {
            "fraction": 0,
            "percentText": "0%",
            "speed": None,
            "eta": None,
        }
    )
    error_message: Optional[str] = None
    output_path: Optional[Path] = None
    file_name: Optional[str] = None
    process: Optional[subprocess.Popen[str]] = None

    @property
    def job_dir(self) -> Path:
        return DOWNLOAD_ROOT / self.job_id

    def touch(self) -> None:
        self.updated_at = time.time()

    def snapshot(self) -> dict[str, Any]:
        return {
            "jobID": self.job_id,
            "status": self.status,
            "title": self.title,
            "kind": self.kind,
            "progress": self.progress,
            "errorMessage": self.error_message,
            "fileName": self.file_name,
            "fileReady": bool(
                self.status == "completed"
                and self.output_path
                and self.output_path.exists()
            ),
            "createdAt": iso_time(self.created_at),
            "updatedAt": iso_time(self.updated_at),
        }


class JobStore:
    def __init__(self) -> None:
        DOWNLOAD_ROOT.mkdir(parents=True, exist_ok=True)
        self.jobs: dict[str, DownloadJob] = {}
        self.lock = threading.RLock()

    def active_count(self) -> int:
        with self.lock:
            return sum(1 for job in self.jobs.values() if job.status not in TERMINAL_STATUSES)

    def get(self, job_id: str) -> DownloadJob:
        with self.lock:
            job = self.jobs.get(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="任务不存在")
        return job

    def create(self, payload: CreateJobRequest) -> DownloadJob:
        with self.lock:
            # 免费云容器资源很小，这里强制同一时间只跑一个任务，避免被朋友同时提交拖垮。
            if self.active_count() > 0:
                raise HTTPException(status_code=409, detail="当前已有任务运行，请稍后。")

            job = DownloadJob(
                job_id=uuid.uuid4().hex,
                raw_url=payload.url,
                kind=payload.kind,
            )
            job.job_dir.mkdir(parents=True, exist_ok=True)
            self.jobs[job.job_id] = job

        thread = threading.Thread(target=run_job, args=(job, payload), daemon=True)
        thread.start()
        return job

    def delete(self, job_id: str) -> None:
        job = self.get(job_id)
        cancel_process(job)
        with self.lock:
            self.jobs.pop(job_id, None)
        remove_path(job.job_dir)

    def cleanup_expired(self) -> None:
        # 下载结果只做临时交付，任务结束超过 TTL 后自动删除，不保留用户数据。
        now = time.time()
        expired: list[str] = []
        with self.lock:
            for job_id, job in self.jobs.items():
                if job.status in TERMINAL_STATUSES and now - job.updated_at > JOB_TTL_SECONDS:
                    expired.append(job_id)

        for job_id in expired:
            try:
                self.delete(job_id)
            except Exception:
                pass


store = JobStore()
app = FastAPI(title="Video Extractor Cloud API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type"],
)


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> PlainTextResponse:
    return PlainTextResponse(str(exc.detail), status_code=exc.status_code)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_: Request, exc: RequestValidationError) -> PlainTextResponse:
    return PlainTextResponse(str(exc.errors()[0]["msg"]), status_code=400)


@app.on_event("startup")
def start_cleanup_thread() -> None:
    # 后台清理线程负责定期删掉已完成/失败/取消的过期任务目录。
    def loop() -> None:
        while True:
            store.cleanup_expired()
            time.sleep(300)

    threading.Thread(target=loop, daemon=True).start()


@app.get("/api/health")
def health() -> dict[str, Any]:
    ytdlp_available = shutil.which("yt-dlp") is not None
    ffmpeg_available = shutil.which("ffmpeg") is not None
    js_runtime_available = shutil.which("deno") is not None
    ok = bool(ytdlp_available and ffmpeg_available and js_runtime_available)
    if not ytdlp_available:
        message = "yt-dlp 不可用"
    elif not ffmpeg_available:
        message = "FFmpeg 不可用"
    elif not js_runtime_available:
        message = "Deno JavaScript 运行时不可用"
    else:
        message = "服务正常"

    return {
        "ok": ok,
        "authConfigured": True,
        "ytdlpAvailable": ytdlp_available,
        "ffmpegAvailable": ffmpeg_available,
        "jsRuntimeAvailable": js_runtime_available,
        "activeJobs": store.active_count(),
        "message": message,
    }


@app.post("/api/analyze")
def analyze(payload: AnalyzeRequest) -> dict[str, Any]:
    raw_url = validate_url(payload.url)
    if not analyze_slots.acquire(blocking=False):
        raise HTTPException(status_code=429, detail="当前分析请求较多，请稍后重试。")
    try:
        return public_metadata(analyze_url(raw_url))
    finally:
        analyze_slots.release()


@app.post("/api/jobs", status_code=201)
def create_download_job(
    payload: CreateJobRequest,
) -> dict[str, str]:
    validate_url(payload.url)
    job = store.create(payload)
    return {"jobID": job.job_id}


@app.get("/api/jobs/{job_id}")
def get_download_job(job_id: str) -> dict[str, Any]:
    return store.get(job_id).snapshot()


@app.get("/api/jobs/{job_id}/file")
def get_download_file(
    job_id: str,
) -> FileResponse:
    job = store.get(job_id)
    if job.status != "completed" or not job.output_path or not job.output_path.exists():
        raise HTTPException(status_code=404, detail="文件尚未准备好或已过期")

    mime_type = mimetypes.guess_type(job.output_path.name)[0] or "application/octet-stream"
    background = BackgroundTask(schedule_delete, job.job_id, 30)
    return FileResponse(
        job.output_path,
        media_type=mime_type,
        filename=job.output_path.name,
        background=background,
    )


@app.delete("/api/jobs/{job_id}")
def delete_download_job(job_id: str) -> dict[str, bool]:
    store.delete(job_id)
    return {"ok": True}


def validate_url(value: str) -> str:
    # 公网服务不接受任意主机，避免被利用访问云端内网。
    raw_url = value.strip()
    parsed = urllib.parse.urlparse(raw_url)
    host = (parsed.hostname or "").lower().rstrip(".")
    if parsed.scheme not in {"http", "https"} or not host:
        raise HTTPException(status_code=400, detail="只支持 http 或 https 链接")
    if not any(host == suffix or host.endswith(f".{suffix}") for suffix in SUPPORTED_HOST_SUFFIXES):
        raise HTTPException(
            status_code=400,
            detail="当前网页版支持 YouTube、Bilibili、小红书和抖音公开链接。",
        )
    return raw_url


def analyze_url(raw_url: str) -> dict[str, Any]:
    # 用 yt-dlp 读取公开元数据；这里不传 cookies，也不读取登录态。
    result = subprocess.run(
        [
            "yt-dlp",
            "--js-runtimes",
            "deno",
            "-J",
            "--no-playlist",
            "--no-warnings",
            raw_url,
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    if result.returncode != 0:
        raise HTTPException(status_code=400, detail=friendly_error(result.stderr or "当前链接无法解析"))

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="当前链接返回的信息无法解析")

    return metadata_from_ytdlp(data, raw_url)


def metadata_from_ytdlp(data: dict[str, Any], raw_url: str) -> dict[str, Any]:
    platform = detect_platform(raw_url)
    thumbnail = data.get("thumbnail")
    image_urls = collect_image_urls(data) if platform == "小红书" else []
    if platform == "小红书" and thumbnail and thumbnail not in image_urls and is_likely_image_url(thumbnail):
        image_urls.insert(0, thumbnail)

    return {
        "id": str(first_non_empty(data.get("id"), uuid.uuid4().hex)),
        "sourceURL": data.get("webpage_url") or raw_url,
        "platform": platform,
        "title": first_non_empty(data.get("title"), f"video_{int(time.time())}"),
        "author": first_non_empty(data.get("uploader"), data.get("channel")),
        "duration": data.get("duration"),
        "thumbnailURL": thumbnail,
        "imageURLs": image_urls[:80],
        "imageCount": min(len(image_urls), 80),
        "formats": [
            mapped
            for item in data.get("formats", [])
            if (mapped := map_format(item)) is not None
        ],
    }


def public_metadata(metadata: dict[str, Any]) -> dict[str, Any]:
    value = dict(metadata)
    value.pop("imageURLs", None)
    return value


def run_job(job: DownloadJob, payload: CreateJobRequest) -> None:
    try:
        # 每个任务会重新分析一次，确保下载时拿到最新标题和图片列表。
        job.status = "analyzing"
        job.touch()
        metadata = analyze_url(job.raw_url)
        job.title = metadata["title"]

        if payload.kind == "images":
            download_images(job, metadata)
        else:
            download_media(job, payload)

        job.status = "completed"
        job.progress = {"fraction": 1, "percentText": "100%", "speed": None, "eta": None}
        job.touch()
    except HTTPException as exc:
        job.status = "failed"
        job.error_message = friendly_error(str(exc.detail))
        job.touch()
        cancel_process(job)
    except Exception as exc:
        job.status = "failed"
        job.error_message = friendly_error(str(exc))
        job.touch()
        cancel_process(job)


def download_media(job: DownloadJob, payload: CreateJobRequest) -> None:
    # 媒体下载由 yt-dlp 执行；视频合并和音频转码会交给容器内的 FFmpeg。
    output_template = f"{job.job_id}_%(title).160s.%(ext)s"
    args = [
        "yt-dlp",
        "--js-runtimes",
        "deno",
        "--newline",
        "--no-playlist",
        "--windows-filenames",
        "--trim-filenames",
        "180",
        "--no-overwrites",
        "--max-filesize",
        MAX_MEDIA_SIZE,
        "--print",
        "after_move:filepath",
        "-P",
        str(job.job_dir),
        "-o",
        output_template,
    ]

    if payload.kind == "audio":
        args.extend([
            "-f",
            "bestaudio/b",
            "-x",
            "--audio-format",
            payload.audioFormat,
            "--audio-quality",
            "0",
        ])
    else:
        args.extend([
            "-f",
            selector_for_mode(payload.mode, payload.customFormatID),
            "--merge-output-format",
            "mp4",
        ])

    args.extend(["--ffmpeg-location", str(Path(shutil.which("ffmpeg") or "/usr/bin/ffmpeg").parent)])
    args.append(job.raw_url)

    job.status = "downloading"
    job.touch()
    process = subprocess.Popen(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    job.process = process
    started_at = time.time()

    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        while True:
            if time.time() - started_at > JOB_TIMEOUT_SECONDS:
                cancel_process(job)
                job.status = "cancelled"
                raise RuntimeError("任务超过 30 分钟，已自动取消")

            # 用 selector 等待输出，避免 readline 阻塞导致超时逻辑失效。
            events = selector.select(timeout=0.5)
            for key, _ in events:
                line = key.fileobj.readline()
                if line:
                    parse_output_line(job, line)

            return_code = process.poll()
            if return_code is not None:
                for line in process.stdout.readlines():
                    parse_output_line(job, line)
                break
    finally:
        selector.close()

    if process.returncode != 0:
        raise RuntimeError(f"下载失败，退出码 {process.returncode}")

    if not job.output_path:
        candidates = sorted(
            job.job_dir.glob(f"{job.job_id}_*"),
            key=lambda item: item.stat().st_mtime,
            reverse=True,
        )
        if candidates:
            job.output_path = candidates[0]
            job.file_name = candidates[0].name

    if not job.output_path:
        raise RuntimeError("下载完成但没有找到输出文件")


def parse_output_line(job: DownloadJob, line: str) -> None:
    progress = progress_from_line(line)
    if progress:
        job.progress = progress
        job.status = "converting" if progress["fraction"] >= 1 else "downloading"
        job.touch()

    candidate = Path(line.strip())
    try:
        candidate.relative_to(job.job_dir)
    except ValueError:
        return

    if candidate.exists() and candidate.is_file():
        job.output_path = candidate
        job.file_name = candidate.name
        job.touch()


def download_images(job: DownloadJob, metadata: dict[str, Any]) -> None:
    # 图文内容会下载为多个图片文件，再压缩成一个 zip 给浏览器下载。
    image_urls = (metadata.get("imageURLs") or [])[:80]
    if not image_urls:
        raise RuntimeError("没有找到可下载图片")

    folder = job.job_dir / f"{safe_name(job.title)}_images"
    folder.mkdir(parents=True, exist_ok=True)
    saved = 0
    total_bytes = 0
    job.status = "downloading"
    started_at = time.time()

    for index, raw_url in enumerate(image_urls, start=1):
        if time.time() - started_at > JOB_TIMEOUT_SECONDS:
            job.status = "cancelled"
            raise RuntimeError("任务超过 30 分钟，已自动取消")

        try:
            request = urllib.request.Request(raw_url, headers={"User-Agent": "VideoExtractor/1.0"})
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(MAX_IMAGE_BYTES + 1)
                content_type = response.headers.get("Content-Type")

            if len(data) > MAX_IMAGE_BYTES:
                raise RuntimeError("单张图片超过云端限制")
            total_bytes += len(data)
            if total_bytes > MAX_IMAGE_JOB_BYTES:
                raise RuntimeError("本次图片总大小超过云端限制")

            ext = image_extension(raw_url, content_type)
            target = folder / f"image_{index:03d}.{ext}"
            target.write_bytes(data)
            saved += 1
        finally:
            fraction = index / len(image_urls)
            job.progress = {
                "fraction": fraction,
                "percentText": f"{round(fraction * 100)}%",
                "speed": None,
                "eta": None,
            }
            job.touch()

    if saved == 0:
        raise RuntimeError("图片下载失败")

    archive_path = job.job_dir / f"{folder.name}.zip"
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for item in sorted(folder.iterdir()):
            if item.is_file():
                archive.write(item, arcname=item.name)

    job.output_path = archive_path
    job.file_name = archive_path.name
    job.touch()


def cancel_process(job: DownloadJob) -> None:
    # yt-dlp 可能会拉起 ffmpeg 子进程，所以优先终止整个进程组。
    process = job.process
    if not process or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except Exception:
        process.terminate()


def schedule_delete(job_id: str, delay_seconds: int) -> None:
    # 文件被下载后延迟删除，给浏览器一点时间完成传输收尾。
    def delayed() -> None:
        time.sleep(delay_seconds)
        try:
            store.delete(job_id)
        except Exception:
            pass

    threading.Thread(target=delayed, daemon=True).start()


def remove_path(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path, ignore_errors=True)
    elif path.exists():
        path.unlink(missing_ok=True)


def selector_for_mode(mode: str, custom_format_id: Optional[str]) -> str:
    if mode == "video1080p":
        return "bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b"
    if mode == "video720p":
        return "bv*[height<=720]+ba/b[height<=720]/bv*+ba/b"
    if mode == "video480p":
        return "bv*[height<=480]+ba/b[height<=480]/bv*+ba/b"
    if mode == "custom" and custom_format_id:
        return f"{custom_format_id}+ba/{custom_format_id}/b"
    return "bv*+ba/b"


def progress_from_line(line: str) -> Optional[dict[str, Any]]:
    if "[download]" not in line:
        return None
    percent_match = re.search(r"(\d+(?:\.\d+)?)%", line)
    if not percent_match:
        return None
    value = float(percent_match.group(1))
    speed_match = re.search(r"at\s+([^\s]+/s)", line)
    eta_match = re.search(r"ETA\s+([0-9:]+)", line)
    return {
        "fraction": max(0, min(value / 100, 1)),
        "percentText": f"{percent_match.group(1)}%",
        "speed": speed_match.group(1) if speed_match else None,
        "eta": eta_match.group(1) if eta_match else None,
    }


def collect_image_urls(value: Any, seen: Optional[set[str]] = None) -> list[str]:
    if seen is None:
        seen = set()

    found: list[str] = []

    def append(raw_url: str) -> None:
        if raw_url not in seen and is_likely_image_url(raw_url):
            seen.add(raw_url)
            found.append(raw_url)

    if isinstance(value, str):
        append(value)
    elif isinstance(value, list):
        for item in value:
            found.extend(collect_image_urls(item, seen))
    elif isinstance(value, dict):
        for item in value.values():
            found.extend(collect_image_urls(item, seen))

    return found


def is_likely_image_url(raw_url: str) -> bool:
    parsed = urllib.parse.urlparse(raw_url)
    if parsed.scheme not in {"http", "https"}:
        return False
    ext = Path(parsed.path).suffix.lower()
    if ext in {".jpg", ".jpeg", ".png", ".webp", ".avif", ".heic", ".heif"}:
        return True
    lowered = raw_url.lower()
    return any(token in lowered for token in ("imageview", "sns-img", "xhscdn", "xhs"))


def map_format(item: dict[str, Any]) -> Optional[dict[str, Any]]:
    format_id = item.get("format_id")
    if not format_id:
        return None
    return {
        "formatID": str(format_id),
        "extensionName": item.get("ext") or "-",
        "resolution": item.get("resolution"),
        "width": item.get("width"),
        "height": item.get("height"),
        "fps": item.get("fps"),
        "fileSize": item.get("filesize"),
        "approxFileSize": item.get("filesize_approx"),
        "videoCodec": item.get("vcodec"),
        "audioCodec": item.get("acodec"),
        "audioBitrate": item.get("abr"),
        "totalBitrate": item.get("tbr"),
        "formatNote": item.get("format_note"),
    }


def detect_platform(raw_url: str) -> str:
    host = urllib.parse.urlparse(raw_url).netloc.lower()
    if "youtube.com" in host or "youtu.be" in host:
        return "YouTube"
    if "bilibili.com" in host or "b23.tv" in host:
        return "Bilibili"
    if "xiaohongshu.com" in host or "xhslink.com" in host:
        return "小红书"
    if "douyin.com" in host or "iesdouyin.com" in host:
        return "抖音"
    return "未知"


def first_non_empty(*values: Any) -> Any:
    for value in values:
        if value:
            return value
    return None


def safe_name(value: str) -> str:
    cleaned = re.sub(r'[\\/:"*?<>|\n\r\t]+', "_", value).strip()
    return (cleaned or f"download_{int(time.time())}")[:90]


def image_extension(raw_url: str, content_type: Optional[str]) -> str:
    guessed = mimetypes.guess_extension(content_type or "") or Path(urllib.parse.urlparse(raw_url).path).suffix
    ext = guessed.lower().lstrip(".")
    if ext in {"jpe", "jpeg"}:
        return "jpg"
    if ext in {"jpg", "png", "webp", "avif", "heic", "heif"}:
        return ext
    return "jpg"


def friendly_error(message: str) -> str:
    text = str(message).strip()
    if not text:
        return "任务失败"
    text = re.sub(r"Deprecated Feature:.*?\n", "", text, flags=re.IGNORECASE)
    if "Unsupported URL" in text:
        return "当前链接暂不支持。"
    if "CERTIFICATE_VERIFY_FAILED" in text:
        return "当前云端环境证书验证失败，请稍后重试或检查容器证书。"
    if any(token in text for token in ("Private video", "login", "Sign in", "cookies")):
        return "该链接需要登录或权限，已停止。"
    return text[:280] + ("..." if len(text) > 280 else "")


def iso_time(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat()
