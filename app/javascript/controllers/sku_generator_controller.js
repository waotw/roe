import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "category",
    "number",
    "name",
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
    const name = this.nameTarget.value.toUpperCase();
    const details = this.detailsTarget.value.toUpperCase();

    let sku = `${category}-${number}`;
    if (name) {
      sku += `-${name}`;
    }
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
    const sku = this.previewTarget.textContent.trim();
    const category = this.categoryTarget.value.trim();

    if (sku === "---" || !sku) {
      alert("Please generate a valid SKU first");
      return;
    }

    // Write to the metadata editor — the source of truth. Both when opened from
    // the metadata editor and from the publish flow. If the publish modal is
    // open, the refresh below rebuilds it so SKU + category show as confirmed.
    const skuField = document.getElementById("metadata-field-sku");
    if (skuField) {
      skuField.value = sku;
      skuField.dispatchEvent(new Event("input", { bubbles: true }));
    }
    if (category) {
      const categoryField = document.getElementById("metadata-field-category");
      if (categoryField) {
        categoryField.value = category;
        categoryField.dispatchEvent(new Event("input", { bubbles: true }));
      }
    }

    // Close the generator overlay.
    document.getElementById("sku-generator-modal").innerHTML = "";

    // Rebuild the publish modal (if open) from the updated metadata editor.
    document.dispatchEvent(
      new CustomEvent("publish-modal:refresh", { bubbles: true }),
    );
  }
}
