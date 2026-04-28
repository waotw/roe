document.addEventListener("turbo:load", function () {
  // Handle radio button selection when clicking on the option container
  document.querySelectorAll('[data-action="click->theme-reset-modal#selectOption"]').forEach((container) => {
    container.addEventListener("click", function (e) {
      // Don't trigger if clicking on the radio button itself (to avoid double firing)
      if (e.target.tagName !== 'INPUT') {
        const option = this.dataset.option;
        const radio = this.querySelector(`input[type="radio"][value="${option}"]`);
        if (radio) {
          radio.checked = true;
          radio.dispatchEvent(new Event('change'));
        }
      }
    });
  });

  // Handle radio button changes
  document.querySelectorAll('#reset-theme-form input[type="radio"][name="reset_type"]').forEach((radio) => {
    radio.addEventListener("change", function () {
      updateSubmitButton();
    });
  });

  // Handle Escape key to close modal
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") {
      const modal = document.getElementById("reset-theme-modal");
      if (modal && !modal.classList.contains("hidden")) {
        hideResetThemeModal();
      }
    }
  });

  // Handle clicks outside the modal to close it
  const modal = document.getElementById("reset-theme-modal");
  if (modal) {
    modal.addEventListener("click", function (e) {
      if (e.target === this) {
        hideResetThemeModal();
      }
    });
  }
});

function showResetThemeModal() {
  const modal = document.getElementById("reset-theme-modal");
  if (modal) {
    modal.classList.remove("hidden");

    // Reset form state
    const radios = modal.querySelectorAll('input[type="radio"][name="reset_type"]');
    radios.forEach(radio => radio.checked = false);

    const customNameInput = modal.querySelector('input[name="custom_name"]');
    if (customNameInput) {
      customNameInput.value = customNameInput.dataset.defaultValue || '';
    }

    updateSubmitButton();
  }
}

function hideResetThemeModal() {
  const modal = document.getElementById("reset-theme-modal");
  if (modal) {
    modal.classList.add("hidden");
  }
}

function updateSubmitButton() {
  const modal = document.getElementById("reset-theme-modal");
  if (!modal) return;

  const submitBtn = modal.querySelector('input[type="submit"], button[type="submit"]');
  const selectedOption = modal.querySelector('input[type="radio"][name="reset_type"]:checked');

  if (submitBtn) {
    submitBtn.disabled = !selectedOption;

    // Update button text based on selection
    if (selectedOption) {
      if (selectedOption.value === 'overwrite') {
        submitBtn.value = "Reset to Original";
        submitBtn.textContent = "Reset to Original";
      } else if (selectedOption.value === 'fresh') {
        submitBtn.value = "Install Fresh Copy";
        submitBtn.textContent = "Install Fresh Copy";
      }
    }
  }
}

// Make functions globally available
window.showResetThemeModal = showResetThemeModal;
window.hideResetThemeModal = hideResetThemeModal;
