import { Controller } from "@hotwired/stimulus";

// Form behavior for the Static Site Sync settings:
//   - hide the SFTP/FTPS credentials block when ZIP is selected
//     (purely cosmetic — server ignores those fields when zip)
//   - rewrite the submit button label so the action matches the
//     protocol: "Save" for SFTP/FTPS, "Download ZIP" for ZIP
export default class extends Controller {
  static targets = ["credentials", "protocolGroup", "submitButton"];

  protocolChanged(event) {
    const value = event.target.value;
    const isZip = value === "zip";

    if (this.hasCredentialsTarget) {
      this.credentialsTarget.classList.toggle("hidden", isZip);
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.value = isZip ? "Download ZIP" : "Save";
    }
  }
}
