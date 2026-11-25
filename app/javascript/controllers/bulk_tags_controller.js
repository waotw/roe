import { Controller } from "@hotwired/stimulus"

// The TAGS menu in a content list's selection bar (admin/shared/_bulk_toolbar).
// Opens with the tags every selected item shares, ticked. Unticking one
// removes it from all of them; typing adds a tag, from the list or new. SAVE
// shows what will change, then posts it to bulk_tags.
//
// Reads the selection from the bulk-select controller's checkboxes, each of
// which carries its item's tags in data-tags.
export default class extends Controller {
  static targets = ["menu", "list", "input", "suggestions", "save", "modal", "summary", "fields"]
  static values = { options: Array, noun: String, nounPlural: String }

  connect() {
    this.root = this.element.closest("[data-controller~='bulk-select']") || document
    this.added = []
    this.unticked = new Set()
    this.onSelectionChange = (event) => {
      if (event.target.matches("[data-bulk-select-target='checkbox'], [data-action*='selectAll']") && this.isOpen()) {
        // After bulk-select has updated the selection.
        setTimeout(() => this.render(), 0)
      }
    }
    this.root.addEventListener("change", this.onSelectionChange)
    this.onOutsideClick = (event) => {
      // A click that re-rendered the list has a detached target; that's inside.
      // Changing the selection leaves the menu open, showing the new shared tags.
      if (event.target.closest?.("[data-bulk-select-target='checkbox'], [data-bulk-select-target='selectColumn']")) return
      if (this.isOpen() && event.target.isConnected && !this.element.contains(event.target)) this.closeMenu()
    }
    document.addEventListener("click", this.onOutsideClick)
  }

  disconnect() {
    this.root.removeEventListener("change", this.onSelectionChange)
    document.removeEventListener("click", this.onOutsideClick)
  }

  isOpen() {
    return !this.menuTarget.classList.contains("hidden")
  }

  toggle(event) {
    event.preventDefault()
    if (this.isOpen()) {
      this.closeMenu()
    } else {
      this.added = []
      this.unticked = new Set()
      this.inputTarget.value = ""
      this.menuTarget.classList.remove("hidden")
      this.render()
      this.inputTarget.focus()
    }
  }

  closeMenu() {
    this.menuTarget.classList.add("hidden")
    this.suggestionsTarget.classList.add("hidden")
  }

  selected() {
    return Array.from(this.root.querySelectorAll("[data-bulk-select-target='checkbox']"))
      .filter((cb) => cb.checked && cb.offsetParent !== null)
  }

  tagsOf(checkbox) {
    try {
      return JSON.parse(checkbox.dataset.tags || "[]")
    } catch {
      return []
    }
  }

  shared() {
    const items = this.selected().map((cb) => this.tagsOf(cb))
    if (items.length === 0) return []
    return items[0].filter((tag) => items.every((tags) => tags.includes(tag)))
  }

  render() {
    const shared = this.shared()
    this.added = this.added.filter((tag) => !shared.includes(tag))
    const rows = shared.map((tag) => this.rowHtml(tag, !this.unticked.has(tag), "shared"))
      .concat(this.added.map((tag) => this.rowHtml(tag, true, "added")))
    this.listTarget.innerHTML = rows.length
      ? rows.join("")
      : `<p class="px-3 py-2 text-xs text-gray-500 font-sans">The selected ${this.nounPluralValue} share no tags.</p>`
    this.saveTarget.disabled = this.changes().length === 0
  }

  rowHtml(tag, checked, kind) {
    let note = ""
    if (kind === "shared" && !checked) note = "will be removed"
    if (kind === "added") note = this.optionsValue.includes(tag) ? "will be added" : "new tag"
    const color = kind === "added" ? "text-green-700" : (checked ? "text-gray-900" : "text-gray-500")
    return `<label class="flex items-center gap-2 px-3 py-1 cursor-pointer hover:bg-gray-50">
      <input type="checkbox" ${checked ? "checked" : ""} data-tag="${this.escape(tag)}" data-kind="${kind}"
             data-action="change->bulk-tags#tick">
      <span class="font-mono text-xs ${color}">${this.escape(tag)}</span>
      <span class="grow"></span>
      <span class="text-[11px] font-sans text-gray-500">${note}</span>
    </label>`
  }

  tick(event) {
    const { tag, kind } = event.target.dataset
    if (kind === "added") {
      this.added = this.added.filter((t) => t !== tag)
    } else if (event.target.checked) {
      this.unticked.delete(tag)
    } else {
      this.unticked.add(tag)
    }
    this.render()
  }

  // ── Adding ────────────────────────────────────────────────────────────────

  // Only while typing. Shown on focus, the list covered the ticked tags the
  // menu opens with, which made them look missing.
  suggest() {
    const query = this.inputTarget.value.trim().toLowerCase()
    if (query === "") {
      this.suggestionsTarget.classList.add("hidden")
      return
    }
    const taken = new Set(this.shared().concat(this.added))
    const matches = this.optionsValue
      .filter((tag) => !taken.has(tag) && tag.toLowerCase().includes(query))
      .slice(0, 8)
    if (matches.length === 0) {
      this.suggestionsTarget.classList.add("hidden")
      return
    }
    this.suggestionsTarget.innerHTML = matches.map((tag) =>
      `<button type="button" class="block w-full text-left px-3 py-1 font-mono text-xs hover:bg-blue-100 cursor-pointer"
               data-tag="${this.escape(tag)}" data-action="bulk-tags#pick">${this.escape(tag)}</button>`
    ).join("")
    this.suggestionsTarget.classList.remove("hidden")
  }

  pick(event) {
    event.preventDefault()
    this.add(event.currentTarget.dataset.tag)
  }

  keydown(event) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      this.add(this.inputTarget.value)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.closeMenu()
    }
  }

  add(value) {
    const tag = String(value || "").replace(/,/g, "").trim()
    if (tag === "") return
    if (this.shared().includes(tag)) {
      this.unticked.delete(tag)
    } else if (!this.added.includes(tag)) {
      this.added.push(tag)
    }
    this.inputTarget.value = ""
    this.suggestionsTarget.classList.add("hidden")
    this.render()
    this.inputTarget.focus()
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  changes() {
    const selected = this.selected()
    const lines = []
    this.added.forEach((tag) => {
      const count = selected.filter((cb) => !this.tagsOf(cb).includes(tag)).length
      if (count > 0) lines.push({ action: "add", tag, count })
    })
    this.shared().filter((tag) => this.unticked.has(tag)).forEach((tag) => {
      lines.push({ action: "remove", tag, count: selected.length })
    })
    return lines
  }

  confirm(event) {
    event.preventDefault()
    const changes = this.changes()
    if (changes.length === 0) return

    this.summaryTarget.innerHTML = changes.map(({ action, tag, count }) => {
      const noun = count === 1 ? this.nounValue : this.nounPluralValue
      const verb = action === "add" ? "add" : "remove"
      const prep = action === "add" ? "to" : "from"
      return `<li>${verb} <code class="font-mono">${this.escape(tag)}</code> ${prep} ${count} ${noun}</li>`
    }).join("")

    this.fieldsTarget.innerHTML = ""
    this.selected().forEach((cb) => this.hidden("ids[]", cb.dataset.id))
    changes.forEach(({ action, tag }) => this.hidden(action === "add" ? "add[]" : "remove[]", tag))

    this.closeMenu()
    this.modalTarget.classList.remove("hidden")
  }

  cancel(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add("hidden")
  }

  hidden(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    this.fieldsTarget.appendChild(input)
  }

  escape(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }
}
