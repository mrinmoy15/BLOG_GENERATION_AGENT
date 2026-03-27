export interface GenerateRequest {
  topic: string;
  model: string;
  output_dir: string;
}

export interface NodeDoneEvent {
  node: string;
  label: string;
}

export interface ResultEvent {
  filename: string;
  markdown: string;
}

export interface ErrorEvent {
  message: string;
}

export type SSEEventType = "node_done" | "result" | "error";

export interface PipelineNode {
  id: string;
  label: string;
  status: "pending" | "running" | "done";
}

// Ordered list of nodes for the progress UI
export const PIPELINE_NODES: PipelineNode[] = [
  { id: "router",       label: "Analysing topic",      status: "pending" },
  { id: "research",     label: "Web research",         status: "pending" },
  { id: "orchestrator", label: "Planning structure",   status: "pending" },
  { id: "worker",       label: "Writing sections",     status: "pending" },
  { id: "reducer",      label: "Merging & finalising", status: "pending" },
];
