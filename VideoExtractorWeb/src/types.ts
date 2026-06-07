export type DownloadKind = "video" | "audio" | "images";

export type DownloadMode =
  | "best"
  | "video1080p"
  | "video720p"
  | "video480p"
  | "custom";

export type AudioFormat = "m4a" | "mp3" | "wav";

export type JobStatus =
  | "waiting"
  | "analyzing"
  | "downloading"
  | "converting"
  | "completed"
  | "failed"
  | "cancelled";

export interface HealthResponse {
  ok: boolean;
  authConfigured: boolean;
  ytdlpAvailable: boolean;
  ffmpegAvailable: boolean;
  activeJobs: number;
  message: string;
}

export interface MediaFormat {
  formatID: string;
  extensionName: string;
  resolution?: string | null;
  width?: number | null;
  height?: number | null;
  fps?: number | null;
  fileSize?: number | null;
  approxFileSize?: number | null;
  videoCodec?: string | null;
  audioCodec?: string | null;
  audioBitrate?: number | null;
  totalBitrate?: number | null;
  formatNote?: string | null;
}

export interface AnalyzeResponse {
  id: string;
  sourceURL: string;
  platform: string;
  title: string;
  author?: string | null;
  duration?: number | null;
  thumbnailURL?: string | null;
  imageCount: number;
  formats: MediaFormat[];
}

export interface JobProgress {
  fraction: number;
  percentText: string;
  speed?: string | null;
  eta?: string | null;
}

export interface JobResponse {
  jobID: string;
  status: JobStatus;
  title: string;
  kind: DownloadKind;
  progress: JobProgress;
  errorMessage?: string | null;
  fileName?: string | null;
  fileReady: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateJobRequest {
  url: string;
  kind: DownloadKind;
  mode: DownloadMode;
  audioFormat: AudioFormat;
  customFormatID?: string;
}
