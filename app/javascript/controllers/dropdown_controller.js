import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["menu"];

  connect() {
    // Close dropdown when clicking outside
    this.clickOutside = this.clickOutside.bind(this);

    // Always start closed when controller connects
    this.menuTarget.classList.add("hidden");
  }

  toggle(event) {
    event.stopPropagation();

    // Close all other dropdowns first
    document
      .querySelectorAll('[data-controller~="dropdown"]')
      .forEach((dropdown) => {
        if (dropdown !== this.element) {
          const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
          if (menu) {
            menu.classList.add("hidden");
          }
        }
      });

    // Toggle this dropdown
    this.menuTarget.classList.toggle("hidden");

    if (!this.menuTarget.classList.contains("hidden")) {
      // Add click listener to close when clicking outside
      setTimeout(() => {
        document.addEventListener("click", this.clickOutside);
      }, 0);
    } else {
      document.removeEventListener("click", this.clickOutside);
    }
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden");
      document.removeEventListener("click", this.clickOutside);
    }
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutside);
  }
}
