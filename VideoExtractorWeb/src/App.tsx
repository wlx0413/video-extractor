import {
  Activity,
  CircleAlert,
  CircleCheck,
  Download,
  FileAudio,
  FileVideo,
  ImageDown,
  KeyRound,
  Link,
  LoaderCircle,
  Search,
  Settings2,
  Trash2,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import {
  analyzeURL,
  apiBaseURL,
  checkHealth,
  createJob,
  deleteJob,
  downloadURL,
  getJob,
} from "./api";
import type {
  AnalyzeResponse,
  AudioFormat,
  CreateJobRequest,
  DownloadKind,
  DownloadMode,
  HealthResponse,
  JobResponse,
  MediaFormat,
} from "./types";

const ACCESS_CODE_KEY = "video-extractor-access-code";

const modeLabels: Record<DownloadMode, string> = {
  best: "最佳质量",
  video1080p: "1080p",
  video720p: "720p",
  video480p: "480p",
  custom: "自定义",
};

const kindLabels: Record<DownloadKind, string> = {
  video: "视频",
  audio: "音频",
  images: "图片",
};

const audioFormats: AudioFormat[] = ["m4a", "mp3", "wav"];

function App() {
  const [accessCode, setAccessCode] = useState(() =>
    sessionStorage.getItem(ACCESS_CODE_KEY) || "",
  );
  const [url, setURL] = useState("");
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [metadata, setMetadata] = useState<AnalyzeResponse | null>(null);
  const [selectedKind, setSelectedKind] = useState<DownloadKind>("video");
  const [selectedMode, setSelectedMode] = useState<DownloadMode>("best");
  const [audioFormat, setAudioFormat] = useState<AudioFormat>("m4a");
  const [selectedFormatID, setSelectedFormatID] = useState<string>("");
  const [currentJob, setCurrentJob] = useState<JobResponse | null>(null);
  const [busyLabel, setBusyLabel] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const preferredFormats = useMemo(() => {
    const formats = metadata?.formats ?? [];
    return [...formats]
      .sort(
        (a, b) =>
          (b.height ?? 0) - (a.height ?? 0) ||
          (b.totalBitrate ?? 0) - (a.totalBitrate ?? 0),
      )
      .slice(0, 24);
  }, [metadata]);

  useEffect(() => {
    // 访问码只保存在当前浏览器会话，刷新页面不用重复输入，但不会写入后端。
    sessionStorage.setItem(ACCESS_CODE_KEY, accessCode);
  }, [accessCode]);

  useEffect(() => {
    // 页面打开时先探测云端 API，Render 免费实例冷启动时这里会先显示异常/检查中。
    checkHealth()
      .then(setHealth)
      .catch((error: Error) => {
        setHealth({
          ok: false,
          authConfigured: false,
          ytdlpAvailable: false,
          ffmpegAvailable: false,
          activeJobs: 0,
          message: error.message,
        });
      });
  }, []);

  useEffect(() => {
    if (!currentJob || ["completed", "failed", "cancelled"].includes(currentJob.status)) {
      return;
    }

    // 下载期间每 3 秒轮询一次，既刷新进度，也能让 Render Free 不容易因空闲休眠。
    const timer = window.setInterval(() => {
      getJob(accessCode.trim(), currentJob.jobID)
        .then(setCurrentJob)
        .catch((error: Error) => setNotice(error.message));
    }, 3000);

    return () => window.clearInterval(timer);
  }, [accessCode, currentJob]);

  const canStart = Boolean(accessCode.trim() && url.trim() && !busyLabel);
  const canDownloadImages = Boolean(metadata?.imageCount);

  async function handleAnalyze() {
    // 先分析元数据，再让用户选择视频、音频或图片下载。
    setBusyLabel("分析中");
    setNotice(null);
    setMetadata(null);
    setCurrentJob(null);
    try {
      const result = await analyzeURL(accessCode.trim(), url.trim());
      setMetadata(result);
      setSelectedFormatID(result.formats[0]?.formatID || "");
      if (result.imageCount > 0) {
        setSelectedKind("images");
      }
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "分析失败");
    } finally {
      setBusyLabel(null);
    }
  }

  async function handleCreateJob(kind: DownloadKind = selectedKind) {
    // 创建任务后立即拉取一次状态，后续进度由轮询负责更新。
    setBusyLabel("提交中");
    setNotice(null);
    try {
      const payload: CreateJobRequest = {
        url: url.trim(),
        kind,
        mode: selectedMode,
        audioFormat,
        customFormatID: selectedMode === "custom" ? selectedFormatID : undefined,
      };
      const created = await createJob(accessCode.trim(), payload);
      const job = await getJob(accessCode.trim(), created.jobID);
      setCurrentJob(job);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "提交失败");
    } finally {
      setBusyLabel(null);
    }
  }

  async function handleDeleteJob() {
    if (!currentJob) return;
    // 删除任务会同时请求后端清理临时文件。
    setBusyLabel("清理中");
    setNotice(null);
    try {
      await deleteJob(accessCode.trim(), currentJob.jobID);
      setCurrentJob(null);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "清理失败");
    } finally {
      setBusyLabel(null);
    }
  }

  return (
    <main className="app-shell">
      <section className="workspace">
        <header className="topbar">
          <div>
            <h1>视频提取器在线版</h1>
            <p>{apiBaseURL}</p>
          </div>
          <HealthPill health={health} />
        </header>

        <section className="panel access-panel">
          <label className="field">
            <span>
              <KeyRound size={16} />
              访问码
            </span>
            <input
              value={accessCode}
              onChange={(event) => setAccessCode(event.target.value)}
              type="password"
              autoComplete="current-password"
              placeholder="输入共享访问码"
            />
          </label>
          <label className="field link-field">
            <span>
              <Link size={16} />
              链接
            </span>
            <textarea
              value={url}
              onChange={(event) => setURL(event.target.value)}
              placeholder="https://..."
              rows={3}
            />
          </label>
          <button className="primary-button" disabled={!canStart} onClick={handleAnalyze}>
            {busyLabel === "分析中" ? <LoaderCircle className="spin" /> : <Search />}
            {busyLabel === "分析中" ? "分析中" : "分析链接"}
          </button>
        </section>

        {notice && (
          <div className="notice">
            <CircleAlert size={18} />
            <span>{notice}</span>
          </div>
        )}

        <section className="content-grid">
          <section className="panel media-panel">
            <div className="section-title">
              <Settings2 size={18} />
              <h2>格式</h2>
            </div>

            {metadata ? (
              <>
                <MediaSummary metadata={metadata} />
                <div className="control-grid">
                  <Segmented
                    label="类型"
                    value={selectedKind}
                    options={[
                      ["video", kindLabels.video],
                      ["audio", kindLabels.audio],
                      ["images", kindLabels.images],
                    ]}
                    disabledOptions={canDownloadImages ? [] : ["images"]}
                    onChange={(value) => setSelectedKind(value as DownloadKind)}
                  />
                  <Segmented
                    label="清晰度"
                    value={selectedMode}
                    options={[
                      ["best", modeLabels.best],
                      ["video1080p", modeLabels.video1080p],
                      ["video720p", modeLabels.video720p],
                      ["video480p", modeLabels.video480p],
                      ["custom", modeLabels.custom],
                    ]}
                    disabledOptions={selectedKind === "video" ? [] : ["custom"]}
                    onChange={(value) => setSelectedMode(value as DownloadMode)}
                  />
                  <Segmented
                    label="音频"
                    value={audioFormat}
                    options={audioFormats.map((item) => [item, item])}
                    onChange={(value) => setAudioFormat(value as AudioFormat)}
                  />
                </div>

                <FormatList
                  formats={preferredFormats}
                  selectedFormatID={selectedFormatID}
                  onSelect={setSelectedFormatID}
                />

                <div className="action-row">
                  <button
                    disabled={!canStart || selectedKind !== "images" || !canDownloadImages}
                    onClick={() => handleCreateJob("images")}
                  >
                    <ImageDown />
                    下载图片
                  </button>
                  <button
                    disabled={!canStart}
                    onClick={() => handleCreateJob("audio")}
                  >
                    <FileAudio />
                    仅音频
                  </button>
                  <button
                    className="primary-button"
                    disabled={!canStart}
                    onClick={() => handleCreateJob("video")}
                  >
                    <FileVideo />
                    下载视频
                  </button>
                </div>
              </>
            ) : (
              <EmptyPanel />
            )}
          </section>

          <section className="panel job-panel">
            <div className="section-title">
              <Activity size={18} />
              <h2>任务</h2>
            </div>
            {currentJob ? (
              <JobCard
                job={currentJob}
                accessCode={accessCode.trim()}
                onDelete={handleDeleteJob}
              />
            ) : (
              <div className="blank-state">
                <Download size={30} />
                <span>暂无任务</span>
              </div>
            )}
          </section>
        </section>
      </section>
    </main>
  );
}

