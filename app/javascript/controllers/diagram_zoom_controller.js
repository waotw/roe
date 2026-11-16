import { Controller } from "@hotwired/stimulus";

// A diagram that opens large in a <dialog>, where it can be zoomed and moved
// around. Zoom with the − / + buttons, or ⌘/Ctrl + scroll (zooming towards
// the pointer); move by scrolling or dragging. The middle button shows the
// zoom and resets it to fit. Esc (native to <dialog>) or a click on the
// backdrop closes it.
export default class extends Controller {
  static targets = ["dialog", "viewport", "image", "level"];

  static MIN = 1;
  static MAX = 4;
  static STEP = 1.25;

  open() {
    this.dialogTarget.showModal();
    this.setZoom(1);
  }

  close() {
    this.dialogTarget.close();
  }

  // A click on the <dialog> itself (not its contents) is a click on the
  // backdrop around it.
  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close();
  }

  zoomIn() {
    this.zoomAround(this.zoom * this.constructor.STEP);
  }

  zoomOut() {
    this.zoomAround(this.zoom / this.constructor.STEP);
  }

  reset() {
    this.setZoom(1);
  }

  wheel(event) {
    if (!(event.ctrlKey || event.metaKey)) return; // plain scroll moves around
    event.preventDefault();
    const factor = event.deltaY < 0 ? 1.1 : 1 / 1.1;
    this.zoomAround(this.zoom * factor, event.clientX, event.clientY);
  }

  // Zoom keeping the point under (x, y) — the pointer, or the middle of the
  // view — where it is.
  zoomAround(next, x, y) {
    const view = this.viewportTarget;
    const box = view.getBoundingClientRect();
    const px = (x ?? box.left + box.width / 2) - box.left;
    const py = (y ?? box.top + box.height / 2) - box.top;
    const before = this.zoom;
    const fx = (view.scrollLeft + px) / before;
    const fy = (view.scrollTop + py) / before;

    this.setZoom(next);
    const ratio = this.zoom / before;
    view.scrollLeft = fx * before * ratio - px;
    view.scrollTop = fy * before * ratio - py;
  }

  // 1 = the whole diagram fits in the view, by width or height, whichever
  // is tighter. Measured from the view's box rather than clientWidth, which
  // shrinks once a scrollbar appears and would make "fit" overflow.
  setZoom(value) {
    const { MIN, MAX } = this.constructor;
    this.zoom = Math.min(MAX, Math.max(MIN, value));
    this.imageTarget.style.width = `${this.fitWidth() * this.zoom}px`;
    this.levelTarget.textContent = `${Math.round(this.zoom * 100)}%`;
    if (this.zoom === 1) {
      this.viewportTarget.scrollLeft = 0;
      this.viewportTarget.scrollTop = 0;
    }
  }

  fitWidth() {
    const box = this.viewportTarget.getBoundingClientRect();
    const image = this.imageTarget;
    const ratio = image.naturalWidth && image.naturalHeight ? image.naturalWidth / image.naturalHeight : 900 / 470;
    return Math.floor(Math.min(box.width, box.height * ratio)) - 2;
  }

  dragStart(event) {
    if (event.button !== 0) return;
    const view = this.viewportTarget;
    const start = { x: event.clientX, y: event.clientY, left: view.scrollLeft, top: view.scrollTop };
    view.setPointerCapture(event.pointerId);
    view.classList.replace("cursor-grab", "cursor-grabbing");

    const move = (e) => {
      view.scrollLeft = start.left - (e.clientX - start.x);
      view.scrollTop = start.top - (e.clientY - start.y);
    };
    const end = () => {
      view.removeEventListener("pointermove", move);
      view.removeEventListener("pointerup", end);
      view.removeEventListener("pointercancel", end);
      view.classList.replace("cursor-grabbing", "cursor-grab");
    };
    view.addEventListener("pointermove", move);
    view.addEventListener("pointerup", end);
    view.addEventListener("pointercancel", end);
  }
}
