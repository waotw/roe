import { Controller } from "@hotwired/stimulus";

// Adds a podcast entry to the config form without a round trip. ADD NEW used
// to POST, rewrite podcast.yml and reload, which threw away every unsaved edit
// on the page — the same problem + New Release had on the music form.
//
// This clones an existing show's panel rather than rendering a blank one from
// ERB. The podcast block is ~150 lines nested deep in the shared config
// editor, and its category selects are populated server-side from Apple's
// fixed list; cloning inherits all of that for free and leaves that markup
// untouched. The clone is then blanked and re-keyed.
//
// Removal is deliberately NOT handled here. The Danger Zone can also delete a
// show's draft episodes, which isn't a config edit and shouldn't wait for Save.
export default class extends Controller {
  static values = {
    // Fallback for a podcast.yml with no shows in it — nothing to clone, so
    // let the server build the first entry.
    addPath: String,
  };

  // Fields with a meaningful default. Everything else blanks to "".
  static DEFAULTS = {
    language: "en",
    type: "episodic",
    explicit: "false",
    subscribe_display: "links",
  };

  add() {
    const source = this.element.querySelector("[data-tabs-panel][data-tabs-target='panel']");
    if (!source) {
      window.location = this.addPathValue;
      return;
    }

    const oldKey = source.dataset.tabsPanel;
    const newKey = this.nextKey();

    const panel = source.cloneNode(true);
    this.rekey(panel, oldKey, newKey);
    this.blank(panel);
    panel.dataset.tabsPanel = newKey;

    source.parentNode.insertBefore(panel, source.nextSibling);
    this.addTab(newKey);

    // Rebuilds every show's subcategory UI from current form state, including
    // the one just added. Already written to be re-runnable — it clears the
    // dynamic fields first.
    window.setupPodcastCategories?.();

    // The form serializes from the DOM on save, so the new panel is only real
    // once saved. Mark the page dirty so leaving warns.
    window.hasUnsavedChanges = true;
  }

  // new-podcast, new-podcast-2, … matching what the server used to produce.
  nextKey() {
    const taken = new Set(
      Array.from(this.element.querySelectorAll("[data-tabs-panel]")).map(
        (el) => el.dataset.tabsPanel,
      ),
    );

    const base = "new-podcast";
    if (!taken.has(base)) return base;

    let n = 2;
    while (taken.has(`${base}-${n}`)) n += 1;
    return `${base}-${n}`;
  }

  // Every place the old key appears. formToYaml builds the YAML key from
  // data-config-field ("<key>.<subkey>"), so missing one here would merge the
  // new show into the cloned one.
  rekey(panel, oldKey, newKey) {
    const swap = (el, attr, value) => {
      if (value === undefined || value === null) return;
      el.setAttribute(attr, value.replace(oldKey, newKey));
    };

    panel.querySelectorAll("[data-config-field]").forEach((el) => {
      swap(el, "data-config-field", el.dataset.configField);
    });
    panel.querySelectorAll("[name]").forEach((el) => {
      swap(el, "name", el.getAttribute("name"));
    });
    panel.querySelectorAll("[data-podcast-key]").forEach((el) => {
      el.setAttribute("data-podcast-key", newKey);
    });
    panel.querySelectorAll("[data-subcategory-for]").forEach((el) => {
      el.setAttribute("data-subcategory-for", newKey);
    });
    panel.querySelectorAll("[data-podcast-feed-key]").forEach((el) => {
      el.setAttribute("data-podcast-feed-key", newKey);
      el.textContent = newKey;
    });

    // The key input is both the editable key and formToYaml's rename source.
    // For a new show the original IS the new key, so no rename fires until
    // the user edits it.
    const keyInput = panel.querySelector("input[data-podcast-key]");
    if (keyInput) keyInput.value = newKey;
  }

  blank(panel) {
    panel.querySelectorAll("input[data-config-field]").forEach((input) => {
      const field = input.dataset.configField.split(".").pop();
      input.value = this.constructor.DEFAULTS[field] ?? "";
    });

    panel.querySelectorAll("select[data-config-field]").forEach((select) => {
      const field = select.dataset.configField.split(".").pop();
      select.value = this.constructor.DEFAULTS[field] ?? "";
      // A value not in the list leaves selectedIndex at -1, which posts
      // nothing — fall back to the first option.
      if (select.selectedIndex === -1) select.selectedIndex = 0;
    });

    // Subcategory rows belong to the show that was cloned; setupPodcastCategories
    // rebuilds them, but clear them here so nothing flashes in between.
    panel.querySelectorAll(".subcategory-field, .add-subcategory-btn").forEach((el) => el.remove());
  }

  addTab(key) {
    const tabs = this.element.querySelector("[data-tabs-target='tab']")?.parentNode;
    if (!tabs) return;

    const template = tabs.querySelector("[data-tabs-target='tab']");
    const tab = template.cloneNode(true);
    tab.dataset.tabsPanel = key;
    tab.textContent = key;
    tabs.appendChild(tab);

    // Stimulus is already bound via data-action on the clone, so a real click
    // runs the same code path as the user clicking it.
    tab.click();
  }
}
