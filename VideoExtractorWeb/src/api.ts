import type {
  AnalyzeResponse,
  CreateJobRequest,
  HealthResponse,
  JobResponse,
} from "./types";

const DEFAULT_API_BASE = "http://localhost:8765";

export const apiBaseURL = (
  import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE
).replace(/\/+$/, "");

async function requestJSON<T>(
  path: string,
  accessCode: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (accessCode) {
    headers.set("X-Access-Code", accessCode);
  }

  const response = await fetch(`${apiBaseURL}${path}`, {
    ...init,
    headers,
  });

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
  return fetch(`${apiBaseURL}/api/health`).then(async (response) => {
    if (!response.ok) {
      throw new Error(await response.text());
    }
    return response.json() as Promise<HealthResponse>;
  });
}

export function analyzeURL(
  accessCode: string,
  url: string,
): Promise<AnalyzeResponse> {
  return requestJSON<AnalyzeResponse>("/api/analyze", accessCode, {
    method: "POST",
    body: JSON.stringify({ url }),
  });
}

export function createJob(
  accessCode: string,
  payload: CreateJobRequest,
): Promise<{ jobID: string }> {
  return requestJSON<{ jobID: string }>("/api/jobs", accessCode, {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function getJob(
  accessCode: string,
  jobID: string,
): Promise<JobResponse> {
  return requestJSON<JobResponse>(`/api/jobs/${jobID}`, accessCode);
}

export function deleteJob(accessCode: string, jobID: string): Promise<void> {
  return requestJSON<void>(`/api/jobs/${jobID}`, accessCode, {
    method: "DELETE",
  });
}

export function downloadURL(jobID: string, accessCode: string): string {
  const query = new URLSearchParams({ access_code: accessCode });
  return `${apiBaseURL}/api/jobs/${jobID}/file?${query.toString()}`;
}
