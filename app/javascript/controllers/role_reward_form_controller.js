import { Controller } from "@hotwired/stimulus"

// The role-rewards form on the guild page: the kind select decides which
// fields apply (achievement name vs. score threshold vs. bracket). Hidden
// fields are also disabled so a switched form never submits stale values.
export default class extends Controller {
  static targets = ["kind", "field"]

  connect() {
    this.toggle()
  }

  toggle() {
    const kind = this.kindTarget.value
    this.fieldTargets.forEach((field) => {
      const show = field.dataset.kinds.split(" ").includes(kind)
      field.hidden = !show
      field.querySelectorAll("input, select").forEach((input) => (input.disabled = !show))
    })
  }
}