function HealthPill({ health }: { health: HealthResponse | null }) {
  if (!health) {
    return (
      <div className="health neutral">
        <LoaderCircle className="spin" size={16} />
        检查中
      </div>
    );
  }

  return (
    <div className={`health ${health.ok ? "ok" : "bad"}`} title={health.message}>
      {health.ok ? <CircleCheck size={16} /> : <CircleAlert size={16} />}
      {health.ok ? "云端就绪" : "云端异常"}
    </div>
  );
}

function MediaSummary({ metadata }: { metadata: AnalyzeResponse }) {
  return (
    <article className="media-summary">
      <div className="thumb">
        {metadata.thumbnailURL ? (
          <img src={metadata.thumbnailURL} alt="" />
        ) : (
          <FileVideo size={30} />
        )}
      </div>
      <div>
        <h3>{metadata.title}</h3>
        <p>
          {metadata.platform}
          {metadata.author ? ` · ${metadata.author}` : ""}
          {metadata.duration ? ` · ${formatDuration(metadata.duration)}` : ""}
          {metadata.imageCount ? ` · ${metadata.imageCount} 张图片` : ""}
        </p>
      </div>
    </article>
  );
}

function Segmented({
  label,
  value,
  options,
  disabledOptions = [],
  onChange,
}: {
  label: string;
  value: string;
  options: string[][];
  disabledOptions?: string[];
  onChange: (value: string) => void;
}) {
  return (
    <div className="segmented-field">
      <span>{label}</span>
      <div className="segmented">
        {options.map(([optionValue, optionLabel]) => (
          <button
            key={optionValue}
            className={value === optionValue ? "selected" : ""}
            disabled={disabledOptions.includes(optionValue)}
            onClick={() => onChange(optionValue)}
          >
            {optionLabel}
          </button>
        ))}
      </div>
    </div>
  );
}

