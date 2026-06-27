import { Controller } from "@hotwired/stimulus"

// Header account / utility dropdown. Toggles the panel and closes it on an
// outside click or Escape, so the low-frequency items (Admin, language, Guide)
// stay tucked behind the identity pill until asked for. The language row opens a
// second-level panel — a flyout on desktop, a bottom sheet on mobile.
export default class extends Controller {
  static targets = ["trigger", "menu", "langTrigger", "langPanel"]

  connect() {
    this.onOutside = this.onOutside.bind(this)
    this.onKeydown = this.onKeydown.bind(this)
  }

  toggle(event) {
    event.preventDefault()
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.onOutside)
    document.addEventListener("keydown", this.onKeydown)
  }

  close() {
    if (this.menuTarget.hidden) return
    this.closeLang()
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.onOutside)
    document.removeEventListener("keydown", this.onKeydown)
  }

  toggleLang(event) {
    event.preventDefault()
    if (!this.hasLangPanelTarget) return
    this.langPanelTarget.hidden ? this.openLang() : this.closeLang()
  }

  openLang() {
    this.langPanelTarget.hidden = false
    if (this.hasLangTriggerTarget) this.langTriggerTarget.setAttribute("aria-expanded", "true")
  }

  closeLang() {
    if (!this.hasLangPanelTarget || this.langPanelTarget.hidden) return
    this.langPanelTarget.hidden = true
    if (this.hasLangTriggerTarget) this.langTriggerTarget.setAttribute("aria-expanded", "false")
  }

  onOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  onKeydown(event) {
    if (event.key !== "Escape") return
    if (this.hasLangPanelTarget && !this.langPanelTarget.hidden) {
      this.closeLang()
    } else {
      this.close()
    }
  }

  disconnect() {
    this.close()
  }
}
