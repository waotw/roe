import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "search",
    "row",
    "count",
    "tab",
    "statusFilter",
    "sortFilter",
    "tbody",
    "tabContainer",
  ];
  static values = { total: Number };

  connect() {
    // Load state from URL params or localStorage
    const params = new URLSearchParams(window.location.search);
    const type =
      params.get("type") || localStorage.getItem("posts_filter_type") || "all";
    const status =
      params.get("status") ||
      localStorage.getItem("posts_filter_status") ||
      "published";
    const sort =
      params.get("sort") ||
      localStorage.getItem("posts_filter_sort") ||
      "date-desc";
    const search = params.get("q") || "";

    // Set initial values
    this.currentType = type;
    this.currentStatus = status;
    this.currentSort = sort;

    // Update UI to match state
    this.setActiveTab(type);
    this.statusFilterTarget.value = status;
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

  filterByStatus(event) {
    this.currentStatus = event.target.value;
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
    let visibleRows = [];

    // Filter rows
    this.rowTargets.forEach((row) => {
      let matches = true;

      // Filter by post type
      if (
        this.currentType !== "all" &&
        row.dataset.postType !== this.currentType
      ) {
        matches = false;
      }

      // Filter by status
      if (
        this.currentStatus !== "all" &&
        row.dataset.status !== this.currentStatus
      ) {
        matches = false;
      }

      // Filter by search query
      if (query && !row.dataset.searchable.includes(query)) {
        matches = false;
      }

      if (matches) {
        row.style.display = "";
        visibleRows.push(row);
      } else {
        row.style.display = "none";
      }
    });

    // Sort visible rows
    this.sortRows(visibleRows);

    // Update count
    this.countTarget.textContent = visibleRows.length;
  }

  sortRows(rows) {
    const [field, direction] = this.currentSort.split("-");

    rows.sort((a, b) => {
      let aVal, bVal;

      switch (field) {
        case "date":
          aVal = parseInt(a.dataset.date) || 0;
          bVal = parseInt(b.dataset.date) || 0;
          break;
        case "title":
          aVal = a.dataset.title.toLowerCase();
          bVal = b.dataset.title.toLowerCase();
          break;
        case "updated":
          aVal = parseInt(a.dataset.updatedAt) || 0;
          bVal = parseInt(b.dataset.updatedAt) || 0;
          break;
      }

      if (aVal < bVal) return direction === "asc" ? -1 : 1;
      if (aVal > bVal) return direction === "asc" ? 1 : -1;
      return 0;
    });

    // Reorder DOM elements
    rows.forEach((row) => this.tbodyTarget.appendChild(row));
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
    localStorage.setItem("posts_filter_type", this.currentType);
    localStorage.setItem("posts_filter_status", this.currentStatus);
    localStorage.setItem("posts_filter_sort", this.currentSort);
  }

  updateURL() {
    const params = new URLSearchParams();

    if (this.currentType !== "all") params.set("type", this.currentType);
    if (this.currentStatus !== "all") params.set("status", this.currentStatus);
    if (this.currentSort !== "date-desc") params.set("sort", this.currentSort);

    const query = this.searchTarget.value.trim();
    if (query) params.set("q", query);

    const newURL = params.toString()
      ? `${window.location.pathname}?${params.toString()}`
      : window.location.pathname;

    window.history.replaceState({}, "", newURL);
  }
}