function FormatList({
  formats,
  selectedFormatID,
  onSelect,
}: {
  formats: MediaFormat[];
  selectedFormatID: string;
  onSelect: (value: string) => void;
}) {
  return (
    <div className="format-list">
      <div className="format-head">
        <span>可用格式</span>
        <span>{formats.length} 项</span>
      </div>
      <div className="format-scroll">
        {formats.map((format) => (
          <button
            key={format.formatID}
            className={selectedFormatID === format.formatID ? "format-row selected" : "format-row"}
            onClick={() => onSelect(format.formatID)}
          >
            <span>{format.formatID}</span>
            <span>{format.height ? `${format.height}p` : format.resolution || "-"}</span>
            <span>{format.extensionName}</span>
            <span>{formatKind(format)}</span>
            <span>{formatSize(format)}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function JobCard({
  job,
  accessCode,
  onDelete,
}: {
  job: JobResponse;
  accessCode: string;
  onDelete: () => void;
}) {
  const finished = ["completed", "failed", "cancelled"].includes(job.status);

  return (
    <article className="job-card">
      <div className="job-head">
        <div>
          <h3>{job.title}</h3>
          <p>{kindLabels[job.kind]} · {statusLabel(job.status)}</p>
        </div>
        <button className="icon-button" onClick={onDelete} aria-label="删除任务">
          <Trash2 />
        </button>
      </div>
      <div className="progress-track">
        <div style={{ width: `${Math.round(job.progress.fraction * 100)}%` }} />
      </div>
      <div className="job-meta">
        <span>{job.progress.percentText}</span>
        {job.progress.speed && <span>{job.progress.speed}</span>}
        {job.progress.eta && <span>剩余 {job.progress.eta}</span>}
      </div>
      {job.errorMessage && <div className="inline-error">{job.errorMessage}</div>}
      {job.fileReady && (
        <a className="download-link" href={downloadURL(job.jobID, accessCode)}>
          <Download />
          下载文件
        </a>
      )}
      {!job.fileReady && finished && !job.errorMessage && (
        <div className="inline-error">文件已不可用</div>
      )}
    </article>
  );
}

function EmptyPanel() {
  return (
    <div className="blank-state tall">
      <Search size={32} />
      <span>等待分析</span>
    </div>
  );
}

function formatDuration(seconds: number) {
  const total = Math.round(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const rest = total % 60;
  if (hours) {
    return `${hours}:${String(minutes).padStart(2, "0")}:${String(rest).padStart(2, "0")}`;
  }
  return `${minutes}:${String(rest).padStart(2, "0")}`;
}

function formatKind(format: MediaFormat) {
  const hasVideo = format.videoCodec && format.videoCodec !== "none";
  const hasAudio = format.audioCodec && format.audioCodec !== "none";
  if (hasVideo && hasAudio) return "视频+音频";
  if (hasVideo) return "视频";
  if (hasAudio) return "音频";
  return "未知";
}

function formatSize(format: MediaFormat) {
  const size = format.fileSize || format.approxFileSize;
  if (!size) return "-";
  const mb = size / 1024 / 1024;
  return mb > 1024 ? `${(mb / 1024).toFixed(2)}GB` : `${mb.toFixed(1)}MB`;
}

function statusLabel(status: JobResponse["status"]) {
  const labels: Record<JobResponse["status"], string> = {
    waiting: "等待中",
    analyzing: "分析中",
    downloading: "下载中",
    converting: "转换中",
    completed: "已完成",
    failed: "失败",
    cancelled: "已取消",
  };
  return labels[status];
}

export default App;
