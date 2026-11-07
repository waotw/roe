import { Controller } from "@hotwired/stimulus";

// Live help beside the content layout editor. The server reads the layout
// (ContentLayout::Explain) and returns the HTML it draws plus a description
// of every line and [box]; this controller only shows them.
//
//   typing      → asks the server again (debounced), redraws the example
//   caret moves → highlights the example lines the caret's line drew, and
//                 shows what that line, or the box under the caret, does,
//                 above the general rules (which always stay). The last
//                 one stays when the textarea loses focus, so it can be
//                 copied.
//
// Nothing here touches the textarea's value or the form.
export default class extends Controller {
  static targets = ["input", "html", "warnings", "detail"];
  static values = { url: String, initial: Object };

  connect() {
    this.explained = this.initialValue;
    this.caret = null;
    this.render();

    this.onSelection = () => {
      if (document.activeElement === this.inputTarget) this.moveCaret();
    };
    document.addEventListener("selectionchange", this.onSelection);
    this.inputTarget.addEventListener("input", (this.onInput = () => this.refresh()));
    this.inputTarget.addEventListener("focus", (this.onFocus = () => this.moveCaret()));
  }

  disconnect() {
    document.removeEventListener("selectionchange", this.onSelection);
    this.inputTarget.removeEventListener("input", this.onInput);
    this.inputTarget.removeEventListener("focus", this.onFocus);
    clearTimeout(this.timer);
    this.request?.abort();
  }

  refresh() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fetchExplain(), 200);
  }

  async fetchExplain() {
    this.request?.abort();
    this.request = new AbortController();
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token || "" },
        body: JSON.stringify({ content: this.inputTarget.value }),
        signal: this.request.signal,
      });
      if (!response.ok) return;
      this.explained = await response.json();
      this.render();
      this.showHelp();
    } catch (error) {
      if (error.name !== "AbortError") console.warn("[layout-explain]", error);
    }
  }

  // Line (1-based) and column of the caret.
  moveCaret() {
    const before = this.inputTarget.value.slice(0, this.inputTarget.selectionStart);
    const lines = before.split("\n");
    const caret = { line: lines.length, column: lines[lines.length - 1].length };
    if (this.caret && this.caret.line === caret.line && this.caret.column === caret.column) return;
    this.caret = caret;
    this.render();
    this.showHelp();
  }

  render() {
    const info = this.caret && this.explained.lines[String(this.caret.line)];
    const isNameLine = info && info.block != null && !(info.boxes || []).length;
    const lit = (entry) => {
      if (!this.caret || entry.block == null) return false;
      if (isNameLine) return entry.block === info.block;
      return entry.line === this.caret.line;
    };

    this.htmlTarget.innerHTML = this.explained.html
      .map((entry) => {
        const text = "  ".repeat(entry.depth) + entry.text;
        const css = entry.block == null ? "text-gray-400" : lit(entry) ? "bg-amber-100" : "";
        return `<span class="block ${css}">${escape(text)}</span>`;
      })
      .join("");

    this.warningsTarget.innerHTML = this.explained.warnings.map((w) => `<li>${escape(w)}</li>`).join("");
  }

  showHelp() {
    if (!this.caret) return;
    const info = this.explained.lines[String(this.caret.line)];
    if (!info) return;

    const box = (info.boxes || []).find((b) => this.caret.column >= b.from && this.caret.column <= b.to);
    const text = box ? box.text : info.text;
    const css = info.problem && !box ? "text-red-800" : "";
    this.detailTarget.innerHTML = text ? `<p class="${css}">${codeSpans(escape(text))}</p>` : "";
  }
}

function escape(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

// `code` → <code>code</code>, after escaping.
function codeSpans(html) {
  return html.replace(/`([^`]+)`/g, '<code class="bg-gray-100 px-1">$1</code>');
}
