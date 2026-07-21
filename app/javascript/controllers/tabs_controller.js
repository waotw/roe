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
  // The URL query key this instance persists into. Defaults to "tab" so
  // existing usages are unchanged; a nested instance sets its own key
  // (data-tabs-param-value="…") so it doesn't fight the outer tabs over
  // the same param. Stimulus scopes targets to the nearest controller, so
  // nesting the same controller is safe.
  static values = { param: { type: String, default: "tab" }, default: String };

  connect() {
    // Read ?<param>=panel-name from the URL. Query params survive Turbo
    // Drive's redirect handling (URL fragments don't — fetch strips
    // them when following the 302). Server redirects after save / test
    // include the tab via `redirect_to ..., tab: "panel-name"`.
    //
    // Precedence: an explicit ?tab= (a manual click, or a save/mode-switch
    // redirect) wins; otherwise fall back to data-tabs-default-value — the
    // tab that matches the integration's active mode — so a fresh page load
    // opens on the mode you're in. Empty default → first enabled tab.
    const params = new URLSearchParams(window.location.search);
    const tabName = params.get(this.paramValue) || this.defaultValue;
    const namedTab = tabName
      ? this.tabTargets.find((t) => t.dataset.tabsPanel === tabName && !t.disabled)
      : null;

    const initial = namedTab || this.tabTargets.find((t) => !t.disabled);
    if (initial) this.activateTab(initial, { updateUrl: false });
  }

  show(event) {
    const tab = event.currentTarget;
    if (tab.disabled) return;
    this.activateTab(tab, { updateUrl: true });
  }

  activateTab(activeTab, { updateUrl } = { updateUrl: false }) {
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

    // Reflect into the URL as a ?tab= param so a follow-up redirect
    // can pin the tab. `replaceState` avoids polluting back-button
    // history every time the user clicks between tabs.
    if (updateUrl) {
      const params = new URLSearchParams(window.location.search);
      params.set(this.paramValue, panelName);
      const newUrl = `${window.location.pathname}?${params.toString()}`;
      window.history.replaceState(null, "", newUrl);
    }
  }
}
