// Modal for the "Update to vX.Y.Z" buttons on the Themes index. Mirrors
// the show/hide pattern in theme_reset_modal.js — global function
// surface, no Stimulus controller, just plain DOM wiring on turbo:load.
//
// The modal is rendered once per page (see _update_theme_modal.html.erb)
// and gets populated at click time from data-* attributes on the
// triggering button: theme slug, display name, installed version,
// bundled version, suggested preserve name.

document.addEventListener("turbo:load", function () {
  wireTriggerButtons();
  wireOptionContainers();
  wireRadioChanges();
  wireDismissals();
});

function wireTriggerButtons() {
  document.querySelectorAll('[data-update-theme-trigger]').forEach((btn) => {
    btn.addEventListener("click", function () {
      showUpdateThemeModal({
        themeName:        this.dataset.themeName,
        displayName:      this.dataset.displayName,
        installedVersion: this.dataset.installedVersion,
        bundledVersion:   this.dataset.bundledVersion,
        suggestedName:    this.dataset.suggestedName,
      });
    });
  });
}

function wireOptionContainers() {
  document.querySelectorAll('#update-theme-modal [data-update-theme-modal-select]').forEach((container) => {
    container.addEventListener("click", function (e) {
      if (e.target.tagName !== "INPUT") {
        const option = this.dataset.updateThemeModalSelect;
        const radio = this.querySelector(`input[type="radio"][value="${option}"]`);
        if (radio) {
          radio.checked = true;
          radio.dispatchEvent(new Event("change"));
        }
      }
    });
  });
}

function wireRadioChanges() {
  document.querySelectorAll('#update-theme-form input[type="radio"][name="reset_type"]').forEach((radio) => {
    radio.addEventListener("change", updateSubmitState);
  });
}

function wireDismissals() {
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") {
      const modal = document.getElementById("update-theme-modal");
      if (modal && !modal.classList.contains("hidden")) {
        hideUpdateThemeModal();
      }
    }
  });

  const modal = document.getElementById("update-theme-modal");
  if (modal) {
    modal.addEventListener("click", function (e) {
      if (e.target === this) {
        hideUpdateThemeModal();
      }
    });
  }
}

function showUpdateThemeModal(opts) {
  const modal = document.getElementById("update-theme-modal");
  if (!modal) return;

  // Fill in every placeholder span for the clicked theme. Using
  // querySelectorAll because the modal references the same value in
  // multiple spots (e.g. bundled version appears in title + both
  // options).
  modal.querySelectorAll('[data-update-theme-modal-display-name]').forEach((el) => {
    el.textContent = opts.displayName || opts.themeName;
  });
  modal.querySelectorAll('[data-update-theme-modal-installed-version]').forEach((el) => {
    el.textContent = opts.installedVersion || "?";
  });
  modal.querySelectorAll('[data-update-theme-modal-bundled-version]').forEach((el) => {
    el.textContent = opts.bundledVersion || "?";
  });

  // Point the form at the reset action for THIS theme.
  const form = document.getElementById("update-theme-form");
  if (form) {
    form.action = "/admin/themes/" + encodeURIComponent(opts.themeName) + "/reset";
  }

  // Reset radio selection between opens so a previous choice doesn't
  // bleed into the next theme's modal.
  modal.querySelectorAll('input[type="radio"][name="reset_type"]').forEach((r) => { r.checked = false; });

  // Seed the custom-name field with the suggestion (server-side will
  // also fall back if left blank).
  const customNameInput = modal.querySelector('input[name="custom_name"]');
  if (customNameInput) {
    customNameInput.value = opts.suggestedName || "";
  }

  updateSubmitState();
  modal.classList.remove("hidden");
}

function hideUpdateThemeModal() {
  const modal = document.getElementById("update-theme-modal");
  if (modal) {
    modal.classList.add("hidden");
  }
}

function updateSubmitState() {
  const modal = document.getElementById("update-theme-modal");
  if (!modal) return;

  const submitBtn = modal.querySelector('input[type="submit"], button[type="submit"]');
  const selected = modal.querySelector('input[type="radio"][name="reset_type"]:checked');

  if (submitBtn) {
    submitBtn.disabled = !selected;
  }
}

window.showUpdateThemeModal = showUpdateThemeModal;
window.hideUpdateThemeModal = hideUpdateThemeModal;
