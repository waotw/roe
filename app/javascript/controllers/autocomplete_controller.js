import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "dropdown"];
  static values = {
    options: Array,
  };

  connect() {
    this.selectedIndex = -1;
    // Close dropdown when clicking outside
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this);
    document.addEventListener("click", this.boundCloseOnClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside);
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideDropdown();
    }
  }

  showDropdown() {
    if (!this.hasDropdownTarget) return;

    const value = this.inputTarget.value.toLowerCase().trim();
    const filtered = this.optionsValue.filter((option) =>
      option.toLowerCase().includes(value),
    );

    if (filtered.length === 0) {
      this.hideDropdown();
      return;
    }

    this.dropdownTarget.innerHTML = filtered
      .map(
        (option, index) =>
          `<div class="autocomplete-option px-3 py-2 cursor-pointer hover:bg-blue-100 text-sm font-mono ${index === this.selectedIndex ? "bg-blue-100" : ""}"
           data-action="click->autocomplete#select"
           data-value="${option}">
        ${option}
      </div>`,
      )
      .join("");

    this.dropdownTarget.classList.remove("hidden");
  }

  hideDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add("hidden");
    }
  }

  filter() {
    this.selectedIndex = -1;
    this.showDropdown();
  }

  select(event) {
    const value = event.currentTarget.dataset.value;
    this.inputTarget.value = value;
    this.hideDropdown();
    this.inputTarget.focus();

    // Trigger change event for metadata editor
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }));
  }

  navigate(event) {
    if (
      !this.hasDropdownTarget ||
      this.dropdownTarget.classList.contains("hidden")
    ) {
      if (event.key === "ArrowDown") {
        event.preventDefault();
        this.showDropdown();
      }
      return;
    }

    const options = this.dropdownTarget.querySelectorAll(
      ".autocomplete-option",
    );

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.selectedIndex = Math.min(
          this.selectedIndex + 1,
          options.length - 1,
        );
        this.updateSelection(options);
        break;
      case "ArrowUp":
        event.preventDefault();
        this.selectedIndex = Math.max(this.selectedIndex - 1, -1);
        this.updateSelection(options);
        break;
      case "Enter":
        event.preventDefault();
        if (this.selectedIndex >= 0 && options[this.selectedIndex]) {
          options[this.selectedIndex].click();
        }
        break;
      case "Escape":
        event.preventDefault();
        this.hideDropdown();
        break;
    }
  }

  updateSelection(options) {
    options.forEach((option, index) => {
      if (index === this.selectedIndex) {
        option.classList.add("bg-blue-100");
        option.scrollIntoView({ block: "nearest" });
      } else {
        option.classList.remove("bg-blue-100");
      }
    });
  }
}
