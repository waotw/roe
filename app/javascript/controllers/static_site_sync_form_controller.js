import { Controller } from "@hotwired/stimulus";

// Form behavior for the Static Site Sync settings:
//   - hide the SFTP/FTPS credentials block when ZIP is selected
//     (purely cosmetic — server ignores those fields when zip)
//   - rewrite the submit button label so the action matches the
//     protocol: "Save" for SFTP/FTPS, "Download ZIP" for ZIP
//   - snap the port to the protocol's default (22 SFTP / 21 FTPS),
//     without clobbering a custom port the user set on purpose
//   - show only the auth fields (password vs SSH key + passphrase) for
//     the authentication mode currently selected
export default class extends Controller {
  static targets = ["credentials", "protocolGroup", "submitButton", "port", "passwordAuth", "keyAuth"];

  protocolChanged(event) {
    const value = event.target.value;
    const isZip = value === "zip";

    if (this.hasCredentialsTarget) {
      this.credentialsTarget.classList.toggle("hidden", isZip);
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.value = isZip ? "Download ZIP" : "Save";
    }

    if (this.hasPortTarget && !isZip) {
      const defaults = { sftp: "22", ftps: "21" };
      const current = this.portTarget.value.trim();
      // Only snap when the field is empty or still on a protocol default —
      // never overwrite a custom port (e.g. 2222) typed on purpose.
      if (current === "" || current === "22" || current === "21") {
        this.portTarget.value = defaults[value] || current;
      }
    }
  }

  authModeChanged(event) {
    const isKey = event.target.value === "ssh_key";
    if (this.hasPasswordAuthTarget) this.passwordAuthTarget.classList.toggle("hidden", isKey);
    if (this.hasKeyAuthTarget) this.keyAuthTarget.classList.toggle("hidden", !isKey);
  }
}
