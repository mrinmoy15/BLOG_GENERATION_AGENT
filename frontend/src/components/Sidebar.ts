import { listBlogs, getBlog, deleteBlog } from "../api";

export interface SidebarOptions {
  onSelect: (filename: string, markdown: string) => void;
  onDelete?: (filename: string) => void;
}

export class Sidebar {
  private el: HTMLElement;
  private listEl!: HTMLElement;

  constructor(private options: SidebarOptions) {
    this.el = this.render();
  }

  mount(parent: HTMLElement): void {
    parent.appendChild(this.el);
  }

  async refresh(): Promise<void> {
    const blogs = await listBlogs();
    this.listEl.innerHTML = "";

    if (blogs.length === 0) {
      this.listEl.innerHTML = `<p class="sidebar-empty">No blogs yet this week</p>`;
      return;
    }

    blogs.forEach((blog) => {
      const item = document.createElement("div");
      item.className = "sidebar-item";

      const date = new Date(blog.created_at);
      const label = blog.filename.replace(".md", "").replace(/_/g, " ");
      const time = date.toLocaleDateString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

      item.innerHTML = `
        <div class="sidebar-item__body">
          <span class="sidebar-item__name">${label}</span>
          <span class="sidebar-item__meta">${time} · ${blog.size_kb}kb</span>
        </div>
        <button class="sidebar-item__delete" title="Delete blog">✕</button>
      `;

      item.querySelector<HTMLElement>(".sidebar-item__body")!.addEventListener("click", async () => {
        document.querySelectorAll(".sidebar-item").forEach(el => el.classList.remove("sidebar-item--active"));
        item.classList.add("sidebar-item--active");
        const result = await getBlog(blog.filename);
        if (result) this.options.onSelect(result.filename, result.markdown);
      });

      item.querySelector<HTMLButtonElement>(".sidebar-item__delete")!.addEventListener("click", async (e) => {
        e.stopPropagation();
        const ok = await deleteBlog(blog.filename);
        if (ok) {
          item.remove();
          this.options.onDelete?.(blog.filename);
          if (this.listEl.children.length === 0) {
            this.listEl.innerHTML = `<p class="sidebar-empty">No blogs yet this week</p>`;
          }
        }
      });

      this.listEl.appendChild(item);
    });
  }

  private render(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "sidebar";
    wrap.innerHTML = `
      <div class="sidebar__header">
        <span class="sidebar__title">Recent blogs</span>
        <span class="sidebar__subtitle">Last 7 days</span>
      </div>
    `;

    this.listEl = document.createElement("div");
    this.listEl.className = "sidebar__list";
    wrap.appendChild(this.listEl);
    return wrap;
  }
}
