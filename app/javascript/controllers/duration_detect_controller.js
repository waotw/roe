import { Controller } from "@hotwired/stimulus";
import { autoDurationOn, detectDuration } from "media_duration";

// The duration field, both ways Content → Global → "Automatically add
// audio and video duration" can be set.
//
// On — Roe keeps the field: grey, read-only and marked SET BY ROE whenever
// it can read the file's length. Change the post's audio or video (typing,
// pasting, picking from the list) and the duration drops to 00:00:00, then
// fills in once you pause — no need to leave the field. A length Roe can't
// read (a missing file, a link to another site) unlocks the field with a
// note, so it can be typed in. The save does the same check on the server
// (Admin::PostsController#apply_auto_duration!), so this is what you'll get.
//
// Off — the field is the writer's, with ADD DURATION beside it to read the
// length once.
//
// Sits on the metadata form and on the publish modal's media section. The
// form rebuilds its rows (Restore, RAW and back, a post type adding its
// fields), so rather than reach into metadata_editor_controller this
// watches for duration fields as they appear and looks after each one.
//
// The length is the post's audio, else its video — audio is what the
// feed sends.
const FIELDS =
  '[data-metadata-field="duration"], [data-media-field-target="duration"]';
const SOURCES =
  '[data-metadata-field="audio"], [data-metadata-field="video"], [data-media-field-target="input"]';
// The look a read-only field already has in the form (_metadata_editor).
const LOCKED = ["bg-gray-200", "text-gray-600"];
// How long a pause in typing before the length is read.
const PAUSE_MS = 400;
const BLANK = "00:00:00";

export default class extends Controller {
  connect() {
    this.auto = autoDurationOn();
    this.fields = new WeakMap();

    this.decorate();
    this.observer = new MutationObserver(() => this.decorate());
    this.observer.observe(this.element, { childList: true, subtree: true });

    if (this.auto) {
      this.onSourceInput = (event) => {
        if (event.target.matches?.(SOURCES)) this.sourceChanged(event.target);
      };
      this.element.addEventListener("input", this.onSourceInput);
    }
  }

  disconnect() {
    this.observer?.disconnect();
    if (this.onSourceInput) {
      this.element.removeEventListener("input", this.onSourceInput);
    }
  }

  decorate() {
    this.element.querySelectorAll(FIELDS).forEach((input) => {
      if (input.dataset.durationDetect) return;
      input.dataset.durationDetect = "ready";
      if (this.auto) {
        this.manage(input);
      } else {
        this.addButton(input);
      }
    });
  }

  // ── On: Roe keeps the field ───────────────────────────────────────────

  manage(input) {
    const note = document.createElement("span");
    note.className =
      "flex-shrink-0 self-center whitespace-nowrap text-xs uppercase text-gray-500";
    note.dataset.durationDetectNote = "";
    input.insertAdjacentElement("afterend", note);

    const state = {
      note,
      path: this.mediaPathFor(input),
      before: input.value,
      placeholder: input.placeholder,
      seq: 0,
    };
    this.fields.set(input, state);

    if (this.pendingRow) {
      // A row just added because a file was entered: treat it as a change.
      this.pendingRow = false;
      state.path = null;
      this.schedule(input);
    } else if (state.path) {
      // On load: check the post's file. Shown, not marked as an edit — the
      // save sets the same length.
      this.read(input, state.path, { quiet: true });
    }
  }

  sourceChanged(source) {
    const inputs = this.durationsFor(source);
    if (inputs.length === 0) {
      this.addRowFor(source);
      return;
    }
    inputs.forEach((input) => this.schedule(input));
  }

