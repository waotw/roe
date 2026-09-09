import { Controller } from "@hotwired/stimulus";

// Music settings: swaps between the structured release form and the raw YAML
// escape hatch. Deliberately its own controller rather than the site config
// editor's toggleConfigView() — that one is a global function tied to the
// 2000-line shared editor, and music.yml is nested a level deeper than
// anything that form handles.
//
// The two views are separate <form>s posting to the same action, so only the
// one on screen can be submitted. Nothing is copied between them: whichever
// you save is what gets written.
export default class extends Controller {
  static targets = [
    "formView",
    "yamlView",
    "yamlToggle",
    "list",
    "template",
    "release",
    "empty",
  ];

  // Add and remove are DOM-only: update_music rebuilds the release list from
  // whatever rows are posted, so nothing is written until Save. That's the
  // point — clicking + New Release used to save the file and reload, which
  // threw away every unsaved edit on the page.
  addRelease() {
    const row = this.templateTarget.content.firstElementChild.cloneNode(true);

    // Give the new row its own array index. The template ships __INDEX__ in
    // every name so one replacement covers key, original_key and every field.
    const index = this.nextIndex();
    row.querySelectorAll("[name]").forEach((input) => {
      input.name = input.name.replace("__INDEX__", index);
    });

    this.listTarget.appendChild(row);
    this.refreshEmpty();
    row.querySelector('[data-music-releases-target="keyInput"]')?.focus();
    row.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  removeRelease(event) {
    const row = event.target.closest('[data-music-releases-target="release"]');
    if (!row) return;

    const key = row
      .querySelector('[name$="[original_key]"]')
      ?.value.trim();

    // Only confirm for a release that's actually in the file. Discarding a row
    // you just added isn't worth a dialog.
    const message = key
      ? `Remove “${key}” when you save? Tracks that name it keep their release: value — they just stop inheriting from it.`
      : null;
    if (message && !window.confirm(message)) return;

    row.remove();
    this.refreshEmpty();
  }

  // Indices only have to be unique within the post, not contiguous —
  // update_music reads params[:releases].values and ignores the keys.
  nextIndex() {
    const used = this.releaseTargets
      .flatMap((row) => Array.from(row.querySelectorAll("[name]")))
      .map((input) => Number(input.name.match(/^releases\[(\d+)\]/)?.[1]))
      .filter((n) => !Number.isNaN(n));

    return used.length ? Math.max(...used) + 1 : 0;
  }

  refreshEmpty() {
    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", this.releaseTargets.length > 0);
    }
  }

  toggleYaml() {
    const showingYaml = !this.yamlViewTarget.classList.contains("hidden");

    this.yamlViewTarget.classList.toggle("hidden", showingYaml);
    this.formViewTarget.classList.toggle("hidden", !showingYaml);
    this.yamlToggleTarget.textContent = showingYaml ? "EDIT YAML" : "EDIT FORM";
  }
}
