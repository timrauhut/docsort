import { Controller } from "@hotwired/stimulus"

// Auto-dismiss flash banners after a few seconds.
export default class extends Controller {
  static values = {
    delay: { type: Number, default: 5000 }
  }

  connect() {
    this.timeout = window.setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    if (this.timeout) window.clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.classList.add("flash--hiding")
    window.setTimeout(() => {
      this.element.remove()
    }, 280)
  }
}
