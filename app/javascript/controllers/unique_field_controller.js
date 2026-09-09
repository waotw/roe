import { Controller } from "@hotwired/stimulus";

// Warns when a value a writer expects to be unique is already in use —
// url_name, episode_number, track_number, chapter_number. Advisory only:
// nothing here blocks a save, because a clash is sometimes deliberate.
//
// Deliberately shaped like media_field_controller (its sibling on the same
// rows): a wrapper div holds the controller, the input reports changes, and a
// <p> target carries the message. The server renders the initial state, so an
// existing conflict is visible the moment the editor opens; this keeps it
// current as you type.
//
// Targets:
//   input   (required) — the text input holding the value
//   warning (required) — the element that shows the message
//
// Values:
//   field       — which field this is (episode_number, url_name, …)
//   scopeFields — the metadata fields that scope it (podcast + season, release)
//   exclude     — this post's url_name, so it doesn't flag itself
export default class extends Controller {
  static targets = ["input", "warning"];
  static values = { field: String, scopeFields: Array, exclude: String };

  connect() {
    this._timer = null;
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer);
  }

  checkDebounced() {
    if (this._timer) clearTimeout(this._timer);
    this._timer = setTimeout(() => this.check(), 300);
  }

  check() {
    if (!this.hasInputTarget) return;

    const value = this.inputTarget.value.trim();
    if (!value) return this.hide();

    const params = new URLSearchParams({
      field: this.fieldValue,
      value,
      exclude: this.excludeValue || "",
    });
    // A number only clashes inside its own show AND season, so send each scope.
    // Read live from the sibling fields — changing the season changes the answer.
    Object.entries(this.scopes()).forEach(([name, val]) => {
      params.append(`scopes[${name}]`, val);
    });

    fetch(`/admin/posts/check_unique?${params}`, {
      headers: { "X-Requested-With": "XMLHttpRequest" },
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!data || !data.taken) return this.hide();
        this.show(data.conflict);
      })
      .catch(() => this.hide());
  }

  // Current value of each scope field, read from its row in the editor. A field
  // the post doesn't have yet reads as blank, which matches how the server
  // compares unset against unset.
  scopes() {
    const out = {};
    (this.scopeFieldsValue || []).forEach((name) => {
      const el = document.querySelector(`[data-metadata-field="${name}"]`);
      out[name] = el ? el.value.trim() : "";
    });
    return out;
  }

  show(conflictTitle) {
    if (!this.hasWarningTarget) return;
    const where = conflictTitle ? `“${conflictTitle}”` : "another post";
    this.warningTarget.textContent = `⚠ Already used by ${where}.`;
    this.warningTarget.classList.remove("hidden");
  }

  hide() {
    if (!this.hasWarningTarget) return;
    this.warningTarget.classList.add("hidden");
  }
}
