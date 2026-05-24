import { Controller } from "@hotwired/stimulus";

// Simple tabs controller.
//
// Usage:
//   <div data-controller="tabs">
//     <button data-tabs-target="tab" data-action="click->tabs#show" data-tabs-panel="test">Test</button>
//     <button data-tabs-target="tab" data-action="click->tabs#show" data-tabs-panel="live">Live</button>
//     <div data-tabs-target="panel" data-tabs-panel="test">...</div>
//     <div data-tabs-target="panel" data-tabs-panel="live" class="hidden">...</div>
//   </div>

export default class extends Controller {
  static targets = ["tab", "panel"];

  connect() {
    // Activate the first non-disabled tab on connect
    const firstActive = this.tabTargets.find((t) => !t.disabled);
    if (firstActive) this.activateTab(firstActive);
  }

  show(event) {
    const tab = event.currentTarget;
    if (tab.disabled) return;
    this.activateTab(tab);
  }

  activateTab(activeTab) {
    const panelName = activeTab.dataset.tabsPanel;

    // Update tab styles
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tabsPanel === panelName;
      tab.classList.toggle("border-blue-600", isActive);
      tab.classList.toggle("text-blue-600", isActive);
      tab.classList.toggle("border-transparent", !isActive);
      tab.classList.toggle("text-gray-500", !isActive && !tab.disabled);
    });

    // Show/hide panels
    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.tabsPanel !== panelName);
    });
  }
}
