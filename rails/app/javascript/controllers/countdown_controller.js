import { Controller } from "@hotwired/stimulus"

// Disables the form(s) once the window closes (data-closes-at), so a page left
// open past the cutoff can't submit a stale vote/pick — the server enforces the
// same guard, this just reflects it in the UI. When a `display` target is
// present it also renders a live ticking countdown to that cutoff.
export default class extends Controller {
  static values = { closesAt: String }
  static targets = ["display"]

  connect() {
    this.closes = Date.parse(this.closesAtValue)
    if (isNaN(this.closes)) return

    if (this.closes - Date.now() <= 0) {
      this.lock()
      return
    }

    this.lockTimer = setTimeout(() => this.lock(), this.closes - Date.now())
    if (this.hasDisplayTarget) {
      this.render()
      this.ticker = setInterval(() => this.render(), 1000)
    }
  }

  disconnect() {
    if (this.lockTimer) clearTimeout(this.lockTimer)
    if (this.ticker) clearInterval(this.ticker)
  }

  render() {
    const remaining = this.closes - Date.now()
    if (remaining <= 0) {
      this.displayTarget.textContent = "已封盘"
      if (this.ticker) clearInterval(this.ticker)
      return
    }
    this.displayTarget.textContent = this.format(remaining)
  }

  format(ms) {
    let s = Math.floor(ms / 1000)
    const days = Math.floor(s / 86400); s -= days * 86400
    const hours = Math.floor(s / 3600); s -= hours * 3600
    const minutes = Math.floor(s / 60); s -= minutes * 60
    const pad = (n) => String(n).padStart(2, "0")
    const clock = `${pad(hours)}:${pad(minutes)}:${pad(s)}`
    return days > 0 ? `${days} 天 ${clock}` : clock
  }

  lock() {
    this.element.querySelectorAll("button, input").forEach((el) => { el.disabled = true })
  }
}
