import { marked } from "marked";
import { showToast } from "./Toast";
import hljs from "highlight.js";
import "highlight.js/styles/vs2015.css";

export class ResultPanel {
  private el: HTMLElement;
  private previewEl!: HTMLElement;
  private editorEl!: HTMLTextAreaElement;
  private filenameEl!: HTMLElement;
  private rawMarkdown = "";
  private activeTab: "preview" | "edit" = "preview";

  constructor() {
    this.el = this.render();
    this.bindEvents();
  }

  mount(parent: HTMLElement): void {
    parent.appendChild(this.el);
  }

  show(markdown: string, filename: string): void {
    this.rawMarkdown = markdown;
    this.filenameEl.textContent = filename;
    this.renderPreview(markdown);
    this.editorEl.value = markdown;
    this.el.classList.add("result--visible");
    this.el.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  hide(): void {
    this.el.classList.remove("result--visible");
  }

  private renderPreview(md: string): void {
    const apiBase = (import.meta.env.VITE_API_URL as string | undefined) ?? "http://localhost:8000";

    // Convert LaTeX delimiters before marked strips the backslashes:
    //   \[...\]  →  $$...$$  (display math)
    //   \(...\)  →  $...$    (inline math)
    const withMath = md
      .replace(/\\\[/g, "$$").replace(/\\\]/g, "$$")
      .replace(/\\\(/g, "$").replace(/\\\)/g, "$");

    const resolved = withMath.replace(/!\[([^\]]*)\]\(images\//g, `![$1](${apiBase}/outputs/images/`);
    this.previewEl.innerHTML = marked.parse(resolved) as string;

    // Syntax-highlight every code block and add a language badge
    this.previewEl.querySelectorAll<HTMLElement>("pre code").forEach((block) => {
      hljs.highlightElement(block);
      const pre = block.parentElement!;
      const lang = block.className.match(/language-(\S+)/)?.[1] ?? "";
      if (lang && !pre.querySelector(".code-lang")) {
        const badge = document.createElement("span");
        badge.className = "code-lang";
        badge.textContent = lang;
        pre.appendChild(badge);
      }
    });

    // Render math via KaTeX auto-render (loaded from CDN in index.html)
    const renderMathInElement = (window as unknown as Record<string, unknown>)["renderMathInElement"] as ((el: HTMLElement, opts: unknown) => void) | undefined;
    if (renderMathInElement) {
      renderMathInElement(this.previewEl, {
        delimiters: [
          { left: "$$", right: "$$", display: true },
          { left: "$",  right: "$",  display: false },
        ],
        throwOnError: false,
      });
    }
  }

  private render(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "result-panel";

    wrap.innerHTML = `
      <div class="result-panel__header">
        <div class="result-meta">
          <span class="result-icon">◈</span>
          <span class="result-filename" id="result-filename">blog.md</span>
        </div>
        <div class="result-actions">
          <button class="btn btn--ghost" id="btn-copy">Copy markdown</button>
          <button class="btn btn--primary" id="btn-download">↓ Download</button>
        </div>
      </div>

      <div class="result-tabs">
        <button class="tab tab--active" data-tab="preview">Preview</button>
        <button class="tab" data-tab="edit">Edit</button>
      </div>

      <div class="result-body">
        <div class="markdown-preview" id="markdown-preview"></div>
        <textarea class="markdown-editor" id="markdown-editor" spellcheck="false"></textarea>
      </div>
    `;

    this.previewEl  = wrap.querySelector<HTMLElement>("#markdown-preview")!;
    this.editorEl   = wrap.querySelector<HTMLTextAreaElement>("#markdown-editor")!;
    this.filenameEl = wrap.querySelector<HTMLElement>("#result-filename")!;

    return wrap;
  }

  private bindEvents(): void {
    // Tabs
    this.el.querySelectorAll<HTMLButtonElement>(".tab").forEach((tab) => {
      tab.addEventListener("click", () => {
        const which = tab.dataset["tab"] as "preview" | "edit";
        this.switchTab(which);
      });
    });

    // Live preview update when editing
    this.editorEl.addEventListener("input", () => {
      this.rawMarkdown = this.editorEl.value;
      if (this.activeTab === "preview") this.renderPreview(this.rawMarkdown);
    });

    // Copy
    this.el.querySelector("#btn-copy")!.addEventListener("click", () => {
      navigator.clipboard.writeText(this.rawMarkdown).then(() => {
        showToast("Markdown copied to clipboard", "success");
      });
    });

    // Download
    this.el.querySelector("#btn-download")!.addEventListener("click", () => {
      const blob = new Blob([this.rawMarkdown], { type: "text/markdown" });
      const url  = URL.createObjectURL(blob);
      const a    = document.createElement("a");
      a.href     = url;
      a.download = this.filenameEl.textContent ?? "blog.md";
      a.click();
      URL.revokeObjectURL(url);
      showToast("File downloaded", "success");
    });
  }

  private switchTab(tab: "preview" | "edit"): void {
    this.activeTab = tab;

    this.el.querySelectorAll<HTMLButtonElement>(".tab").forEach((t) => {
      t.classList.toggle("tab--active", t.dataset["tab"] === tab);
    });

    if (tab === "preview") {
      this.renderPreview(this.rawMarkdown);
      this.previewEl.style.display = "block";
      this.editorEl.style.display  = "none";
    } else {
      this.editorEl.value         = this.rawMarkdown;
      this.previewEl.style.display = "none";
      this.editorEl.style.display  = "block";
    }
  }
}
