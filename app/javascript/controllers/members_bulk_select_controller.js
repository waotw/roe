import { Controller } from "@hotwired/stimulus";

// Multi-select + bulk actions for the Members index. Same shape as
// bulk_select_controller (SELECT toggle reveals a checkbox column; a toolbar
// appears when rows are picked; select-all-visible respects the client-side
// filter via offsetParent), but with members-specific actions: delete (erase/
// anonymise server-side), tier up/down, and newsletter subscribe/unsubscribe.
//
// The tier buttons adapt to the selection: all-free shows Upgrade, all-paid
// shows Downgrade, mixed shows both (each makes the whole selection that tier).
export default class extends Controller {
  static targets = [
    "checkbox", "selectColumn", "toggle", "toolbar", "count", "visibleCount",
    "upgradeButton", "downgradeButton", "subscribeButton", "unsubscribeButton",
    "normalAction",
    "purgeButton", "purgeModal", "purgeIds", "purgeInput", "purgeSubmit",
    "deleteModal", "deleteIds", "deleteInput", "deleteSubmit",
    "formIds",
  ];

  connect() {
    this.selecting = false;
    this.update();
  }

  toggleMode(event) {
    event.preventDefault();
    this.selecting = !this.selecting;
    this.selectColumnTargets.forEach((el) => el.classList.toggle("hidden", !this.selecting));
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = this.selecting ? "Cancel" : "Select";
      this.toggleTarget.classList.toggle("bg-white", !this.selecting);
      this.toggleTarget.classList.toggle("bg-gray-800", this.selecting);
      this.toggleTarget.classList.toggle("text-white", this.selecting);
    }
    if (!this.selecting) {
      this.checkboxTargets.forEach((cb) => (cb.checked = false));
    }
    this.update();
  }

  // "Select all visible (N)" — only rows the current filter leaves shown
  // (filtered-out rows are display:none, so offsetParent is null). Explicit,
  // unlike a header checkbox that silently affected only visible rows.
  selectAllVisible() {
    this.checkboxTargets.forEach((cb) => {
      if (this.isVisible(cb)) cb.checked = true;
    });
    this.update();
  }

  clearSelection() {
    this.checkboxTargets.forEach((cb) => (cb.checked = false));
    this.update();
  }

  // Filters changed (members-filter:changed). Uncheck any row that's now
  // hidden so a filtered-out selection truly drops — otherwise re-showing it
  // later would resurrect a stale selection — then refresh the toolbar counts.
  refresh() {
    this.checkboxTargets.forEach((cb) => {
      if (!this.isVisible(cb)) cb.checked = false;
    });
    this.update();
  }

  isVisible(cb) {
    return cb.offsetParent !== null;
  }

  selected() {
    return this.checkboxTargets.filter((cb) => cb.checked && this.isVisible(cb));
  }

  visibleCheckboxes() {
    return this.checkboxTargets.filter((cb) => this.isVisible(cb));
  }

  update() {
    const selected = this.selected();
    if (selected.length === 0 || !this.selecting) {
      this.toolbarTarget.classList.add("hidden");
      return;
    }
    this.toolbarTarget.classList.remove("hidden");
    this.countTarget.textContent = selected.length;

    // Show the visible-row count on the "Select all visible" button so it's
    // clear how many it will pick (and that it's only the visible ones).
    if (this.hasVisibleCountTarget) {
      this.visibleCountTarget.textContent = ` (${this.visibleCheckboxes().length})`;
    }

    // Purge mode: when EVERY selected row is an already-deleted (anonymised)
    // account, the only valid action is the permanent purge — you can't
    // upgrade, subscribe or re-anonymise a tombstone. Swap the toolbar to a
    // single PERMANENTLY DELETE button with its own heavy modal. Any live
    // member in the selection drops back to the normal actions.
    const allDeleted = selected.every((cb) => cb.dataset.deleted === "1");
    this.setPurgeMode(allDeleted);
    if (allDeleted) return;

    // Normal tier buttons by selection composition.
    const tiers = new Set(selected.map((cb) => cb.dataset.tier));
    if (this.hasUpgradeButtonTarget) {
      this.upgradeButtonTarget.classList.toggle("hidden", !tiers.has("free"));
    }
    if (this.hasDowngradeButtonTarget) {
      this.downgradeButtonTarget.classList.toggle("hidden", !tiers.has("paid"));
    }

    // Newsletter buttons by status composition: Subscribe only when someone
    // selected could actually be subscribed (currently unsubscribed — bounced
    // can't resubscribe, so it doesn't count); Unsubscribe only when someone is
    // currently subscribed. Both show for a mixed selection.
    const statuses = new Set(selected.map((cb) => cb.dataset.newsletterStatus));
    if (this.hasSubscribeButtonTarget) {
      this.subscribeButtonTarget.classList.toggle("hidden", !statuses.has("unsubscribed"));
    }
    if (this.hasUnsubscribeButtonTarget) {
      this.unsubscribeButtonTarget.classList.toggle("hidden", !statuses.has("subscribed"));
    }
  }

  // Toggle every normal action off and the purge button on (or vice versa).
  setPurgeMode(on) {
    this.normalActionTargets.forEach((el) => el.classList.toggle("hidden", on));
    if (this.hasPurgeButtonTarget) this.purgeButtonTarget.classList.toggle("hidden", !on);
  }

  // ── Delete (type-DELETE confirm) ────────────────────────────────────────
  openDelete(event) {
    event.preventDefault();
    const selected = this.selected();
    if (selected.length === 0) return;
    this.fillIds(this.deleteIdsTarget, selected);
    this.deleteInputTarget.value = "";
    this.deleteSubmitTarget.disabled = true;
    this.deleteModalTarget.classList.remove("hidden");
    this.deleteInputTarget.focus();
  }

  deleteInputChanged() {
    this.deleteSubmitTarget.disabled = this.deleteInputTarget.value !== "DELETE";
  }

  deleteInputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      if (this.deleteInputTarget.value === "DELETE") {
        this.deleteSubmitTarget.form.requestSubmit();
      }
    } else if (event.key === "Escape") {
      this.closeModals();
    }
  }

  closeModals(event) {
    if (event) event.preventDefault();
    if (this.hasDeleteModalTarget) this.deleteModalTarget.classList.add("hidden");
    if (this.hasPurgeModalTarget) this.purgeModalTarget.classList.add("hidden");
  }

  // ── Purge (permanent, deleted accounts only) ─────────────────────────────
  openPurge(event) {
    event.preventDefault();
    const selected = this.selected();
    if (selected.length === 0) return;
    this.fillIds(this.purgeIdsTarget, selected);
    this.purgeInputTarget.value = "";
    this.purgeSubmitTarget.disabled = true;
    this.purgeModalTarget.classList.remove("hidden");
    this.purgeInputTarget.focus();
  }

  purgeInputChanged() {
    this.purgeSubmitTarget.disabled = this.purgeInputTarget.value !== "DELETE";
  }

  purgeInputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      if (this.purgeInputTarget.value === "DELETE") {
        this.purgeSubmitTarget.form.requestSubmit();
      }
    } else if (event.key === "Escape") {
      this.closeModals();
    }
  }

  // ── Tier + newsletter: fill the clicked form's ids, then submit ──────────
  submitTier(event) {
    this.fillAndSubmit(event);
  }

  submitNewsletter(event) {
    this.fillAndSubmit(event);
  }

  // The button lives inside its own form carrying a hidden ids container
  // (data-members-bulk-select-target="formIds") plus its fixed param (tier or
  // newsletter value). Fill the current selection and submit.
  fillAndSubmit(event) {
    event.preventDefault();
    const selected = this.selected();
    if (selected.length === 0) return;
    const form = event.currentTarget.closest("form");
    const container = form.querySelector("[data-members-bulk-select-target='formIds']");
    this.fillIds(container, selected);
    form.requestSubmit();
  }

  fillIds(container, checkboxes) {
    container.innerHTML = "";
    checkboxes.forEach((cb) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "ids[]";
      input.value = cb.dataset.id;
      container.appendChild(input);
    });
  }
}
