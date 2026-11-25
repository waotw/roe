import { Controller } from "@hotwired/stimulus"

// The metadata editor's tags field: each tag a box with a ×, and a dropdown of
// the site's tags (with how often each is used) while typing. A tag that isn't
// in the list can still be typed and added with Enter or a comma.
//
// The value lives in a hidden input — data-metadata-field="tags", comma-
// separated — so the metadata editor reads and writes it as before. Every
// change fires `input` on it, which is what the editor listens for.
export default class extends Controller {
  static targets = ["value", "chips", "entry", "dropdown"]
  static values = { options: Array }

  connect() {
    this.highlight = -1
    this.committed = this.valueTarget.value.split(",").map((t) => t.trim()).filter((t) => t !== "")
    this.render()
    this.onOutsideClick = (event) => {
      if (event.target.isConnected && !this.element.contains(event.target)) this.hide()
    }
    document.addEventListener("click", this.onOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.onOutsideClick)
  }

  // The tags shown as boxes.
  tags() {
    return this.committed
  }

  setTags(tags) {
    this.committed = tags
    this.sync()
    this.render()
  }

  // The hidden value is the boxes plus whatever is typed and not yet added,
  // so a save straight after typing keeps the tag. Saving reads the value
  // at once; waiting for blur would lose it.
  sync() {
    const pending = this.entryTarget.value.replace(/,/g, "").trim()
    const all = pending && !this.committed.includes(pending) ? this.committed.concat(pending) : this.committed
    const value = all.join(", ")
    if (value === this.valueTarget.value) return
    this.valueTarget.value = value
    this.valueTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  typed() {
    this.sync()
    this.suggest()
  }

  render() {
    this.chipsTarget.innerHTML = this.tags().map((tag) =>
      `<span class="inline-flex items-center gap-1 px-1.5 py-0.5 bg-blue-100 border border-blue-300 font-mono text-xs text-blue-900">
        ${this.escape(tag)}
        <button type="button" class="text-blue-700 hover:text-red-700 leading-none cursor-pointer"
                data-tag="${this.escape(tag)}" data-action="tag-field#remove" aria-label="Remove ${this.escape(tag)}">&times;</button>
      </span>`
    ).join("")
  }

  focus(event) {
    if (event.target === event.currentTarget) this.entryTarget.focus()
  }

  remove(event) {
    event.preventDefault()
    const tag = event.currentTarget.dataset.tag
    this.setTags(this.tags().filter((t) => t !== tag))
    this.entryTarget.focus()
  }

  add(value) {
    const tag = String(value || "").replace(/,/g, "").trim()
    this.entryTarget.value = ""
    if (tag !== "" && !this.tags().includes(tag)) this.setTags(this.tags().concat(tag))
    else this.sync()
    this.hide()
  }

  // Typed text that was never confirmed still counts once the field is left.
  commit() {
    setTimeout(() => {
      if (!this.element.contains(document.activeElement) && this.entryTarget.value.trim() !== "") {
        this.add(this.entryTarget.value)
      }
    }, 150)
  }

  matches() {
    const query = this.entryTarget.value.trim().toLowerCase()
    const taken = new Set(this.tags())
    return this.optionsValue
      .filter((o) => !taken.has(o.name) && (query === "" || o.name.toLowerCase().includes(query)))
      .slice(0, 10)
  }

  suggest() {
    this.highlight = -1
    const matches = this.matches()
    if (matches.length === 0) return this.hide()

    // Typed a tag that exists in another case: preselect the most used
    // spelling (listed first), so Enter takes it rather than a new variant.
    const typed = this.entryTarget.value.trim().toLowerCase()
    const same = matches.findIndex((o) => o.name.toLowerCase() === typed)
    if (typed !== "" && same >= 0) this.highlight = same

    this.dropdownTarget.innerHTML = matches.map((o, i) =>
      `<button type="button" class="flex w-full items-center gap-2 px-3 py-1 text-left font-mono text-xs hover:bg-blue-100 cursor-pointer"
               data-index="${i}" data-tag="${this.escape(o.name)}" data-action="tag-field#pick">
        <span class="grow">${this.escape(o.name)}</span>
        <span class="text-gray-500">${o.count}</span>
      </button>`
    ).join("")
    this.dropdownTarget.classList.remove("hidden")
    Array.from(this.dropdownTarget.querySelectorAll("[data-tag]"))
      .forEach((el, i) => el.classList.toggle("bg-blue-100", i === this.highlight))
  }

  pick(event) {
    event.preventDefault()
    this.add(event.currentTarget.dataset.tag)
    this.entryTarget.focus()
  }

  keydown(event) {
    const items = Array.from(this.dropdownTarget.querySelectorAll("[data-tag]"))
    const open = !this.dropdownTarget.classList.contains("hidden")

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (!open) return this.suggest()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.highlight = Math.max(-1, Math.min(items.length - 1, this.highlight + step))
      items.forEach((el, i) => el.classList.toggle("bg-blue-100", i === this.highlight))
    } else if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      const chosen = open && this.highlight >= 0 ? items[this.highlight].dataset.tag : this.entryTarget.value
      this.add(chosen)
    } else if (event.key === "Backspace" && this.entryTarget.value === "") {
      const tags = this.tags()
      if (tags.length) this.setTags(tags.slice(0, -1))
    } else if (event.key === "Escape" && open) {
      event.preventDefault()
      this.hide()
    }
  }

  hide() {
    this.dropdownTarget.classList.add("hidden")
    this.highlight = -1
  }

  escape(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }
}
