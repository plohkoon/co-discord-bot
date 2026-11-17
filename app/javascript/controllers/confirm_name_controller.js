import { Controller } from "@hotwired/stimulus"

// Keeps a destructive submit disabled until the typed text matches the expected
// name (case-insensitive, like the server's check). The server re-checks — this
// only stops the button looking live before it is.
export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { expected: String }

  connect() { this.check() }

  check() {
    const typed = this.inputTarget.value.trim().toLowerCase()
    this.submitTarget.disabled = typed !== this.expectedValue.trim().toLowerCase()
  }
}
