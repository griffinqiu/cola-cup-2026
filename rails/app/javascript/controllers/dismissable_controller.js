import { Controller } from "@hotwired/stimulus"

// Hides an element for good once dismissed, remembering the choice in
// localStorage (keyed by data-dismissable-key-value) so it stays gone on return.
export default class extends Controller {
  static values = { key: String }

  connect() {
    if (localStorage.getItem(this.storageKey)) this.element.hidden = true
  }

  close(event) {
    if (event) event.preventDefault()
    localStorage.setItem(this.storageKey, "1")
    this.element.hidden = true
  }

  get storageKey() {
    return `dismissed:${this.keyValue}`
  }
}
