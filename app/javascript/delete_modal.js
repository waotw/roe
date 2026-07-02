document.addEventListener("turbo:load", function () {
  // Handle delete button clicks
  document.querySelectorAll('[data-action="delete"]').forEach((button) => {
    button.addEventListener("click", function () {
      const id = this.dataset.resourceId;
      const title = this.dataset.resourceTitle;
      const resourceType = this.dataset.resourceType;
      const deleteUrl = this.dataset.deleteUrl;
      showDeleteConfirmation(id, title, resourceType, deleteUrl);
    });
  });

  // Find all delete modals on the page
  const modals = document.querySelectorAll('[id^="delete-modal-"]');

  modals.forEach((modal) => {
    const resourceType = modal.id.replace("delete-modal-", "");
    const deleteInput = document.getElementById(
      `delete-confirmation-input-${resourceType}`,
    );
    const deleteBtn = document.getElementById(
      `delete-confirm-btn-${resourceType}`,
    );

    if (deleteInput && deleteBtn) {
      // Remove any existing listeners by cloning (prevents duplicates)
      const newInput = deleteInput.cloneNode(true);
      deleteInput.parentNode.replaceChild(newInput, deleteInput);

      newInput.addEventListener("input", function () {
        deleteBtn.disabled = this.value !== "DELETE";
      });

      newInput.addEventListener("keydown", function (e) {
        if (e.key === "Enter" && this.value === "DELETE") {
          deleteBtn.form.requestSubmit();
        } else if (e.key === "Escape") {
          hideDeleteConfirmation(resourceType);
        }
      });
    }
  });
});

function showDeleteConfirmation(id, title, resourceType, deleteUrl) {
  document.getElementById("delete-item-title-" + resourceType).textContent =
    title;
  document
    .getElementById("delete-modal-" + resourceType)
    .classList.remove("hidden");
  const input = document.getElementById(
    "delete-confirmation-input-" + resourceType,
  );
  input.value = "";
  input.focus();
  const btn = document.getElementById("delete-confirm-btn-" + resourceType);
  btn.disabled = true;

  // Index pages render one modal for many rows: retarget its delete form to the
  // clicked row's resource. Single-resource pages omit data-delete-url and keep
  // the form action they were rendered with.
  if (deleteUrl && btn && btn.form) {
    btn.form.action = deleteUrl;
  }
}

function hideDeleteConfirmation(resourceType) {
  document
    .getElementById("delete-modal-" + resourceType)
    .classList.add("hidden");
}

// Make functions globally available
window.showDeleteConfirmation = showDeleteConfirmation;
window.hideDeleteConfirmation = hideDeleteConfirmation;