  // The media changed: blank the length, then read it after a pause.
  schedule(input) {
    const state = this.fields.get(input);
    if (!state) return;

    const path = this.mediaPathFor(input);
    if (path === state.path) return; // e.g. video edited while audio wins
    state.path = path;
    clearTimeout(state.timer);
    state.seq++;

    if (!path) {
      input.value = state.before;
      input.placeholder = state.placeholder;
      this.unlock(input, "");
      return;
    }

    // Shown as 00:00:00 but left empty: anything that saves the form
    // meanwhile mustn't write a made-up length.
    input.value = "";
    input.placeholder = BLANK;
    // COPY: duration — reading
    this.lock(input, "Reading…");
    state.timer = setTimeout(() => this.read(input, path), PAUSE_MS);
  }

  async read(input, path, { quiet = false } = {}) {
    const state = this.fields.get(input);
    const seq = ++state.seq;
    // COPY: duration — set by Roe
    this.lock(input, quiet ? "Set by Roe" : "Reading…");

    try {
      const length = await detectDuration(path);
      if (seq !== state.seq) return; // the file changed again meanwhile
      const changed = input.value !== length;
      input.value = length;
      input.placeholder = state.placeholder;
      state.before = length;
      this.lock(input, "Set by Roe");
      if (changed && !quiet) {
        // A row the form added for us has no change listener yet.
        this.application
          .getControllerForElementAndIdentifier(this.element, "metadata-editor")
          ?.attachChangeListeners?.();
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
      }
    } catch (_error) {
      if (seq !== state.seq) return;
      input.value = state.before;
      input.placeholder = state.placeholder;
      // COPY: duration — Roe couldn't read the file
      this.unlock(input, "Couldn't read the length. Type it in.");
    }
  }

  lock(input, text) {
    const state = this.fields.get(input);
    input.readOnly = true;
    input.classList.add(...LOCKED);
    // COPY: duration — tooltip while Roe keeps it
    input.title =
      "Roe sets this from the file. Turn it off in Content → Global → Automatically add audio and video duration.";
    if (state) state.note.textContent = text;
  }

  unlock(input, text) {
    const state = this.fields.get(input);
    input.readOnly = false;
    input.classList.remove(...LOCKED);
    input.removeAttribute("title");
    if (state) {
      state.note.textContent = text;
      state.note.classList.toggle("normal-case", Boolean(text));
    }
  }

  // The duration fields a changed media field feeds: in the publish modal,
  // the one in the same media section; on the form, the post's own
  // (unless the post type keeps it hidden).
  durationsFor(source) {
    const section = this.modalSection(source);
    if (section) {
      return Array.from(section.querySelectorAll('[data-media-field-target="duration"]'));
    }
    return Array.from(this.element.querySelectorAll('[data-metadata-field="duration"]'))
      .filter((input) => input.closest(".metadata-field-row")?.style.display !== "none");
  }

  // The publish modal's media section: a media-field that holds its own
  // duration. (The form's audio and video fields are media-fields too —
  // for their "file not found" warning — but their duration is the post's.)
  modalSection(element) {
    const section = element.closest('[data-controller~="media-field"]');
    return section?.querySelector('[data-media-field-target="duration"]') ? section : null;
  }

  // A file entered on a post with no duration row yet (the form drops the
  // row while there's no media): have the form add one, the way it does
  // when it reads a length itself. Only for types that have a duration.
  addRowFor(source) {
    if (this.modalSection(source)) return;
    if (!this.mediaPathFor(source)) return;

    const form = this.application.getControllerForElementAndIdentifier(
      this.element,
      "metadata-editor",
    );
    if (!form || typeof form.addDurationField !== "function") return;

    const type = this.element.querySelector('[data-metadata-field="post_type"]')?.value;
    if (!form.getFieldsForType?.(type)?.includes("duration")) return;

    this.pendingRow = true;
    form.addDurationField("");
  }

  // ── Off: ADD DURATION ─────────────────────────────────────────────────

  addButton(input) {
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

  // ── Both ──────────────────────────────────────────────────────────────

  // The publish modal pairs a duration with its own media field; the
  // metadata form has the post's audio and video fields, audio first.
  mediaPathFor(input) {
    const field = this.modalSection(input);
    if (field) {
      return field
        .querySelector('[data-media-field-target="input"]')
        ?.value.trim() || "";
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
