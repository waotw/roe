import { Controller } from "@hotwired/stimulus";

// A <details> that remembers whether it was left open or closed, per
// browser. The HTML decides the first visit (`open` or not); after that,
// the last choice wins.
export default class extends Controller {
  static values = { key: String };

  connect() {
    const saved = this.read();
    if (saved === "open") this.element.open = true;
    if (saved === "closed") this.element.open = false;
  }

  save() {
    try {
      localStorage.setItem(this.keyValue, this.element.open ? "open" : "closed");
    } catch {
      // Private browsing or storage turned off: it just won't be remembered.
    }
  }

  read() {
    try {
      return localStorage.getItem(this.keyValue);
    } catch {
      return null;
    }
  }
}
