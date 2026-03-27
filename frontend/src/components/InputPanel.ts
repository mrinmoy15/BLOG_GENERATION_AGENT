export interface InputPanelOptions {
  onSubmit: (topic: string, model: string) => void;
}

export class InputPanel {
  private el: HTMLElement;
  private textarea!: HTMLTextAreaElement;
  private modelSelect!: HTMLSelectElement;
  private submitBtn!: HTMLButtonElement;
  private charCount!: HTMLElement;

  constructor(private options: InputPanelOptions) {
    this.el = this.render();
    this.bindEvents();
  }

  mount(parent: HTMLElement): void {
    parent.appendChild(this.el);
  }

  setDisabled(disabled: boolean): void {
    this.textarea.disabled = disabled;
    this.modelSelect.disabled = disabled;
    this.submitBtn.disabled = disabled;
    this.submitBtn.classList.toggle("btn--loading", disabled);
    this.submitBtn.textContent = disabled ? "Generating…" : "Generate Blog";
  }

  private render(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "input-panel";
    wrap.innerHTML = `
      <div class="input-panel__header">
        <div class="input-panel__logo">
          <span class="logo-mark">✦</span>
          <span class="logo-text">BlogForge</span>
        </div>
        <p class="input-panel__tagline">Turn any topic into a publication-ready technical blog</p>
      </div>

      <div class="input-panel__form">
        <label class="field-label" for="topic-input">Topic</label>
        <div class="textarea-wrap">
          <textarea
            id="topic-input"
            class="topic-textarea"
            placeholder="e.g. How KV cache works in LLM inference, and why it matters for latency"
            rows="4"
            maxlength="500"
          ></textarea>
          <span class="char-count"><span id="char-current">0</span> / 500</span>
        </div>

        <div class="form-row">
          <div class="field-group">
            <label class="field-label" for="model-select">Model</label>
            <select id="model-select" class="model-select">
              <option value="gpt-4o">GPT-4o</option>
              <option value="gpt-4o-mini">GPT-4o mini</option>
              <option value="gpt-4-turbo">GPT-4 Turbo</option>
            </select>
          </div>

          <button id="submit-btn" class="btn btn--primary" type="button">
            Generate Blog
          </button>
        </div>
      </div>
    `;

    this.textarea    = wrap.querySelector<HTMLTextAreaElement>("#topic-input")!;
    this.modelSelect = wrap.querySelector<HTMLSelectElement>("#model-select")!;
    this.submitBtn   = wrap.querySelector<HTMLButtonElement>("#submit-btn")!;
    this.charCount   = wrap.querySelector<HTMLElement>("#char-current")!;

    return wrap;
  }

  private bindEvents(): void {
    this.textarea.addEventListener("input", () => {
      this.charCount.textContent = String(this.textarea.value.length);
    });

    this.textarea.addEventListener("keydown", (e: KeyboardEvent) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
        this.handleSubmit();
      }
    });

    this.submitBtn.addEventListener("click", () => this.handleSubmit());
  }

  private handleSubmit(): void {
    const topic = this.textarea.value.trim();
    if (!topic) {
      this.textarea.classList.add("textarea--error");
      setTimeout(() => this.textarea.classList.remove("textarea--error"), 800);
      return;
    }
    this.options.onSubmit(topic, this.modelSelect.value);
  }
}
