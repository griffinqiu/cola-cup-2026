import { Controller } from "@hotwired/stimulus"

// The bottle-count popover opens via CSS when a side radio is checked. This
// closes it again when you click anywhere outside the card, and keeps only one
// popover open at a time — by clearing the side radios (which the CSS keys off).
export default class extends Controller {
  open() {
    // Ask every other open popover to close.
    document.dispatchEvent(new CustomEvent("stakepop:open", { detail: { card: this.element } }))

    this.boundOutside ||= (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this.boundOther ||= (event) => {
      if (event.detail.card !== this.element) this.close()
    }
    document.addEventListener("stakepop:open", this.boundOther)
    // Defer so the click that opened this popover doesn't immediately close it.
    setTimeout(() => document.addEventListener("click", this.boundOutside), 0)
  }

  close() {
    this.element.querySelectorAll('input[type="radio"]').forEach((radio) => { radio.checked = false })
    this.teardown()
  }

  teardown() {
    if (this.boundOutside) document.removeEventListener("click", this.boundOutside)
    if (this.boundOther) document.removeEventListener("stakepop:open", this.boundOther)
  }

  disconnect() {
    this.teardown()
  }
}
