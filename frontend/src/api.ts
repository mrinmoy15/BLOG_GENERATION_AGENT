import type { GenerateRequest, NodeDoneEvent, ResultEvent, ErrorEvent } from "./types";

const BASE_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000";

export interface StreamCallbacks {
  onNodeDone: (evt: NodeDoneEvent) => void;
  onResult:   (evt: ResultEvent)   => void;
  onError:    (evt: ErrorEvent)    => void;
  onClose:    ()                   => void;
}

/**
 * Opens an SSE connection to /generate/stream.
 * Returns a cleanup function — call it to abort the stream.
 */
export function streamGenerate(
  req: GenerateRequest,
  callbacks: StreamCallbacks
): () => void {
  const controller = new AbortController();

  // SSE via fetch so we can POST a body (EventSource only supports GET)
  fetch(`${BASE_URL}/generate/stream`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
    signal: controller.signal,
  })
    .then(async (res) => {
      if (!res.ok || !res.body) {
        callbacks.onError({ message: `HTTP ${res.status}: ${res.statusText}` });
        return;
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        // SSE messages are separated by double newlines
        const parts = buffer.split("\n\n");
        buffer = parts.pop() ?? "";

        for (const part of parts) {
          if (!part.trim()) continue;

          let eventType = "message";
          let dataLine = "";

          for (const line of part.split("\n")) {
            if (line.startsWith("event:")) eventType = line.slice(6).trim();
            if (line.startsWith("data:"))  dataLine  = line.slice(5).trim();
          }

          if (!dataLine) continue;

          try {
            const payload = JSON.parse(dataLine);
            if (eventType === "node_done") callbacks.onNodeDone(payload as NodeDoneEvent);
            if (eventType === "result")    callbacks.onResult(payload as ResultEvent);
            if (eventType === "error")     callbacks.onError(payload as ErrorEvent);
          } catch {
            // malformed JSON — ignore
          }
        }
      }

      callbacks.onClose();
    })
    .catch((err: unknown) => {
      if (err instanceof Error && err.name === "AbortError") return;
      callbacks.onError({ message: String(err) });
    });

  return () => controller.abort();
}

export async function checkHealth(): Promise<boolean> {
  try {
    const res = await fetch(`${BASE_URL}/health`);
    return res.ok;
  } catch {
    return false;
  }
}

export interface BlogMeta {
  filename: string;
  created_at: string;
  size_kb: number;
}

export async function listBlogs(): Promise<BlogMeta[]> {
  const res = await fetch(`${BASE_URL}/blogs`);
  if (!res.ok) return [];
  const data = await res.json();
  return data.blogs as BlogMeta[];
}

export async function getBlog(filename: string): Promise<{ filename: string; markdown: string } | null> {
  const res = await fetch(`${BASE_URL}/blogs/${encodeURIComponent(filename)}`);
  if (!res.ok) return null;
  return res.json();
}

export async function deleteBlog(filename: string): Promise<boolean> {
  const res = await fetch(`${BASE_URL}/blogs/${encodeURIComponent(filename)}`, {
    method: "DELETE",
  });
  return res.ok;
}
