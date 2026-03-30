import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["search", "item", "count", "tab", "sortFilter", "grid"];
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

  filterBySearch(event) {
    this.updateURL();
    this.applyFilters();
  }

  applyFilters() {
    const query = this.searchTarget.value.toLowerCase().trim();
    let visibleItems = [];

    // Filter items
    this.itemTargets.forEach((item) => {
      let matches = true;

      // Filter by media type
      if (
        this.currentType !== "all" &&
        item.dataset.mediaType !== this.currentType
      ) {
        matches = false;
      }

      // Filter by search query
      if (query && !item.dataset.searchable.includes(query)) {
        matches = false;
      }

      if (matches) {
        item.style.display = "";
        visibleItems.push(item);
      } else {
        item.style.display = "none";
      }
    });

    // Sort visible items
    this.sortItems(visibleItems);

    // Update count
    this.countTarget.textContent = visibleItems.length;
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
