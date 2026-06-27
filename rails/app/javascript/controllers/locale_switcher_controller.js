import { Controller } from "@hotwired/stimulus"

// Language picker: submit the form as soon as a new locale is chosen so the
// page reloads in that language. Without JS the form still works via its
// submit button.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
