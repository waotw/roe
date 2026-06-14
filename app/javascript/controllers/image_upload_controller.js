import { Controller } from "@hotwired/stimulus"

// Reusable image upload field with inline URL-verify-on-blur.
//
// Pairs with shared/_image_upload_field.html.erb. Each rendered
// instance gets its own controller scope, so multiple fields on
// the same page (e.g. artwork + logo) don't interfere.
//
// Two behaviours wired up:
//
//   1. Verify the filename exists. On blur / on input, we construct
//      `<base_url><filename>` and create an <img> with that src.
//      Browser's onload/onerror tells us whether the file resolves
//      — no XHR required, and we get free browser caching.
//
//   2. Upload a new image. Clicking the Upload button triggers a
//      hidden <input type="file">; on file-select we POST to the
//      configured upload endpoint with FormData and populate the
//      filename field with the server's returned filename.
//
// Targets:
//   filename     — the visible <input type="text"> with the
//                  filename. Carries the form field name so the
//                  parent form submits its value as usual.
//   uploadButton — the "Upload" button that triggers the file picker.
//   fileInput    — the hidden <input type="file">.
//   warning      — element shown when the filename doesn't resolve.
//                  Optional; if omitted, no inline warning rendered.
//   status       — element used to show upload progress / errors.
//                  Optional.
//
// Values:
//   baseUrl   — URL prefix used to construct the existence-check URL.
//               Default "/system/images/" (served from
//               /site/system/assets/images/ by System::ImagesController).
//   assetType — POST body param the upload endpoint uses to route the
//               file. Default "images" (writes to
//               /site/system/assets/images/).
//   uploadUrl — endpoint that accepts the multipart upload.
//               Default "/admin/system_assets".
export default class extends Controller {
  static targets = ["filename", "uploadButton", "fileInput", "warning", "status"]
  static values = {
    baseUrl:   { type: String, default: "/system/images/" },
    assetType: { type: String, default: "images" },
    uploadUrl: { type: String, default: "/admin/system_assets" }
  }

  connect() {
    // Run an initial verify so a server-pre-filled value (e.g. from
    // "Fill from feed") gets its existence check on page load too.
    this.verify()
  }

  verify() {
    const value = this.filenameTarget.value.trim()
    if (!value) {
      this.hideWarning()
      return
    }
    const img = new Image()
    img.onload  = () => this.hideWarning()
    img.onerror = () => this.showWarning()
    img.src = this.baseUrlValue + value
  }

  hideWarning() {
    if (this.hasWarningTarget) {
      this.warningTarget.classList.add("hidden")
    }
    this.filenameTarget.classList.remove("border-red-300")
  }

  showWarning() {
    if (this.hasWarningTarget) {
      this.warningTarget.classList.remove("hidden")
    }
    this.filenameTarget.classList.add("border-red-300")
  }

  triggerFilePicker() {
    this.fileInputTarget.click()
  }

  async upload() {
    const file = this.fileInputTarget.files[0]
    if (!file) return

    const formData = new FormData()
    formData.append("file", file)
    formData.append("asset_type", this.assetTypeValue)

    const tokenEl = document.querySelector('meta[name="csrf-token"]')
    const token   = tokenEl ? tokenEl.content : ""

    this.setStatus("Uploading…")

    try {
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" },
        body: formData
      })
      const data = await response.json()
      if (data.success) {
        this.filenameTarget.value = data.filename
        this.verify()
        this.setStatus(`✓ Uploaded: ${data.filename}`)
        setTimeout(() => this.clearStatus(), 2500)
      } else {
        this.setStatus(`Upload failed: ${data.error || "unknown error"}`)
      }
    } catch (err) {
      this.setStatus(`Upload error: ${err.message}`)
    }

    // Reset the file input so the same file can be re-selected later
    // (browsers don't fire `change` if the value is unchanged).
    this.fileInputTarget.value = ""
  }

  setStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
  }

  clearStatus() {
    if (!this.hasStatusTarget) return
    this.statusTarget.classList.add("hidden")
  }
}
