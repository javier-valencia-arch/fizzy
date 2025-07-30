import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "image", "dialog", "zoomedImage" ]

  connect() {
    this.dialogTarget.addEventListener('transitionend', this.onTransitionEnd.bind(this))
  }

  // Only remove the image src after the CSS transition has finished
  onTransitionEnd(event) {
    if (this._waitingForTransition && !this.dialogTarget.open) {
      this._waitingForTransition = false
      this.zoomedImageTarget.src = ""
    }
  }

  open(event) {
    this.dialogTarget.showModal()
    this.#set(event.target.closest("a"))
  }

  reset() {
    this._waitingForTransition = true
  }

  #set(target) {
    this.zoomedImageTarget.src = target.href
  }
}
