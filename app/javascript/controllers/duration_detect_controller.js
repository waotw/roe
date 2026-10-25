import { Controller } from "@hotwired/stimulus";
import { autoDurationOn, detectDuration } from "media_duration";

// ADD DURATION, beside each duration field, when Content → Global →
// "Automatically add audio and video duration" is off. With it on there's
// nothing to add: Roe fills the field itself (media_duration.js, and on
// save Admin::PostsController#apply_auto_duration!).
//
// Sits on the metadata form and on the publish modal's media section. The
// form rebuilds its rows (Restore, RAW and back, a post type adding its
// fields), so rather than reach into metadata_editor_controller this
// watches for duration fields as they appear and gives each one a button.
//
// The button reads the post's audio, else its video — audio is what the
// feed sends — and fills the field once. The writer can keep it, change
// it or clear it; whatever is in the field is what's saved.
const FIELDS =
  '[data-metadata-field="duration"], [data-media-field-target="duration"]';

export default class extends Controller {
  connect() {
    if (autoDurationOn()) return;

    this.decorate();
    this.observer = new MutationObserver(() => this.decorate());
    this.observer.observe(this.element, { childList: true, subtree: true });
  }

  disconnect() {
    this.observer?.disconnect();
  }

  decorate() {
    this.element.querySelectorAll(FIELDS).forEach((input) => {
      if (input.dataset.durationDetect) return;
      input.dataset.durationDetect = "ready";

      const wrap = document.createElement("span");
      wrap.className = "flex flex-shrink-0 items-center gap-2";
      wrap.dataset.durationDetectButton = "";

      const button = document.createElement("button");
      button.type = "button";
      // COPY: ADD DURATION button
      button.textContent = "Add duration";
      button.className =
        "uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-6 leading-none cursor-pointer";
      button.addEventListener("click", () => this.add(input, button, note));

      const note = document.createElement("span");
      note.className = "hidden text-xs text-gray-600";

      wrap.append(button, note);
      input.insertAdjacentElement("afterend", wrap);
    });
  }

  async add(input, button, note) {
    const path = this.mediaPathFor(input);
    note.classList.add("hidden");

    if (!path) {
      // COPY: ADD DURATION — no file
      this.say(note, "Add an audio or video file first.", input);
      return;
    }

    const label = button.textContent;
    button.disabled = true;
    // COPY: ADD DURATION — working
    button.textContent = "Reading…";
    try {
      input.value = await detectDuration(path);
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    } catch (_error) {
      // COPY: ADD DURATION — couldn't read
      this.say(note, "Couldn't read the length. Type it in instead.", input);
    } finally {
      button.disabled = false;
      button.textContent = label;
    }
  }

  // An empty field carries the message as its placeholder, so the field
  // keeps its width; one that already holds a length gets a note beside
  // the button instead, since a placeholder wouldn't show.
  say(note, text, input) {
    if (input && !input.value.trim()) {
      input.placeholder = text;
      return;
    }
    note.textContent = text;
    note.classList.remove("hidden");
  }

  // The publish modal pairs a duration with its own media field; the
  // metadata form has the post's audio and video fields.
  mediaPathFor(input) {
    const field = input.closest('[data-controller~="media-field"]');
    if (field) {
      return field
        .querySelector('[data-media-field-target="input"]')
        ?.value.trim();
    }
    for (const name of ["audio", "video"]) {
      const value = this.element
        .querySelector(`[data-metadata-field="${name}"]`)
        ?.value.trim();
      if (value) return value;
    }
    return "";
  }
}
