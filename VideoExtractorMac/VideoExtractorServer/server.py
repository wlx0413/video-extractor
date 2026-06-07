#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import shutil
import subprocess
import threading
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_DOWNLOADS_DIR = ROOT_DIR / "Downloads" / "iOSServer"


def find_tool(name: str, env_name: str, project_relative: tuple[str, ...]) -> str | None:
    env_value = os.environ.get(env_name)
    if env_value and Path(env_value).exists():
        return env_value

    bundled = ROOT_DIR.joinpath(*project_relative)
    if bundled.exists():
        return str(bundled)

    return shutil.which(name)


def detect_platform(raw_url: str) -> str:
    host = urllib.parse.urlparse(raw_url).netloc.lower()
    if "youtube.com" in host or "youtu.be" in host:
        return "youtube"
    if "bilibili.com" in host or "b23.tv" in host:
        return "bilibili"
    if "xiaohongshu.com" in host or "xhslink.com" in host:
        return "xiaohongshu"
    if "douyin.com" in host or "iesdouyin.com" in host:
        return "douyin"
    return "unknown"


def first_non_empty(*values: Any) -> Any:
    for value in values:
        if value:
            return value
    return None


def map_format(item: dict[str, Any]) -> dict[str, Any] | None:
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


def is_likely_image_url(raw_url: str) -> bool:
    parsed = urllib.parse.urlparse(raw_url)
    if parsed.scheme not in {"http", "https"}:
        return False

    ext = Path(parsed.path).suffix.lower()
    if ext in {".jpg", ".jpeg", ".png", ".webp", ".avif", ".heic"}:
        return True

    lowered = raw_url.lower()
    return any(token in lowered for token in ("imageview", "sns-img", "xhscdn", "xhs"))


def collect_image_urls(value: Any, seen: set[str] | None = None) -> list[str]:
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


def metadata_from_ytdlp(data: dict[str, Any], raw_url: str) -> dict[str, Any]:
    image_urls = collect_image_urls(data)
    thumbnail = data.get("thumbnail")
    if thumbnail and thumbnail not in image_urls and is_likely_image_url(thumbnail):
        image_urls.insert(0, thumbnail)

    formats = [mapped for item in data.get("formats", []) if (mapped := map_format(item))]
    title = first_non_empty(data.get("title"), f"video_{int(time.time())}")
    metadata_id = str(first_non_empty(data.get("id"), uuid.uuid4()))

    return {
        "id": metadata_id,
        "sourceURL": data.get("webpage_url") or raw_url,
        "platform": detect_platform(raw_url),
        "title": title,
        "author": first_non_empty(data.get("uploader"), data.get("channel")),
        "duration": data.get("duration"),
        "thumbnailURL": thumbnail,
        "imageURLs": image_urls[:80],
        "formats": formats,
    }


def progress_from_line(line: str) -> dict[str, Any] | None:
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


def safe_name(value: str) -> str:
    cleaned = re.sub(r'[\\/:"*?<>|]+', "_", value).strip()
    return cleaned or f"download_{int(time.time())}"


def selector_for_mode(mode: str, custom_format_id: str | None) -> str:
    if mode == "video1080p":
        return "bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b"
    if mode == "video720p":
        return "bv*[height<=720]+ba/b[height<=720]/bv*+ba/b"
    if mode == "video480p":
        return "bv*[height<=480]+ba/b[height<=480]/bv*+ba/b"
    if mode == "audioOnly":
        return "bestaudio/b"
    if mode == "custom" and custom_format_id:
        return f"{custom_format_id}+ba/{custom_format_id}/b"
    return "bv*+ba/b"


@dataclass
class DownloadJob:
    job_id: str
    raw_url: str
    kind: str
    title: str = "等待中"
    status: str = "waiting"
    progress: dict[str, Any] = field(default_factory=lambda: {
        "fraction": 0,
        "percentText": "0%",
        "speed": None,
        "eta": None,
    })
    error_message: str | None = None
    output_path: Path | None = None
    file_name: str | None = None

    def snapshot(self) -> dict[str, Any]:
        return {
            "jobID": self.job_id,
            "status": self.status,
            "title": self.title,
            "progress": self.progress,
            "errorMessage": self.error_message,
            "fileName": self.file_name,
        }


