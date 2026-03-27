import { InputPanel } from "./components/InputPanel";
import { ProgressStream } from "./components/ProgressStream";
import { ResultPanel } from "./components/ResultPanel";
import { showToast } from "./components/Toast";
import { streamGenerate, checkHealth } from "./api";
import "./styles/main.css";
import { Sidebar } from "./components/Sidebar";

const app = document.getElementById("app")!;

// ── Layout skeleton (three columns: sidebar | input | main) ──────────────────
const layout = document.createElement("div");
layout.className = "layout layout--three-col";
app.appendChild(layout);

const sidebarCol = document.createElement("div");
sidebarCol.className = "col col--sidebar";

const leftCol = document.createElement("div");
leftCol.className = "col col--left";

const rightCol = document.createElement("div");
rightCol.className = "col col--right";

layout.appendChild(sidebarCol);
layout.appendChild(leftCol);
layout.appendChild(rightCol);

// ── Background canvas particles ──────────────────────────────────────────────
const canvas = document.createElement("canvas");
canvas.className = "bg-canvas";
document.body.prepend(canvas);
initParticles(canvas);

// ── Instantiate components ───────────────────────────────────────────────────
const inputPanel     = new InputPanel({ onSubmit: handleSubmit });
const progressStream = new ProgressStream();
const resultPanel    = new ResultPanel();
const sidebar        = new Sidebar({
  onSelect: (filename: string, markdown: string) => {
    resultPanel.show(markdown, filename);
    progressStream.hide();
  },
});

sidebar.mount(sidebarCol);
inputPanel.mount(leftCol);
progressStream.mount(rightCol);
resultPanel.mount(rightCol);

// ── Health check on load ─────────────────────────────────────────────────────
checkHealth().then((ok) => {
  if (!ok) showToast("Cannot reach the API — is the server running?", "error", 8000);
});

sidebar.refresh();

// ── Core flow ────────────────────────────────────────────────────────────────
let cancelStream: (() => void) | null = null;

function handleSubmit(topic: string, model: string): void {
  if (cancelStream) cancelStream();

  inputPanel.setDisabled(true);
  resultPanel.hide();
  progressStream.reset();
  progressStream.show();

  cancelStream = streamGenerate(
    { topic, model, output_dir: "outputs" },
    {
      onNodeDone(evt) {
        progressStream.markNodeDone(evt.node, evt.label);
      },
      onResult(evt) {
        progressStream.addLog("✦ Pipeline complete");
        resultPanel.show(evt.markdown, evt.filename);
        inputPanel.setDisabled(false);
        showToast("Blog generated successfully", "success");
        sidebar.refresh();
      },
      onError(evt) {
        progressStream.addLog(`✕ Error: ${evt.message}`);
        inputPanel.setDisabled(false);
        showToast(`Generation failed: ${evt.message}`, "error");
      },
      onClose() {
        inputPanel.setDisabled(false);
      },
    }
  );
}

// ── Ambient particle background ──────────────────────────────────────────────
function initParticles(canvas: HTMLCanvasElement): void {
  const ctx = canvas.getContext("2d")!;

  type Particle = {
    x: number; y: number;
    vx: number; vy: number;
    r: number; alpha: number;
  };

  let particles: Particle[] = [];
  let W = 0, H = 0;

  function resize() {
    W = canvas.width  = window.innerWidth;
    H = canvas.height = window.innerHeight;
  }

  function spawn(): Particle {
    return {
      x: Math.random() * W,
      y: Math.random() * H,
      vx: (Math.random() - 0.5) * 0.25,
      vy: (Math.random() - 0.5) * 0.25,
      r: Math.random() * 1.5 + 0.3,
      alpha: Math.random() * 0.4 + 0.05,
    };
  }

  function init() {
    resize();
    particles = Array.from({ length: 90 }, spawn);
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);
    for (const p of particles) {
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(180,160,255,${p.alpha})`;
      ctx.fill();

      p.x += p.vx;
      p.y += p.vy;

      if (p.x < 0 || p.x > W) p.vx *= -1;
      if (p.y < 0 || p.y > H) p.vy *= -1;
    }
    requestAnimationFrame(draw);
  }

  window.addEventListener("resize", resize);
  init();
  draw();
}
