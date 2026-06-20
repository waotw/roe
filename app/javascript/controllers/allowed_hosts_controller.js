import { Controller } from "@hotwired/stimulus";

// Manages the add/remove row UI for the allowed_hosts list on the
// admin Development Configuration edit page. Rows are pure DOM —
// the form submission gathers every surviving `allowed_hosts[]`
// input at save time. Clicking CANCEL navigates away (no submit),
// so in-page changes don't persist by design.
//
// Replaces an earlier inline <script> block that bound handlers on
// DOMContentLoaded — which Turbo Drive doesn't fire on page-to-page
// navigations, so the buttons silently did nothing whenever the user
// arrived at the page via a link click.
//
// Usage:
//   <div data-controller="allowed-hosts">
//     <div data-allowed-hosts-target="container">
//       <div data-allowed-hosts-target="row">
//         <input ...>
//         <button data-action="click->allowed-hosts#remove">Remove</button>
//       </div>
//     </div>
//     <template data-allowed-hosts-target="template">
//       <!-- markup for a fresh empty row -->
//     </template>
//     <button data-action="click->allowed-hosts#add">+ Add Host</button>
//   </div>
export default class extends Controller {
  static targets = [ "container", "template", "row" ];

  add() {
    const fragment = this.templateTarget.content.cloneNode(true);
    this.containerTarget.appendChild(fragment);
  }

  remove(event) {
    const row = event.target.closest("[data-allowed-hosts-target='row']");
    if (!row) return;

    // Don't let the user delete every row — the form would then have
    // no allowed_hosts[] inputs at all and the controller would see
    // an empty list. Clear the input instead.
    if (this.rowTargets.length <= 1) {
      const input = row.querySelector("input");
      if (input) input.value = "";
    } else {
      row.remove();
    }
  }
}
