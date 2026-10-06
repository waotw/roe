import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "row",
    "count",
    "search",
    "tierFilter",
    "importedFilter",
    "statusFilter",
    "newsletterStatusFilter",
    "sortFilter",
    "tbody",
  ];
  static values = { total: Number };

  connect() {
    this.restoreStateFromURL();
    this.filterRows();
  }

  // Tier is now a set of checkboxes (Free / Paid) rather than tabs. The checked
  // set is the filter: none checked OR all checked = show everything, since
  // filtering to "both" is the same as not filtering.
  filterByTier() {
    this.filterRows();
  }

  filterByImported() {
    this.filterRows();
  }

  filterByStatus(event) {
    this.currentStatus = event.target.value;
    this.updateURL({ status: this.currentStatus });
    this.filterRows();
  }

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

  // The tiers currently checked. Empty set means "no tier filter".
  checkedTiers() {
    if (!this.hasTierFilterTarget) return [];
    return this.tierFilterTargets
      .filter((cb) => cb.checked)
      .map((cb) => cb.value);
  }

  importedOnly() {
    return this.hasImportedFilterTarget && this.importedFilterTarget.checked;
  }

  filterRows() {
    const tiers = this.checkedTiers();
    const importedOnly = this.importedOnly();
    let visibleCount = 0;

    this.rowTargets.forEach((row) => {
      // Empty or both-checked = match any tier.
      const tierMatch =
        tiers.length === 0 || tiers.includes(row.dataset.tier);
      const importedMatch = !importedOnly || row.dataset.imported === "1";
      const statusMatch =
        !this.currentStatus ||
        this.currentStatus === "all" ||
        row.dataset.status === this.currentStatus;
      const newsletterStatusMatch =
        !this.currentNewsletterStatus ||
        this.currentNewsletterStatus === "all" ||
        row.dataset.newsletterStatus === this.currentNewsletterStatus;
      const searchMatch =
        !this.searchTerm || row.dataset.searchable.includes(this.searchTerm);

      if (
        tierMatch &&
        importedMatch &&
        statusMatch &&
        newsletterStatusMatch &&
        searchMatch
      ) {
        row.style.display = "";
        visibleCount++;
      } else {
        row.style.display = "none";
      }
    });

    if (this.hasCountTarget) this.countTarget.textContent = visibleCount;

    // Tell the bulk-select controller the visible set changed, so it can drop
    // now-hidden rows from the selection and refresh its "select all visible"
    // count. Both controllers live on the same root element.
    this.dispatch("changed");
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
    const status = url.searchParams.get("status") || "all";
    const newsletterStatus = url.searchParams.get("newsletter_status") || "all";

    this.currentStatus = status;
    this.currentNewsletterStatus = newsletterStatus;

    if (this.hasStatusFilterTarget) {
      this.statusFilterTarget.value = status;
    }
    if (this.hasNewsletterStatusFilterTarget) {
      this.newsletterStatusFilterTarget.value = newsletterStatus;
    }
  }
}
