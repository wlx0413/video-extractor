import type {
  AnalyzeResponse,
  CreateJobRequest,
  HealthResponse,
  JobResponse,
} from "./types";

// 网页版必须始终使用公网云端 API。不允许回退到 localhost，
// 否则其他访问者的浏览器会错误请求他们自己的电脑。
const DEFAULT_API_BASE = "https://lixon-video-extractor-api.onrender.com";

export const apiBaseURL = (
  import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE
).replace(/\/+$/, "");

async function requestJSON<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  let response: Response;
  try {
    response = await fetch(`${apiBaseURL}${path}`, {
      ...init,
      headers,
    });
  } catch {
    throw new Error("暂时无法连接云端服务，请稍后重试。");
  }

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `请求失败：${response.status}`);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  const text = await response.text();
  if (!text) {
    return undefined as T;
  }

  return JSON.parse(text) as T;
}

export function checkHealth(): Promise<HealthResponse> {
  return requestJSON<HealthResponse>("/api/health");
}

export function analyzeURL(
  url: string,
): Promise<AnalyzeResponse> {
  return requestJSON<AnalyzeResponse>("/api/analyze", {
    method: "POST",
    body: JSON.stringify({ url }),
  });
}

export function createJob(
  payload: CreateJobRequest,
): Promise<{ jobID: string }> {
  return requestJSON<{ jobID: string }>("/api/jobs", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function getJob(
  jobID: string,
): Promise<JobResponse> {
  return requestJSON<JobResponse>(`/api/jobs/${jobID}`);
}

export function deleteJob(jobID: string): Promise<void> {
  return requestJSON<void>(`/api/jobs/${jobID}`, {
    method: "DELETE",
  });
}

export function downloadURL(jobID: string): string {
  return `${apiBaseURL}/api/jobs/${jobID}/file`;
}
