import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "search",
    "item",
    "count",
    "tab",
    "sortFilter",
    "grid",
    "paidToggle",
    "freeToggle",
    "audienceNote",
  ];
  static values = { total: Number };

  connect() {
    // Load state from URL params or localStorage
    const params = new URLSearchParams(window.location.search);
    const type =
      params.get("type") || localStorage.getItem("media_filter_type") || "all";
    const sort =
      params.get("sort") ||
      localStorage.getItem("media_filter_sort") ||
      "date-desc";
    const search = params.get("q") || "";

    // Set initial values
    this.currentType = type;
    this.currentSort = sort;

    // Update UI to match state
    this.setActiveTab(type);
    this.sortFilterTarget.value = sort;
    this.searchTarget.value = search;

    // Apply filters
    this.applyFilters();
  }

  filterByType(event) {
    this.currentType = event.currentTarget.dataset.type;
    this.setActiveTab(this.currentType);
    this.saveState();
    this.updateURL();
    this.applyFilters();
  }

  sortBy(event) {
    this.currentSort = event.target.value;
    this.saveState();
    this.updateURL();
    this.applyFilters();
  }

  filterByAudience() {
    this.applyFilters();
  }

  // Two predicates, not a union:
  //   neither → everything
  //   one     → files with that audience
  //   both    → files that are somehow both, i.e. referenced by paid content
  //             but resolved free because something public uses them too
  //
  // A file's audience is single-valued, so "both" can't mean an intersection
  // of the column. It means the mixed flag, which is the case worth finding —
  // a file you meant to protect that's public because of another reference.
  matchesAudience(item) {
    const paid = this.hasPaidToggleTarget && this.paidToggleTarget.checked;
    const free = this.hasFreeToggleTarget && this.freeToggleTarget.checked;

    if (!paid && !free) return true;
    if (paid && free) return item.dataset.mixed === "true";
    if (paid) return item.dataset.audience === "paid";
    return item.dataset.audience === "free";
  }

  // Says what the current toggle state actually means, so "both checked shows
  // fewer than one checked" reads as intended rather than as a bug.
  updateAudienceNote() {
    if (!this.hasAudienceNoteTarget) return;

    const paid = this.hasPaidToggleTarget && this.paidToggleTarget.checked;
    const free = this.hasFreeToggleTarget && this.freeToggleTarget.checked;

    let note = "";
    if (paid && free) note = " used by both paid and free content";
    else if (paid) note = " protected from the public";
    else if (free) note = " readable by anyone";

    this.audienceNoteTarget.textContent = note;
  }

  filterBySearch(event) {
    this.updateURL();
    this.applyFilters();
  }

  applyFilters() {
    const query = this.searchTarget.value.toLowerCase().trim();
    let visibleItems = [];

    this.itemTargets.forEach((item) => {
      let matches = true;

      // Filter by type, unused, or global (referenced by a config file) status
      if (this.currentType === "unused") {
        matches = item.dataset.hasReferences === "false";
      } else if (this.currentType === "global") {
        matches = item.dataset.usageGlobal === "true";
      } else if (this.currentType !== "all") {
        matches = item.dataset.mediaType === this.currentType;
      }

      // Filter by search query
      if (query && !item.dataset.searchable.includes(query)) {
        matches = false;
      }

      if (matches && !this.matchesAudience(item)) {
        matches = false;
      }

      if (matches) {
        item.style.display = "";
        visibleItems.push(item);
      } else {
        item.style.display = "none";
      }
    });

    this.sortItems(visibleItems);
    this.countTarget.textContent = visibleItems.length;
    this.updateAudienceNote();
  }

  sortItems(items) {
    const [field, direction] = this.currentSort.split("-");

    items.sort((a, b) => {
      let aVal, bVal;

      switch (field) {
        case "date":
          aVal = parseInt(a.dataset.uploadedAt) || 0;
          bVal = parseInt(b.dataset.uploadedAt) || 0;
          break;
        case "name":
          aVal = a.dataset.filename;
          bVal = b.dataset.filename;
          break;
        case "size":
          aVal = parseInt(a.dataset.fileSize) || 0;
          bVal = parseInt(b.dataset.fileSize) || 0;
          break;
      }

      if (aVal < bVal) return direction === "asc" ? -1 : 1;
      if (aVal > bVal) return direction === "asc" ? 1 : -1;
      return 0;
    });

    // Reorder DOM elements
    items.forEach((item) => this.gridTarget.appendChild(item));
  }

  setActiveTab(type) {
    this.tabTargets.forEach((tab) => {
      if (tab.dataset.type === type) {
        tab.classList.remove("border-transparent", "text-gray-500");
        tab.classList.add("border-blue-500", "text-blue-600");
      } else {
        tab.classList.add("border-transparent", "text-gray-500");
        tab.classList.remove("border-blue-500", "text-blue-600");
      }
    });
  }

  saveState() {
    localStorage.setItem("media_filter_type", this.currentType);
    localStorage.setItem("media_filter_sort", this.currentSort);
  }

  updateURL() {
    const params = new URLSearchParams();

    if (this.currentType !== "all") params.set("type", this.currentType);
    if (this.currentSort !== "date-desc") params.set("sort", this.currentSort);

    const query = this.searchTarget.value.trim();
    if (query) params.set("q", query);

    const newURL = params.toString()
      ? `${window.location.pathname}?${params.toString()}`
      : window.location.pathname;

    window.history.replaceState({}, "", newURL);
  }
}
