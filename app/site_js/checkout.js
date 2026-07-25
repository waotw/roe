// Remove any existing overlays when page is shown (handles back button)
window.addEventListener("pageshow", function (event) {
  const existingOverlay = document.querySelector(".checkout-loading-overlay");
  if (existingOverlay) {
    existingOverlay.remove();
  }
});

// Checkout loading state
document.addEventListener("DOMContentLoaded", function () {
  const checkoutForms = document.querySelectorAll(".checkout-form");

  checkoutForms.forEach((form) => {
    form.addEventListener("submit", function (e) {
      // Create and show loading overlay
      const overlay = document.createElement("div");
      overlay.className = "checkout-loading-overlay";
      overlay.innerHTML = `
        <div class="checkout-loading-message">
          <div class="loading-spinner"></div>
          <p>Sending you to Stripe's secure checkout...</p>
        </div>
      `;

      document.body.appendChild(overlay);

      // Disable the submit button to prevent double-clicks
      const button = form.querySelector('button[type="submit"]');
      if (button) {
        button.disabled = true;
      }
    });
  });
});