class VideoExtractorState:
    def __init__(self, downloads_dir: Path) -> None:
        self.downloads_dir = downloads_dir
        self.downloads_dir.mkdir(parents=True, exist_ok=True)
        self.ytdlp = find_tool("yt-dlp", "YTDLP_PATH", ("Tools", "yt-dlp", "yt-dlp"))
        self.ffmpeg = find_tool("ffmpeg", "FFMPEG_PATH", ("Tools", "ffmpeg", "ffmpeg"))
        self.jobs: dict[str, DownloadJob] = {}
        self.lock = threading.RLock()

    def health(self) -> dict[str, Any]:
        ytdlp_ok = bool(self.ytdlp and Path(self.ytdlp).exists())
        ffmpeg_ok = bool(self.ffmpeg and Path(self.ffmpeg).exists())
        message = "服务正常" if ytdlp_ok else "找不到 yt-dlp"
        if ytdlp_ok and not ffmpeg_ok:
            message = "服务正常，未找到 FFmpeg 时部分合并/转码可能失败"

        return {
            "ok": ytdlp_ok,
            "ytdlpAvailable": ytdlp_ok,
            "ffmpegAvailable": ffmpeg_ok,
            "message": message,
        }

    def analyze(self, raw_url: str) -> dict[str, Any]:
        if not self.ytdlp:
            raise RuntimeError("yt-dlp 不可用")

        result = subprocess.run(
            [self.ytdlp, "-J", "--no-playlist", raw_url],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "当前链接无法解析")

        return metadata_from_ytdlp(json.loads(result.stdout), raw_url)

    def create_job(self, payload: dict[str, Any]) -> DownloadJob:
        raw_url = payload["url"]
        job = DownloadJob(job_id=uuid.uuid4().hex, raw_url=raw_url, kind=payload.get("kind", "video"))
        with self.lock:
            self.jobs[job.job_id] = job

        thread = threading.Thread(target=self._run_job, args=(job, payload), daemon=True)
        thread.start()
        return job

    def get_job(self, job_id: str) -> DownloadJob | None:
        with self.lock:
            return self.jobs.get(job_id)

    def _run_job(self, job: DownloadJob, payload: dict[str, Any]) -> None:
        try:
            job.status = "analyzing"
            metadata = self.analyze(job.raw_url)
            job.title = metadata["title"]

            if job.kind == "images":
                self._download_images(job, metadata)
            else:
                self._download_media(job, payload)

            job.status = "completed"
            job.progress = {"fraction": 1, "percentText": "100%", "speed": None, "eta": None}
        except Exception as exc:
            job.status = "failed"
            job.error_message = str(exc)

    def _download_media(self, job: DownloadJob, payload: dict[str, Any]) -> None:
        if not self.ytdlp:
            raise RuntimeError("yt-dlp 不可用")

        job.status = "downloading"
        output_template = f"{job.job_id}_%(title).160s.%(ext)s"
        args = [
            self.ytdlp,
            "--newline",
            "--no-playlist",
            "--windows-filenames",
            "--trim-filenames",
            "180",
            "--no-overwrites",
            "--print",
            "after_move:filepath",
            "-P",
            str(self.downloads_dir),
            "-o",
            output_template,
        ]

        if job.kind == "audio":
            args.extend([
                "-f",
                "bestaudio/b",
                "-x",
                "--audio-format",
                payload.get("audioFormat", "m4a"),
                "--audio-quality",
                "0",
            ])
        else:
            args.extend([
                "-f",
                selector_for_mode(payload.get("mode", "best"), payload.get("customFormatID")),
                "--merge-output-format",
                "mp4",
            ])

        if self.ffmpeg:
            args.extend(["--ffmpeg-location", str(Path(self.ffmpeg).parent)])

        args.append(job.raw_url)

        process = subprocess.Popen(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        for line in process.stdout:
            progress = progress_from_line(line)
            if progress:
                job.progress = progress

            candidate = Path(line.strip())
            if str(candidate).startswith(str(self.downloads_dir)) and candidate.exists():
                job.output_path = candidate
                job.file_name = candidate.name

        return_code = process.wait()
        if return_code != 0:
            raise RuntimeError(f"下载失败，退出码 {return_code}")

        if not job.output_path:
            candidates = sorted(
                self.downloads_dir.glob(f"{job.job_id}_*"),
                key=lambda item: item.stat().st_mtime,
                reverse=True,
            )
            if candidates:
                job.output_path = candidates[0]
                job.file_name = candidates[0].name

        if not job.output_path:
            raise RuntimeError("下载完成但没有找到输出文件")

    def _download_images(self, job: DownloadJob, metadata: dict[str, Any]) -> None:
        image_urls = metadata.get("imageURLs") or []
        if not image_urls:
            raise RuntimeError("没有找到可下载图片")

        folder = self.downloads_dir / f"{job.job_id}_{safe_name(job.title)}_images"
        folder.mkdir(parents=True, exist_ok=True)
        saved = 0

        for index, raw_url in enumerate(image_urls, start=1):
            try:
                request = urllib.request.Request(raw_url, headers={"User-Agent": "VideoExtractor/1.0"})
                with urllib.request.urlopen(request, timeout=30) as response:
                    data = response.read()
                    content_type = response.headers.get("Content-Type")
                ext = mimetypes.guess_extension(content_type or "") or Path(urllib.parse.urlparse(raw_url).path).suffix
                if ext.lower() in {".jpe", ".jpeg"}:
                    ext = ".jpg"
                if not ext:
                    ext = ".jpg"
                target = folder / f"image_{index:03d}{ext}"
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

        if saved == 0:
            raise RuntimeError("图片下载失败")

        archive_path = self.downloads_dir / f"{folder.name}.zip"
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for item in sorted(folder.iterdir()):
                if item.is_file():
                    archive.write(item, arcname=item.name)

        job.output_path = archive_path
        job.file_name = archive_path.name


class VideoExtractorHandler(BaseHTTPRequestHandler):
    server_version = "VideoExtractorServer/1.0"

    @property
    def state(self) -> VideoExtractorState:
        return self.server.state  # type: ignore[attr-defined]

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self._cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/health":
            self._send_json(self.state.health())
            return

        match = re.fullmatch(r"/api/downloads/([a-f0-9]+)(/file)?", path)
        if match:
            job = self.state.get_job(match.group(1))
            if not job:
                self._send_error(HTTPStatus.NOT_FOUND, "任务不存在")
                return

            if match.group(2):
                self._send_file(job)
            else:
                self._send_json(job.snapshot())
            return

        self._send_error(HTTPStatus.NOT_FOUND, "接口不存在")

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        try:
            payload = self._read_json()
            if path == "/api/analyze":
                raw_url = payload.get("url")
                if not raw_url:
                    self._send_error(HTTPStatus.BAD_REQUEST, "缺少 url")
                    return
                self._send_json(self.state.analyze(raw_url))
                return

            if path == "/api/downloads":
                raw_url = payload.get("url")
                if not raw_url:
                    self._send_error(HTTPStatus.BAD_REQUEST, "缺少 url")
                    return
                job = self.state.create_job(payload)
                self._send_json({"jobID": job.job_id}, HTTPStatus.CREATED)
                return

            self._send_error(HTTPStatus.NOT_FOUND, "接口不存在")
        except Exception as exc:
            self._send_error(HTTPStatus.BAD_REQUEST, str(exc))

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(length)
        return json.loads(data.decode("utf-8")) if data else {}

    def _send_json(self, value: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self._cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, job: DownloadJob) -> None:
        if job.status != "completed" or not job.output_path or not job.output_path.exists():
            self._send_error(HTTPStatus.NOT_FOUND, "文件尚未准备好")
            return

        data = job.output_path.read_bytes()
        mime_type = mimetypes.guess_type(job.output_path.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self._cors_headers()
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Disposition", f'attachment; filename="{job.output_path.name}"')
        self.end_headers()
        self.wfile.write(data)

    def _send_error(self, status: HTTPStatus, message: str) -> None:
        data = message.encode("utf-8")
        self.send_response(status)
        self._cors_headers()
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} - {fmt % args}")


class VideoExtractorHTTPServer(ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], handler_class: type[BaseHTTPRequestHandler], state: VideoExtractorState) -> None:
        super().__init__(server_address, handler_class)
        self.state = state


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Video Extractor local API server for the iOS app.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--downloads", type=Path, default=DEFAULT_DOWNLOADS_DIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    state = VideoExtractorState(args.downloads)
    server = VideoExtractorHTTPServer((args.host, args.port), VideoExtractorHandler, state)
    print(f"Video Extractor server: http://{args.host}:{args.port}")
    print(f"Downloads: {state.downloads_dir}")
    print(f"yt-dlp: {state.ytdlp or 'not found'}")
    print(f"ffmpeg: {state.ffmpeg or 'not found'}")
    server.serve_forever()


if __name__ == "__main__":
    main()
