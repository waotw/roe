import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "row",
    "count",
    "tab",
    "search",
    "statusFilter",
    "newsletterStatusFilter",
    "sortFilter",
    "tbody",
  ];
  static values = { total: Number };

  connect() {
    this.filterRows();
    this.restoreStateFromURL();
  }

  filterByTier(event) {
    const tier = event.currentTarget.dataset.tier;
    this.updateTabs(event.currentTarget);
    this.currentTier = tier;
    this.updateURL({ tier });
    this.filterRows();
  }

  filterByStatus(event) {
    this.currentStatus = event.target.value;
    this.updateURL({ status: this.currentStatus });
    this.filterRows();
  }

  // Newsletter status filter
  filterByNewsletterStatus(event) {
    this.currentNewsletterStatus = event.target.value;
    this.updateURL({ newsletter_status: this.currentNewsletterStatus });
    this.filterRows();
  }

  filterBySearch(event) {
    this.searchTerm = event.target.value.toLowerCase();
    this.filterRows();
  }

  sortBy(event) {
    const [field, direction] = event.target.value.split("-");
    this.sortRows(field, direction);
  }

  filterRows() {
    let visibleCount = 0;

    this.rowTargets.forEach((row) => {
      const tierMatch =
        !this.currentTier ||
        this.currentTier === "all" ||
        row.dataset.tier === this.currentTier;
      const statusMatch =
        !this.currentStatus ||
        this.currentStatus === "all" ||
        row.dataset.status === this.currentStatus;
      // Newsletter status matching
      const newsletterStatusMatch =
        !this.currentNewsletterStatus ||
        this.currentNewsletterStatus === "all" ||
        row.dataset.newsletterStatus === this.currentNewsletterStatus;
      const searchMatch =
        !this.searchTerm || row.dataset.searchable.includes(this.searchTerm);

      if (tierMatch && statusMatch && newsletterStatusMatch && searchMatch) {
        row.style.display = "";
        visibleCount++;
      } else {
        row.style.display = "none";
      }
    });

    this.countTarget.textContent = visibleCount;
  }

  sortRows(field, direction) {
    const rows = Array.from(this.rowTargets);

    rows.sort((a, b) => {
      let aVal, bVal;

      switch (field) {
        case "created":
          aVal = parseInt(a.dataset.createdAt);
          bVal = parseInt(b.dataset.createdAt);
          break;
        case "email":
          aVal = a.dataset.email.toLowerCase();
          bVal = b.dataset.email.toLowerCase();
          break;
      }

      if (direction === "asc") {
        return aVal > bVal ? 1 : -1;
      } else {
        return aVal < bVal ? 1 : -1;
      }
    });

    rows.forEach((row) => this.tbodyTarget.appendChild(row));
  }

  updateTabs(activeTab) {
    this.tabTargets.forEach((tab) => {
      tab.classList.remove("border-blue-500", "text-blue-600");
      tab.classList.add("border-transparent", "text-gray-500");
    });

    activeTab.classList.add("border-blue-500", "text-blue-600");
    activeTab.classList.remove("border-transparent", "text-gray-500");
  }

  updateURL(params) {
    const url = new URL(window.location);
    Object.entries(params).forEach(([key, value]) => {
      if (value && value !== "all") {
        url.searchParams.set(key, value);
      } else {
        url.searchParams.delete(key);
      }
    });
    window.history.replaceState({}, "", url);
  }

  restoreStateFromURL() {
    const url = new URL(window.location);
    const tier = url.searchParams.get("tier") || "all";
    const status = url.searchParams.get("status") || "all";
    const newsletterStatus = url.searchParams.get("newsletter_status") || "all";

    this.currentTier = tier;
    this.currentStatus = status;
    this.currentNewsletterStatus = newsletterStatus;

    // Set active tab
    const activeTab = this.tabTargets.find((tab) => tab.dataset.tier === tier);
    if (activeTab) this.updateTabs(activeTab);

    // Set status filter
    if (this.hasStatusFilterTarget) {
      this.statusFilterTarget.value = status;
    }

    // Set newsletter status filter
    if (this.hasNewsletterStatusFilterTarget) {
      this.newsletterStatusFilterTarget.value = newsletterStatus;
    }

    this.filterRows();
  }
}
