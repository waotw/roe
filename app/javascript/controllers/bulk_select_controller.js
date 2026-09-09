import { Controller } from "@hotwired/stimulus"

// Multi-select for the posts/pages/products index tables. A SELECT toggle
// reveals a checkbox column; picking rows shows a toolbar with Delete and
// (when every selected draft is clean) Publish. Delete uses a type-DELETE
// confirm; Publish shows a consequence summary. Selected ids are injected into
// the modal forms on open.
export default class extends Controller {
  static targets = [
    "checkbox", "selectColumn", "toggle", "toolbar", "count",
    "publishButton", "deleteModal", "publishModal",
    "deleteIds", "publishIds", "deleteInput", "deleteSubmit",
    "publishCount", "newsletterSummary", "paidSummary"
  ]

  connect() {
    this.selecting = false
    this.update()
  }

  toggleMode(event) {
    event.preventDefault()
    this.selecting = !this.selecting
    this.selectColumnTargets.forEach((el) => el.classList.toggle("hidden", !this.selecting))
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = this.selecting ? "Cancel" : "Select"
      // Swap the base bg-white for a filled dark state so the label stays
      // readable (toggling bg-gray-800 alone loses to bg-white in Tailwind).
      this.toggleTarget.classList.toggle("bg-white", !this.selecting)
      this.toggleTarget.classList.toggle("bg-gray-800", this.selecting)
      this.toggleTarget.classList.toggle("text-white", this.selecting)
    }
    if (!this.selecting) {
      this.checkboxTargets.forEach((cb) => (cb.checked = false))
    }
    this.update()
  }

  // "Select all visible" — only touches rows the current filter leaves shown
  // (filtered-out rows are display:none, so they have no offsetParent).
  selectAll(event) {
    const checked = event.currentTarget.checked
    this.checkboxTargets.forEach((cb) => {
      if (this.isVisible(cb)) cb.checked = checked
    })
    this.update()
  }

  isVisible(cb) {
    return cb.offsetParent !== null
  }

  update() {
    const selected = this.checkboxTargets.filter((cb) => cb.checked && this.isVisible(cb))
    if (selected.length === 0 || !this.selecting) {
      this.toolbarTarget.classList.add("hidden")
      return
    }
    this.toolbarTarget.classList.remove("hidden")
    this.countTarget.textContent = selected.length

    // Publish only applies to selected drafts; hide it if any of them warn.
    const drafts = selected.filter((cb) => cb.dataset.status === "draft")
    const anyWarnings = drafts.some((cb) => cb.dataset.warnings === "true")
    const showPublish = drafts.length > 0 && !anyWarnings
    if (this.hasPublishButtonTarget) {
      this.publishButtonTarget.classList.toggle("hidden", !showPublish)
    }
  }

  openDelete(event) {
    event.preventDefault()
    const selected = this.checkboxTargets.filter((cb) => cb.checked && this.isVisible(cb))
    if (selected.length === 0) return
    this.fillIds(this.deleteIdsTarget, selected)
    this.deleteInputTarget.value = ""
    this.deleteSubmitTarget.disabled = true
    this.deleteModalTarget.classList.remove("hidden")
    this.deleteInputTarget.focus()
  }

  deleteInputChanged() {
    this.deleteSubmitTarget.disabled = this.deleteInputTarget.value !== "DELETE"
  }

  // Enter submits when "DELETE" is typed; Escape cancels — matches the other
  // delete modals.
  deleteInputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      if (this.deleteInputTarget.value === "DELETE") {
        this.deleteSubmitTarget.form.requestSubmit()
      }
    } else if (event.key === "Escape") {
      this.closeModals()
    }
  }

  openPublish(event) {
    event.preventDefault()
    const drafts = this.checkboxTargets.filter(
      (cb) => cb.checked && this.isVisible(cb) && cb.dataset.status === "draft"
    )
    if (drafts.length === 0) return
    this.fillIds(this.publishIdsTarget, drafts)

    const newsletters = drafts.filter((cb) => cb.dataset.newsletter === "true").length
    const paid = drafts.filter((cb) => cb.dataset.paid === "true").length
    if (this.hasPublishCountTarget) this.publishCountTarget.textContent = drafts.length
    if (this.hasNewsletterSummaryTarget) {
      this.newsletterSummaryTarget.classList.toggle("hidden", newsletters === 0)
      this.newsletterSummaryTarget.textContent = `${newsletters} newsletter${newsletters === 1 ? "" : "s"} will be sent`
    }
    if (this.hasPaidSummaryTarget) {
      this.paidSummaryTarget.classList.toggle("hidden", paid === 0)
      this.paidSummaryTarget.textContent = `${paid} paid`
    }
    this.publishModalTarget.classList.remove("hidden")
  }

  closeModals(event) {
    if (event) event.preventDefault()
    if (this.hasDeleteModalTarget) this.deleteModalTarget.classList.add("hidden")
    if (this.hasPublishModalTarget) this.publishModalTarget.classList.add("hidden")
  }

  fillIds(container, checkboxes) {
    container.innerHTML = ""
    checkboxes.forEach((cb) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "ids[]"
      input.value = cb.dataset.id
      container.appendChild(input)
    })
  }
}
