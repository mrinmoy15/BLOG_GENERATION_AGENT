import { PIPELINE_NODES, type PipelineNode } from "../types";

export class ProgressStream {
  private el: HTMLElement;
  private nodes: PipelineNode[];
  private logEl!: HTMLElement;
  private nodeEls: Map<string, HTMLElement> = new Map();

  constructor() {
    this.nodes = PIPELINE_NODES.map((n) => ({ ...n }));
    this.el = this.render();
  }

  mount(parent: HTMLElement): void {
    parent.appendChild(this.el);
  }

  show(): void {
    this.el.classList.add("progress--visible");
    this.el.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  hide(): void {
    this.el.classList.remove("progress--visible");
  }

  reset(): void {
    this.nodes.forEach((n) => {
      n.status = "pending";
      const el = this.nodeEls.get(n.id);
      if (el) {
        el.className = "pipeline-node pipeline-node--pending";
        el.querySelector(".node-status")!.textContent = "";
      }
    });
    this.logEl.innerHTML = "";
    this.addLog("Pipeline initialised — waiting for first event…");
  }

  markNodeDone(nodeId: string, label: string): void {
    const node = this.nodes.find((n) => n.id === nodeId);
    if (node) {
      node.status = "done";
      const el = this.nodeEls.get(nodeId);
      if (el) {
        el.className = "pipeline-node pipeline-node--done";
        el.querySelector(".node-status")!.textContent = "✓";
      }
    }
    this.addLog(`✦ ${label}`);
  }

  addLog(message: string): void {
    const line = document.createElement("div");
    line.className = "log-line";
    const ts = new Date().toLocaleTimeString("en-GB", { hour12: false });
    line.innerHTML = `<span class="log-ts">${ts}</span><span class="log-msg">${message}</span>`;
    this.logEl.appendChild(line);
    this.logEl.scrollTop = this.logEl.scrollHeight;
  }

  private render(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "progress-stream";

    // Pipeline tracker
    const tracker = document.createElement("div");
    tracker.className = "pipeline-tracker";

    this.nodes.forEach((node, i) => {
      const nodeEl = document.createElement("div");
      nodeEl.className = "pipeline-node pipeline-node--pending";
      nodeEl.innerHTML = `
        <div class="node-connector ${i === 0 ? "node-connector--hidden" : ""}"></div>
        <div class="node-dot">
          <span class="node-status"></span>
        </div>
        <div class="node-info">
          <span class="node-label">${node.label}</span>
        </div>
      `;
      this.nodeEls.set(node.id, nodeEl);
      tracker.appendChild(nodeEl);
    });

    // Log terminal
    const terminal = document.createElement("div");
    terminal.className = "terminal";
    terminal.innerHTML = `
      <div class="terminal__bar">
        <span class="terminal__dot terminal__dot--red"></span>
        <span class="terminal__dot terminal__dot--amber"></span>
        <span class="terminal__dot terminal__dot--green"></span>
        <span class="terminal__title">agent.log</span>
      </div>
    `;
    this.logEl = document.createElement("div");
    this.logEl.className = "terminal__body";
    terminal.appendChild(this.logEl);

    wrap.appendChild(tracker);
    wrap.appendChild(terminal);
    return wrap;
  }
}
