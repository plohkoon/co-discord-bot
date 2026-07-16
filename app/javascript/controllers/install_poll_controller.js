import { Controller } from "@hotwired/stimulus"

// Attached to the dashboard's "Add co-bot" section. While install cards are on
// screen, ask the server every few seconds whether one of those servers has
// joined (the bot's server_create creates its Guild row); reload to promote it
// to a regular server card. Polling stops when the section (or page) goes away.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 4000 } }

  connect() {
    this.timer = setInterval(() => this.check(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async check() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const { ready } = await response.json()
      if (ready) window.location.reload()
    } catch {
      // transient network error — try again next tick
    }
  }
}
