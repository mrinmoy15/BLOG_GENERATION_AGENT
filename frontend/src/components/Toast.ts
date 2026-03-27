export type ToastKind = "success" | "error" | "info";

interface Toast {
  el: HTMLElement;
  timeout: ReturnType<typeof setTimeout>;
}

let _container: HTMLElement | null = null;

function getContainer(): HTMLElement {
  if (!_container) {
    _container = document.createElement("div");
    _container.className = "toast-container";
    document.body.appendChild(_container);
  }
  return _container;
}

export function showToast(message: string, kind: ToastKind = "info", duration = 4000): void {
  const container = getContainer();

  const el = document.createElement("div");
  el.className = `toast toast--${kind}`;
  el.innerHTML = `
    <span class="toast__icon">${kind === "success" ? "✓" : kind === "error" ? "✕" : "i"}</span>
    <span class="toast__msg">${message}</span>
  `;

  container.appendChild(el);

  // Trigger enter animation
  requestAnimationFrame(() => el.classList.add("toast--visible"));

  const toast: Toast = {
    el,
    timeout: setTimeout(() => dismiss(toast), duration),
  };

  el.addEventListener("click", () => {
    clearTimeout(toast.timeout);
    dismiss(toast);
  });
}

function dismiss(toast: Toast): void {
  toast.el.classList.remove("toast--visible");
  toast.el.classList.add("toast--leaving");
  toast.el.addEventListener("transitionend", () => toast.el.remove(), { once: true });
}
