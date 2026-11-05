import { Controller } from "@hotwired/stimulus";

// The media grid's one rename form. Each card carries only its file name
// and the data to rename it (data-rename-url, data-name, data-extension on
// .inline-rename-container); double-clicking the name copies the form in
// here, filled in, so a library of a thousand files sends one form, not a
// thousand. Saving is the same plain form post as before: the page reloads
// with the result.
export default class extends Controller {
  static targets = ["form"];

  start(event) {
    const display = event.currentTarget;
    const container = display.closest(".inline-rename-container");
    if (!container || container.querySelector("form")) return;

    const form = this.formTarget.content.firstElementChild.cloneNode(true);
    form.action = container.dataset.renameUrl;
    const input = form.querySelector('input[type="text"]');
    input.value = container.dataset.name;
    form.querySelector("[data-extension]").textContent =
      container.dataset.extension;

    display.classList.add("hidden");
    container.appendChild(form);
    requestAnimationFrame(() => {
      input.focus();
      input.select();
    });
  }

  cancel(event) {
    event.stopPropagation();
    this.close(event.target.closest(".inline-rename-container"));
  }

  keydown(event) {
    if (event.key !== "Escape") return;
    event.preventDefault();
    this.close(event.target.closest(".inline-rename-container"));
  }

  // Clicks inside the form mustn't reach the card, which would pick the file.
  stop(event) {
    event.stopPropagation();
  }

  close(container) {
    if (!container) return;
    container.querySelector("form")?.remove();
    container.querySelector(".filename-display")?.classList.remove("hidden");
  }
}
