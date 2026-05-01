import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "message"]
  static values = {
    batchId: String
  }

  connect() {
    console.log("Upload progress connected for batch:", this.batchIdValue)
    
    // Give Turbo Streams time to connect
    setTimeout(() => {
      this.checkConnection()
    }, 2000)
  }

  checkConnection() {
    // Check if any statuses are still showing "Waiting..."
    const waitingCount = this.messageTargets.filter(el => 
      el.textContent.includes("Waiting...") || el.textContent.includes("Uploading...")
    ).length

    if (waitingCount > 0 && waitingCount === this.messageTargets.length) {
      console.log("No status updates received, page may have loaded after job completed")
      // All still waiting - job might have finished before page loaded
      this.refreshPage()
    }
  }

  refreshPage() {
    // Refresh after a delay to check current status
    setTimeout(() => {
      window.location.reload()
    }, 3000)
  }
}
