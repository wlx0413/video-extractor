import {
  Activity,
  Captions,
  CircleAlert,
  CircleCheck,
  Clock3,
  Download,
  FileAudio,
  FileText,
  FileVideo,
  Folder,
  ImageDown,
  Link,
  List,
  LoaderCircle,
  Search,
  Settings2,
  SlidersHorizontal,
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

type AppSection = "downloads" | "history" | "settings" | "logs";
type QueueStatus = JobResponse["status"] | "ready";

interface HistoryEntry {
  id: string;
  title: string;
  kind: DownloadKind;
  status: QueueStatus;
  createdAt: string;
}

interface LogEntry {
  id: string;
  message: string;
  level: "info" | "error";
  time: string;
}

const sections: Array<{
  id: AppSection;
  title: string;
  icon: typeof Download;
}> = [
  { id: "downloads", title: "下载", icon: Download },
  { id: "history", title: "历史", icon: Clock3 },
  { id: "settings", title: "设置", icon: Settings2 },
  { id: "logs", title: "日志", icon: FileText },
];

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
const terminalStatuses = new Set(["completed", "failed", "cancelled"]);

function App() {
  const [selectedSection, setSelectedSection] = useState<AppSection>("downloads");
  const [url, setURL] = useState("");
  const [analyzedURL, setAnalyzedURL] = useState("");
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [metadata, setMetadata] = useState<AnalyzeResponse | null>(null);
  const [selectedKind, setSelectedKind] = useState<DownloadKind>("video");
  const [selectedMode, setSelectedMode] = useState<DownloadMode>("best");
  const [audioFormat, setAudioFormat] = useState<AudioFormat>("m4a");
  const [selectedFormatID, setSelectedFormatID] = useState<string>("");
  const [currentJob, setCurrentJob] = useState<JobResponse | null>(null);
  const [busyLabel, setBusyLabel] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [history, setHistory] = useState<HistoryEntry[]>(loadHistory);
  const [logs, setLogs] = useState<LogEntry[]>([]);

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

  const queueCount = currentJob || metadata ? 1 : 0;
  const hasActiveJob = Boolean(currentJob && !terminalStatuses.has(currentJob.status));
  const canAnalyze = Boolean(firstURL(url) && !busyLabel && !hasActiveJob);
  const canCreateJob = Boolean(metadata && analyzedURL && !busyLabel && !hasActiveJob);
  const canDownloadImages = Boolean(metadata?.imageCount);
  const isYouTube = Boolean(metadata?.platform.toLowerCase().includes("youtube"));

  function appendLog(message: string, level: LogEntry["level"] = "info") {
    setLogs((items) => [
      {
        id: crypto.randomUUID(),
        message,
        level,
        time: new Date().toLocaleTimeString(),
      },
      ...items,
    ].slice(0, 60));
  }

  useEffect(() => {
    checkHealth()
      .then((result) => {
        setHealth(result);
        appendLog(`云端检查：${result.message}`, result.ok ? "info" : "error");
      })
      .catch((error: Error) => {
        const failedHealth: HealthResponse = {
          ok: false,
          authConfigured: false,
          ytdlpAvailable: false,
          ffmpegAvailable: false,
          activeJobs: 0,
          message: error.message,
        };
        setHealth(failedHealth);
        appendLog(`云端检查失败：${error.message}`, "error");
      });
  }, []);

  useEffect(() => {
    localStorage.setItem("video-extractor-history", JSON.stringify(history.slice(0, 100)));
  }, [history]);

  useEffect(() => {
    if (!currentJob || ["completed", "failed", "cancelled"].includes(currentJob.status)) {
      return;
    }

    const timer = window.setInterval(() => {
      getJob(currentJob.jobID)
        .then((job) => {
          setCurrentJob(job);
          if (job.status === "completed") {
            appendLog(`任务完成：${job.title}`);
            setHistory((items) => [
              historyFromJob(job),
              ...items.filter((item) => item.id !== job.jobID),
            ]);
          }
          if (job.status === "failed" || job.status === "cancelled") {
            appendLog(`任务${statusLabel(job.status)}：${job.title}`, "error");
            setHistory((items) => [
              historyFromJob(job),
              ...items.filter((item) => item.id !== job.jobID),
            ]);
          }
        })
        .catch((error: Error) => {
          setNotice(error.message);
          appendLog(error.message, "error");
        });
    }, 3000);

    return () => window.clearInterval(timer);
  }, [currentJob]);

  async function handleAnalyze() {
    const submittedURL = firstURL(url);
    if (!submittedURL || hasActiveJob) {
      return;
    }

    setBusyLabel("分析中");
    setNotice(null);
    setMetadata(null);
    setAnalyzedURL("");
    try {
      const result = await analyzeURL(submittedURL);
      setMetadata(result);
      setAnalyzedURL(submittedURL);
      setSelectedFormatID(result.formats[0]?.formatID || "");
      setSelectedKind(result.imageCount > 0 ? "images" : "video");
      appendLog(`分析完成：${result.title}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "分析失败";
      setNotice(message);
      appendLog(message, "error");
    } finally {
      setBusyLabel(null);
    }
  }

  async function handleCreateJob(kind: DownloadKind = selectedKind) {
    if (!analyzedURL || !metadata || hasActiveJob) {
      setNotice("请先分析链接，再选择下载方式。");
      return;
    }

    setBusyLabel("提交中");
    setNotice(null);
    try {
      const payload: CreateJobRequest = {
        url: analyzedURL,
        kind,
        mode: selectedMode,
        audioFormat,
        customFormatID: selectedMode === "custom" ? selectedFormatID : undefined,
      };
      const created = await createJob(payload);
      const job = await getJob(created.jobID);
      setCurrentJob(job);
      appendLog(`已加入下载队列：${metadata?.title || job.title}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "提交失败";
      setNotice(message);
      appendLog(message, "error");
    } finally {
      setBusyLabel(null);
    }
  }

  async function handleDeleteJob() {
    if (!currentJob) {
      setMetadata(null);
      return;
    }

    setBusyLabel("清理中");
    setNotice(null);
    try {
      await deleteJob(currentJob.jobID);
      appendLog(`已清理任务：${currentJob.title}`);
      setCurrentJob(null);
      setMetadata(null);
      setAnalyzedURL("");
    } catch (error) {
      const message = error instanceof Error ? error.message : "清理失败";
      setNotice(message);
      appendLog(message, "error");
    } finally {
      setBusyLabel(null);
    }
  }

  return (
    <main className="app-shell">
      <aside className="sidebar" aria-label="主导航">
        <div className="sidebar-title">视频提取器</div>
        <nav className="sidebar-list">
          {sections.map((section) => {
            const Icon = section.icon;
            return (
              <button
                key={section.id}
                className={selectedSection === section.id ? "sidebar-item selected" : "sidebar-item"}
                onClick={() => setSelectedSection(section.id)}
              >
                <Icon size={17} />
                {section.title}
              </button>
            );
          })}
        </nav>
      </aside>

      <section className="detail-pane">
        {selectedSection === "downloads" && (
          <DownloadsView
            audioFormat={audioFormat}
            busyLabel={busyLabel}
            canAnalyze={canAnalyze}
            canCreateJob={canCreateJob}
            canDownloadImages={canDownloadImages}
            currentJob={currentJob}
            health={health}
            isYouTube={isYouTube}
            metadata={metadata}
            notice={notice}
            preferredFormats={preferredFormats}
            queueCount={queueCount}
            selectedFormatID={selectedFormatID}
            selectedKind={selectedKind}
            selectedMode={selectedMode}
            url={url}
            onAnalyze={handleAnalyze}
            onCreateJob={handleCreateJob}
            onDeleteJob={handleDeleteJob}
            onSelectFormat={setSelectedFormatID}
            onSetAudioFormat={setAudioFormat}
            onSetKind={setSelectedKind}
            onSetMode={setSelectedMode}
            onSetURL={setURL}
          />
        )}
        {selectedSection === "history" && <HistoryView items={history} />}
        {selectedSection === "settings" && <SettingsView health={health} />}
        {selectedSection === "logs" && <LogsView logs={logs} />}
      </section>
    </main>
  );
}

function DownloadsView({
  audioFormat,
  busyLabel,
  canAnalyze,
  canCreateJob,
  canDownloadImages,
  currentJob,
  health,
  isYouTube,
  metadata,
  notice,
  preferredFormats,
  queueCount,
  selectedFormatID,
  selectedKind,
  selectedMode,
  url,
  onAnalyze,
  onCreateJob,
  onDeleteJob,
  onSelectFormat,
  onSetAudioFormat,
  onSetKind,
  onSetMode,
  onSetURL,
}: {
  audioFormat: AudioFormat;
  busyLabel: string | null;
  canAnalyze: boolean;
  canCreateJob: boolean;
  canDownloadImages: boolean;
  currentJob: JobResponse | null;
  health: HealthResponse | null;
  isYouTube: boolean;
  metadata: AnalyzeResponse | null;
  notice: string | null;
  preferredFormats: MediaFormat[];
  queueCount: number;
  selectedFormatID: string;
  selectedKind: DownloadKind;
  selectedMode: DownloadMode;
  url: string;
  onAnalyze: () => void;
  onCreateJob: (kind?: DownloadKind) => void;
  onDeleteJob: () => void;
  onSelectFormat: (value: string) => void;
  onSetAudioFormat: (value: AudioFormat) => void;
  onSetKind: (value: DownloadKind) => void;
  onSetMode: (value: DownloadMode) => void;
  onSetURL: (value: string) => void;
}) {
  return (
    <div className="detail-scroll">
      <header className="app-header">
        <div className="app-icon">
          <Download size={32} />
        </div>
        <div>
          <h1>Media Extractor</h1>
          <p>3.0 云端下载核心。粘贴公开视频链接，选择视频、音频或图片后下载。</p>
        </div>
        <HealthPill health={health} />
      </header>

      <Card className="url-card">
        <div className="card-title-row">
          <Label icon={Link} text="视频链接" />
          <button className="secondary-button" disabled={!canAnalyze} onClick={onAnalyze}>
            {busyLabel === "分析中" ? <LoaderCircle className="spin" /> : <Search />}
            {busyLabel === "分析中" ? "分析中" : "分析链接"}
          </button>
        </div>
        <textarea
          className="url-editor"
          value={url}
          onChange={(event) => onSetURL(event.target.value)}
          placeholder="粘贴一个公开媒体链接，例如 https://www.youtube.com/watch?v=..."
          rows={5}
        />
      </Card>

      {notice && (
        <div className="notice">
          <CircleAlert size={18} />
          <span>{notice}</span>
        </div>
      )}

      <Card className="destination-card">
        <Label icon={Folder} text="保存位置" />
        <span className="destination-path">浏览器下载目录，云端临时文件会在下载后自动清理</span>
        <button disabled>更改</button>
      </Card>

      <Card>
        <div className="card-title-row">
          <Label icon={SlidersHorizontal} text="格式选择" />
        </div>

        {metadata ? (
          <>
            <MediaSummary metadata={metadata} />
            <div className="app-controls">
              <SelectField
                label="视频规格"
                value={selectedMode}
                options={[
                  ["best", modeLabels.best],
                  ["video1080p", modeLabels.video1080p],
                  ["video720p", modeLabels.video720p],
                  ["video480p", modeLabels.video480p],
                  ["custom", modeLabels.custom],
                ]}
                disabledOptions={selectedKind === "video" ? [] : ["custom"]}
                onChange={(value) => onSetMode(value as DownloadMode)}
              />
              <Segmented
                label="音频格式"
                value={audioFormat}
                options={audioFormats.map((item) => [item, item])}
                onChange={(value) => onSetAudioFormat(value as AudioFormat)}
              />
              <Segmented
                label="下载类型"
                value={selectedKind}
                options={[
                  ["video", kindLabels.video],
                  ["audio", kindLabels.audio],
                  ["images", kindLabels.images],
                ]}
                disabledOptions={canDownloadImages ? [] : ["images"]}
                onChange={(value) => onSetKind(value as DownloadKind)}
              />
            </div>

            {isYouTube && <SubtitlePanel />}

            <FormatList
              formats={preferredFormats}
              selectedFormatID={selectedFormatID}
              disabled={selectedMode !== "custom"}
              onSelect={onSelectFormat}
            />

            <div className="action-row">
              <button
                disabled={!canCreateJob || selectedKind !== "images" || !canDownloadImages}
                onClick={() => onCreateJob("images")}
              >
                <ImageDown />
                下载图片
              </button>
              <button disabled={!canCreateJob} onClick={() => onCreateJob("audio")}>
                <FileAudio />
                仅音频
              </button>
              <button
                className="primary-button"
                disabled={!canCreateJob}
                onClick={() => onCreateJob("video")}
              >
                <FileVideo />
                下载视频
              </button>
            </div>
          </>
        ) : (
          <EmptyPanel
            title="等待分析"
            description="输入链接并点击分析后，会在这里显示标题、平台和可用格式。"
            icon={Search}
          />
        )}
      </Card>

      <Card>
        <div className="card-title-row">
          <Label icon={List} text="下载队列" />
          <span className="task-count">{queueCount} 个任务</span>
        </div>
        <QueueContent
          currentJob={currentJob}
          metadata={metadata}
          onDelete={onDeleteJob}
        />
      </Card>
    </div>
  );
}

function Card({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return <section className={className ? `ve-card ${className}` : "ve-card"}>{children}</section>;
}

function Label({
  icon: Icon,
  text,
}: {
  icon: typeof Download;
  text: string;
}) {
  return (
    <div className="section-label">
      <Icon size={17} />
      <span>{text}</span>
    </div>
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
      <div className="media-copy">
        <h2>{metadata.title}</h2>
        <div className="media-meta">
          <span>{metadata.platform}</span>
          {metadata.author && <span>{metadata.author}</span>}
          {metadata.duration && <span>{formatDuration(metadata.duration)}</span>}
          {metadata.imageCount > 0 && <span>{metadata.imageCount} 张图片</span>}
        </div>
      </div>
    </article>
  );
}

function SelectField({
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
    <label className="select-field">
      <span>{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        {options.map(([optionValue, optionLabel]) => (
          <option
            key={optionValue}
            value={optionValue}
            disabled={disabledOptions.includes(optionValue)}
          >
            {optionLabel}
          </option>
        ))}
      </select>
    </label>
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

function SubtitlePanel() {
  return (
    <div className="subtitle-panel">
      <div className="subtitle-head">
        <Label icon={Captions} text="YouTube 字幕" />
        <span>云端接口暂未返回字幕轨道</span>
      </div>
      <p>当前网页版会先保持 App 的字幕区域位置。后端加入字幕轨道后，这里会显示单语、双语或三语选择。</p>
    </div>
  );
}

function FormatList({
  formats,
  selectedFormatID,
  disabled,
  onSelect,
}: {
  formats: MediaFormat[];
  selectedFormatID: string;
  disabled: boolean;
  onSelect: (value: string) => void;
}) {
  return (
    <div className={disabled ? "format-group disabled" : "format-group"}>
      <div className="format-head">
        <span>可用格式</span>
        <span>{formats.length} 项</span>
      </div>
      <div className="format-list">
        {formats.map((format) => (
          <button
            key={format.formatID}
            className={selectedFormatID === format.formatID ? "format-row selected" : "format-row"}
            onClick={() => onSelect(format.formatID)}
          >
            <span className="format-main">
              <strong>{formatSummary(format)}</strong>
              <small>{formatKind(format)}</small>
            </span>
            <span>{format.extensionName}</span>
            <span>{format.fps ? `${format.fps}fps` : "-"}</span>
            <span>{formatSize(format)}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function QueueContent({
  currentJob,
  metadata,
  onDelete,
}: {
  currentJob: JobResponse | null;
  metadata: AnalyzeResponse | null;
  onDelete: () => void;
}) {
  if (currentJob) {
    return <JobRow job={currentJob} onDelete={onDelete} />;
  }

  if (metadata) {
    return (
      <article className="queue-row selected">
        <FileVideo className="queue-icon" />
        <div className="queue-body">
          <div className="queue-topline">
            <h3>{metadata.title}</h3>
            <StatusBadge status="ready" />
          </div>
          <p>{metadata.sourceURL}</p>
          <div className="progress-track">
            <div style={{ width: "0%" }} />
          </div>
          <div className="queue-meta">已分析，等待选择下载方式。</div>
        </div>
        <button className="icon-button" onClick={onDelete} aria-label="移除任务">
          <Trash2 />
        </button>
      </article>
    );
  }

  return (
    <EmptyPanel
      title="暂无任务"
      description="分析链接后，任务会加入队列。"
      icon={Download}
      compact
    />
  );
}

function JobRow({
  job,
  onDelete,
}: {
  job: JobResponse;
  onDelete: () => void;
}) {
  const finished = ["completed", "failed", "cancelled"].includes(job.status);

  return (
    <article className="queue-row selected">
      <FileVideo className="queue-icon" />
      <div className="queue-body">
        <div className="queue-topline">
          <h3>{job.title}</h3>
          <StatusBadge status={job.status} />
        </div>
        <p>{kindLabels[job.kind]} · {statusLabel(job.status)}</p>
        <div className="progress-track">
          <div style={{ width: `${Math.round(job.progress.fraction * 100)}%` }} />
        </div>
        <div className="queue-meta">
          <span>{job.progress.percentText}</span>
          {job.progress.speed && <span>{job.progress.speed}</span>}
          {job.progress.eta && <span>剩余 {job.progress.eta}</span>}
          {job.fileName && <span>{job.fileName}</span>}
        </div>
        {job.errorMessage && <div className="inline-error">{job.errorMessage}</div>}
        {job.fileReady && (
          <a className="download-link" href={downloadURL(job.jobID)}>
            <Download />
            下载文件
          </a>
        )}
        {!job.fileReady && finished && !job.errorMessage && (
          <div className="inline-error">文件已不可用</div>
        )}
      </div>
      <button className="icon-button" onClick={onDelete} aria-label="删除任务">
        <Trash2 />
      </button>
    </article>
  );
}

function StatusBadge({ status }: { status: QueueStatus }) {
  return <span className={`status-badge ${status}`}>{statusLabel(status)}</span>;
}

function EmptyPanel({
  title,
  description,
  icon: Icon,
  compact = false,
}: {
  title: string;
  description: string;
  icon: typeof Download;
  compact?: boolean;
}) {
  return (
    <div className={compact ? "empty-state compact" : "empty-state"}>
      <Icon size={36} />
      <strong>{title}</strong>
      <span>{description}</span>
    </div>
  );
}

function HistoryView({ items }: { items: HistoryEntry[] }) {
  return (
    <div className="detail-scroll">
      <SimpleHeader title="历史" description="本次网页会话里的下载记录。" />
      <Card>
        {items.length === 0 ? (
          <EmptyPanel
            title="暂无历史"
            description="完成或失败的任务会显示在这里。"
            icon={Clock3}
          />
        ) : (
          <div className="history-list">
            {items.map((item) => (
              <div className="history-row" key={item.id}>
                <Download size={17} />
                <div>
                  <strong>{item.title}</strong>
                  <span>{kindLabels[item.kind]} · {statusLabel(item.status)} · {item.createdAt}</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}

function SettingsView({ health }: { health: HealthResponse | null }) {
  return (
    <div className="detail-scroll">
      <SimpleHeader title="设置" description="网页版设置只保存在当前浏览器会话。" />
      <Card>
        <div className="settings-grid">
          <div className="settings-field">
            <span>访问方式</span>
            <code>公开访问，无需共享码</code>
          </div>
          <div className="settings-field">
            <span>云端 API</span>
            <code>{apiBaseURL}</code>
          </div>
          <div className="settings-field">
            <span>服务状态</span>
            <code>{health?.message || "检查中"}</code>
          </div>
        </div>
      </Card>
    </div>
  );
}

function LogsView({ logs }: { logs: LogEntry[] }) {
  return (
    <div className="detail-scroll">
      <SimpleHeader title="日志" description="分析、提交和下载状态会记录在这里。" />
      <Card>
        {logs.length === 0 ? (
          <EmptyPanel title="暂无日志" description="执行一次分析后会出现日志。" icon={FileText} />
        ) : (
          <div className="log-list">
            {logs.map((log) => (
              <div className={`log-row ${log.level}`} key={log.id}>
                <span>{log.time}</span>
                <p>{log.message}</p>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}

function SimpleHeader({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <header className="simple-header">
      <h1>{title}</h1>
      <p>{description}</p>
    </header>
  );
}

function firstURL(value: string) {
  return value
    .split(/\s+/)
    .map((item) => item.trim())
    .filter(Boolean)[0] || "";
}

function loadHistory(): HistoryEntry[] {
  try {
    const stored = localStorage.getItem("video-extractor-history");
    return stored ? (JSON.parse(stored) as HistoryEntry[]).slice(0, 100) : [];
  } catch {
    return [];
  }
}

function historyFromJob(job: JobResponse): HistoryEntry {
  return {
    id: job.jobID,
    title: job.title,
    kind: job.kind,
    status: job.status,
    createdAt: new Date(job.createdAt).toLocaleString(),
  };
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

function formatSummary(format: MediaFormat) {
  if (format.height) return `${format.height}p`;
  return format.resolution || format.formatNote || format.formatID;
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

function statusLabel(status: QueueStatus) {
  const labels: Record<QueueStatus, string> = {
    ready: "就绪",
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
