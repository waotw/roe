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
    "insertBtn",
  ];
  static values = { productId: Number };

  connect() {
    this.updatePreview();
    // Auto-check duplicate on connect if we're in standalone modal
    if (this.hasInsertBtnTarget) {
      this.checkDuplicateForInsert();
    }
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

    // Check duplicate if in standalone modal
    if (this.hasInsertBtnTarget) {
      this.checkDuplicateForInsert();
    }
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

  async checkDuplicateForInsert() {
    const sku = this.previewTarget.textContent;

    if (!sku || sku === "---") {
      this.validationTarget.innerHTML = "";
      if (this.hasInsertBtnTarget) {
        this.insertBtnTarget.disabled = true;
      }
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
        if (this.hasInsertBtnTarget) {
          this.insertBtnTarget.disabled = true;
          this.insertBtnTarget.classList.add(
            "opacity-50",
            "cursor-not-allowed",
          );
        }
      } else {
        this.validationTarget.innerHTML = `
          <p class="text-green-600">✓ SKU available</p>
        `;
        if (this.hasInsertBtnTarget) {
          this.insertBtnTarget.disabled = false;
          this.insertBtnTarget.classList.remove(
            "opacity-50",
            "cursor-not-allowed",
          );
        }
      }
    } catch (error) {
      console.error("Error checking SKU:", error);
      this.validationTarget.innerHTML = "";
      if (this.hasInsertBtnTarget) {
        this.insertBtnTarget.disabled = false;
        this.insertBtnTarget.classList.remove(
          "opacity-50",
          "cursor-not-allowed",
        );
      }
    }
  }

  insertToMetadata() {
    const sku = this.previewTarget.textContent;
    const category = this.categoryTarget.value.trim();

    if (sku === "---" || !sku) {
      alert("Please generate a valid SKU first");
      return;
    }

    // Insert SKU into metadata field
    const skuField = document.getElementById("metadata-field-sku");
    if (skuField) {
      skuField.value = sku;
      skuField.dispatchEvent(new Event("input", { bubbles: true }));
    }

    // Update category if it was changed
    if (category) {
      const categoryField = document.getElementById("metadata-field-category");
      if (categoryField) {
        categoryField.value = category;
        categoryField.dispatchEvent(new Event("input", { bubbles: true }));
      }
    }

    // Close modal
    document.getElementById("sku-generator-modal").innerHTML = "";
  }
}
