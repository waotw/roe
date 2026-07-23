import { Controller } from "@hotwired/stimulus";

// Form behavior for the Static Site Sync settings:
//   - hide the SFTP/FTPS credentials block when ZIP is selected
//     (purely cosmetic — server ignores those fields when zip)
//   - swap the action to match the protocol: a Download button next to
//     the picker for ZIP, the floating Save bar for SFTP/FTPS
//   - snap the port to the protocol's default (22 SFTP / 21 FTPS),
//     without clobbering a custom port the user set on purpose
//   - the protocol decides auth entirely: SFTP shows the SSH key +
//     passphrase; FTPS shows the password and the TLS-verify option
export default class extends Controller {
  static targets = [
    "credentials", "protocolGroup", "zipAction", "saveBar", "port",
    "passwordAuth", "keyAuth", "verifyTls"
  ];

  protocolChanged(event) {
    const value = event.target.value;
    const isZip = value === "zip";
    const isFtps = value === "ftps";
    const isSftp = value === "sftp";

    if (this.hasCredentialsTarget) {
      this.credentialsTarget.classList.toggle("hidden", isZip);
    }

    // ZIP → Download button by the picker; SFTP/FTPS → floating Save bar.
    if (this.hasZipActionTarget) this.zipActionTarget.classList.toggle("hidden", !isZip);
    if (this.hasSaveBarTarget) this.saveBarTarget.classList.toggle("hidden", isZip);

    if (this.hasPortTarget && !isZip) {
      const defaults = { sftp: "22", ftps: "21" };
      const current = this.portTarget.value.trim();
      // Only snap when the field is empty or still on a protocol default —
      // never overwrite a custom port (e.g. 2222) typed on purpose.
      if (current === "" || current === "22" || current === "21") {
        this.portTarget.value = defaults[value] || current;
      }
    }

    if (isZip) return; // credentials block is hidden — nothing else to arrange

    // FTPS = password + TLS-verify; SFTP = SSH key + passphrase.
    if (this.hasPasswordAuthTarget) this.passwordAuthTarget.classList.toggle("hidden", !isFtps);
    if (this.hasKeyAuthTarget) this.keyAuthTarget.classList.toggle("hidden", !isSftp);
    if (this.hasVerifyTlsTarget) this.verifyTlsTarget.classList.toggle("hidden", !isFtps);
  }
}
