import { Controller } from "@hotwired/stimulus";

// Puts an "Edit release →" link beside the `release` select on a music post,
// pointing at that release's section of Music settings — or at the settings
// page itself when nothing is chosen yet. Saves hunting through a config file
// to change a cover or a release date.
//
// Deliberately separate from metadata-editor: that controller owns the field
// rows and rebuilds them when post_type changes, so the link is attached from
// the outside and re-attached when the rows change, rather than being woven
// into markup that gets regenerated.
export default class extends Controller {
  static values = { settingsPath: String };

  connect() {
    this.onChange = (event) => {
      if (event.target?.dataset?.metadataField === "release") this.render();
    };
    this.element.addEventListener("change", this.onChange);

    // post_type switching adds and removes rows, so watch for the select
    // appearing rather than assuming it's here on connect.
    this.observer = new MutationObserver(() => this.render());
    this.observer.observe(this.element, { childList: true, subtree: true });

    this.render();
  }

  disconnect() {
    this.element.removeEventListener("change", this.onChange);
    this.observer?.disconnect();
    this.observer = null;
  }

  get select() {
    return this.element.querySelector('select[data-metadata-field="release"]');
  }

  // Writing the link is itself a DOM change, which the observer would see and
  // call this again — so pause it around the write, and only write when
  // something actually differs.
  render() {
    const select = this.select;
    if (!select) return;

    const row = select.closest(".metadata-field-row") || select.parentElement;
    const key = select.value.trim();
    const text = key ? "Edit release →" : "Music settings →";
    const href = key
      ? `${this.settingsPathValue}#release-${key}`
      : this.settingsPathValue;

    let link = row.querySelector("[data-release-link]");
    if (link && link.textContent === text && link.getAttribute("href") === href) {
      return;
    }

    this.observer?.disconnect();

    if (!link) {
      link = document.createElement("a");
      link.dataset.releaseLink = "";
      link.target = "_blank";
      link.rel = "noopener";
      link.className =
        "text-xs text-blue-600 hover:text-blue-800 underline shrink-0 pt-1.5 whitespace-nowrap";
      // After the select, before the remove button, so the row reads
      // label → control → link → ✕.
      select.insertAdjacentElement("afterend", link);
    }
    link.textContent = text;
    link.setAttribute("href", href);

    this.observer?.observe(this.element, { childList: true, subtree: true });
  }
}
