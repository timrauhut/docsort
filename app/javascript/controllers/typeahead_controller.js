import { Controller } from "@hotwired/stimulus"

// Debounced document typeahead: suggestions dropdown + live table filter.
export default class extends Controller {
  static targets = ["input", "panel", "form"]
  static values = {
    url: String,
    delay: { type: Number, default: 220 },
    minLength: { type: Number, default: 1 }
  }

  connect() {
    this.abortController = null
    this.debounceTimer = null
    this.formTimer = null
    this.activeIndex = -1
    this.navigating = false
    this.hidePanel()

    // Capture-phase so arrows aren't eaten by the browser/input caret behavior
    this.boundKeydown = this.onKeydown.bind(this)
    this.inputTarget.addEventListener("keydown", this.boundKeydown, true)

    // Delegation: keep focus on the input when interacting with fetched suggestions
    this.boundPanelPointerDown = (event) => {
      if (event.target.closest("[data-typeahead-item]")) {
        event.preventDefault()
      }
    }
    this.boundPanelClick = (event) => {
      const item = event.target.closest("[data-typeahead-item]")
      if (!item) return
      event.preventDefault()
      this.activate(item)
    }
    this.panelTarget.addEventListener("pointerdown", this.boundPanelPointerDown)
    this.panelTarget.addEventListener("click", this.boundPanelClick)
  }

  disconnect() {
    this.clearTimers()
    this.abortInFlight()
    if (this.boundKeydown) {
      this.inputTarget.removeEventListener("keydown", this.boundKeydown, true)
    }
    if (this.boundPanelPointerDown) {
      this.panelTarget.removeEventListener("pointerdown", this.boundPanelPointerDown)
    }
    if (this.boundPanelClick) {
      this.panelTarget.removeEventListener("click", this.boundPanelClick)
    }
  }


  search() {
    // Typing cancels keyboard-nav lock
    this.navigating = false
    const query = this.inputTarget.value.trim()

    clearTimeout(this.debounceTimer)
    clearTimeout(this.formTimer)

    // Don't refresh the table while user is arrowing through suggestions
    this.formTimer = setTimeout(() => {
      if (!this.navigating) this.submitForm()
    }, this.delayValue)

    if (query.length < this.minLengthValue) {
      this.hidePanel()
      this.panelTarget.innerHTML = ""
      return
    }

    this.debounceTimer = setTimeout(() => this.fetchSuggestions(query), this.delayValue)
  }

  async fetchSuggestions(query) {
    this.abortInFlight()
    this.abortController = new AbortController()

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)

    if (this.hasFormTarget) {
      const data = new FormData(this.formTarget)
      for (const [key, value] of data.entries()) {
        if (key !== "q" && value) url.searchParams.set(key, value)
      }
    }

    try {
      const response = await fetch(url.toString(), {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        },
        signal: this.abortController.signal,
        credentials: "same-origin"
      })
      if (!response.ok) return

      // Ignore stale responses if the query changed
      if (this.inputTarget.value.trim() !== query) return

      const html = await response.text()
      this.panelTarget.innerHTML = html
      this.activeIndex = -1

      if (this.items().length === 0) {
        this.hidePanel()
      } else {
        this.showPanel()
      }
    } catch (error) {
      if (error.name !== "AbortError") {
        console.error("Typeahead fetch failed", error)
      }
    }
  }

  submitForm() {
    if (!this.hasFormTarget) return
    if (typeof this.formTarget.requestSubmit === "function") {
      this.formTarget.requestSubmit()
    } else {
      this.formTarget.submit()
    }
  }

  onKeydown(event) {
    const key = event.key
    if (!["ArrowDown", "ArrowUp", "Enter", "Escape", "Home", "End"].includes(key)) {
      return
    }

    const query = this.inputTarget.value.trim()
    let items = this.items()
    const hasItems = items.length > 0
    const panelOpen = !this.panelTarget.classList.contains("hidden") && hasItems

    // --- ArrowDown ---
    if (key === "ArrowDown") {
      event.preventDefault()
      event.stopPropagation()
      this.navigating = true
      clearTimeout(this.formTimer)

      if (!panelOpen) {
        if (hasItems) {
          this.showPanel()
          this.activeIndex = 0
          this.highlight()
          return
        }
        if (query.length >= this.minLengthValue) {
          this.fetchSuggestions(query).then(() => {
            this.navigating = true
            this.activeIndex = 0
            this.highlight()
          })
        }
        return
      }

      this.activeIndex = this.activeIndex < items.length - 1 ? this.activeIndex + 1 : 0
      this.highlight()
      return
    }

    // --- ArrowUp ---
    if (key === "ArrowUp") {
      event.preventDefault()
      event.stopPropagation()
      if (!panelOpen) return

      this.navigating = true
      clearTimeout(this.formTimer)
      this.activeIndex = this.activeIndex > 0 ? this.activeIndex - 1 : items.length - 1
      this.highlight()
      return
    }

    // --- Home / End within list ---
    if (key === "Home" && panelOpen) {
      event.preventDefault()
      this.navigating = true
      clearTimeout(this.formTimer)
      this.activeIndex = 0
      this.highlight()
      return
    }
    if (key === "End" && panelOpen) {
      event.preventDefault()
      this.navigating = true
      clearTimeout(this.formTimer)
      this.activeIndex = items.length - 1
      this.highlight()
      return
    }

    // --- Enter ---
    if (key === "Enter") {
      if (panelOpen && this.activeIndex >= 0) {
        event.preventDefault()
        event.stopPropagation()
        const item = this.items()[this.activeIndex]
        if (item) this.activate(item)
      }
      // else: allow form submit / default
      return
    }

    // --- Escape ---
    if (key === "Escape") {
      event.preventDefault()
      this.navigating = false
      this.hidePanel()
    }
  }

  // Kept for data-action compatibility if present
  keydown(event) {
    // Real handling is in capture listener (onKeydown)
  }

  open() {
    if (this.items().length > 0) this.showPanel()
  }

  // Delay hide so mousedown/click on a suggestion can fire first
  maybeClose() {
    setTimeout(() => {
      if (this.element.contains(document.activeElement)) return
      this.navigating = false
      this.hidePanel()
    }, 180)
  }

  activate(item) {
    const href = item.getAttribute("href") || item.dataset.href
    if (href) {
      // Leave the turbo frame so we open the document page
      if (window.Turbo) {
        window.Turbo.visit(href)
      } else {
        window.location.href = href
      }
    } else {
      item.click()
    }
  }

  highlight() {
    const items = this.items()
    items.forEach((item, index) => {
      const selected = index === this.activeIndex
      item.setAttribute("aria-selected", selected ? "true" : "false")
      item.classList.toggle("is-active", selected)
      if (selected) {
        item.scrollIntoView({ block: "nearest" })
        this.inputTarget.setAttribute("aria-activedescendant", item.id || `typeahead-option-${index}`)
      }
    })
  }

  items() {
    return Array.from(this.panelTarget.querySelectorAll("[data-typeahead-item]"))
  }

  showPanel() {
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.style.display = "block"
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  hidePanel() {
    this.panelTarget.classList.add("hidden")
    this.panelTarget.style.display = "none"
    this.activeIndex = -1
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.items().forEach((item) => {
      item.classList.remove("is-active")
      item.setAttribute("aria-selected", "false")
    })
  }


  clearTimers() {
    clearTimeout(this.debounceTimer)
    clearTimeout(this.formTimer)
  }

  abortInFlight() {
    if (this.abortController) {
      this.abortController.abort()
      this.abortController = null
    }
  }
}
