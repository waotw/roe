import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "category",
    "number",
    "details",
    "preview",
    "skuField",
    "validation",
    "submitBtn",
  ];
  static values = { productId: Number };

  connect() {
    this.updatePreview();
  }

  updatePreview() {
    const category = this.categoryTarget.value.toUpperCase() || "PROD";
    const number = this.numberTarget.value.padStart(3, "0");
    const details = this.detailsTarget.value.toUpperCase();

    let sku = `${category}-${number}`;
    if (details) {
      sku += `-${details}`;
    }

    this.previewTarget.textContent = sku;
  }

  useSuggestion() {
    const suggestedSku = this.previewTarget.textContent;
    this.skuFieldTarget.value = suggestedSku;
    this.checkDuplicate();
  }

  async checkDuplicate() {
    const sku = this.skuFieldTarget.value.trim();

    if (!sku) {
      this.validationTarget.innerHTML = "";
      this.submitBtnTarget.disabled = true;
      return;
    }

    try {
      const response = await fetch(
        `/admin/products/check_sku?sku=${encodeURIComponent(sku)}`,
      );
      const data = await response.json();

      if (data.exists) {
        this.validationTarget.innerHTML = `
          <p class="text-red-600">⚠️ SKU already in use</p>
        `;
        this.submitBtnTarget.disabled = true;
      } else {
        this.validationTarget.innerHTML = `
          <p class="text-green-600">✓ SKU available</p>
        `;
        this.submitBtnTarget.disabled = false;
      }
    } catch (error) {
      console.error("Error checking SKU:", error);
      this.validationTarget.innerHTML = "";
      this.submitBtnTarget.disabled = false;
    }
  }
}
