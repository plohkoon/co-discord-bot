import { Controller } from "@hotwired/stimulus"

// An application question's editor: the style select decides which settings
// apply (placeholder for text, options for multiple choice / checkboxes, no
// Required for yes/no). Hidden fields are also disabled so a switched form
// never submits stale values — the model drops them for the style anyway.
export default class extends Controller {
  static targets = ["style", "field"]

  connect() {
    this.toggle()
  }

  toggle() {
    const style = this.styleTarget.value
    this.fieldTargets.forEach((field) => {
      const show = field.dataset.styles.split(" ").includes(style)
      field.hidden = !show
      field.querySelectorAll("input, select, textarea").forEach((input) => (input.disabled = !show))
    })
  }
}
