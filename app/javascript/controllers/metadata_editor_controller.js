import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="metadata-editor"
export default class extends Controller {
  static values = {
    knownFields: Object,
    defaultAuthor: String,
    rawFrontmatter: String,
    originalMetadata: Object,
    postTypes: Object,
    resourceType: String,
    podcastConfigs: Object,
    productCategories: Array,
    mediaPaths: Object,
  };

  static targets = [
    "content",
    "arrow",
    "formView",
    "yamlView",
    "yamlTextarea",
    "toggleBtn",
    "fieldsContainer",
    "addFieldMenu",
    "finalInput",
  ];

  coreFieldNames = [
    "title",
    "subtitle",
    "date",
    "post_type",
    "status",
    "author",
    "tags",
    "url_name",
    "image",
    "excerpt",
    "audience",
    "published_to",
  ];

  connect() {
    // Add initialization flag
    this.isInitializing = true;
    this.isProgrammaticChange = false;

    this.removedFields = new Set();
    this.isYamlView = false;
    this.notifyMetadataChange = this._notifyMetadataChange.bind(this);

    this.restoreSectionState();
    this.setupFormHandler();

    document.addEventListener(
      "click",
      (this.clickOutsideHandler = this.handleClickOutside.bind(this)),
    );

    this.attachChangeListeners();
    this.setupPostTypeListener();
    this.setupPodcastListener();
    this.setupMediaDurationListeners();
    this.setupStatusListener();
    this.setupPublishModalListeners();

    this.fieldsContainerTarget.addEventListener("click", (e) => {
      if (e.target.closest('[data-action*="removeMetadataField"]')) {
        this.removeMetadataField(e);
      }
    });

    // Initialization complete - now start tracking changes
    // Use setTimeout to ensure all initial DOM updates are complete
    setTimeout(() => {
      this.isInitializing = false;
    }, 100);
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler);

    if (this.formHandler) {
      this.formHandler.removeEventListener("submit", this.boundSubmitHandler);
    }

    if (this.boundPublishCancel) {
      document.removeEventListener("publish-modal:cancelled", this.boundPublishCancel);
    }
    if (this.boundPublishConfirm) {
      document.removeEventListener("publish-modal:confirmed", this.boundPublishConfirm);
    }
  }

  // ========== STATE MANAGEMENT ==========

  restoreSectionState() {
    const savedState = sessionStorage.getItem("metadataEditorOpen");

    if (savedState !== null) {
      const shouldBeOpen = savedState === "true";
      if (shouldBeOpen) {
        this.contentTarget.classList.remove("hidden");
        this.arrowTarget.textContent = "▼";
      } else {
        this.contentTarget.classList.add("hidden");
        this.arrowTarget.textContent = "▶";
      }
    } else {
      // First visit in this tab — sync sessionStorage from the server-rendered
      // visibility so the state survives the next save/redirect. Without this,
      // a new post (rendered open via flash[:new_post]) collapses on first save
      // because sessionStorage was never written.
      const isHidden = this.contentTarget.classList.contains("hidden");
      sessionStorage.setItem("metadataEditorOpen", String(!isHidden));
    }
  }

  setupFormHandler() {
    const form = document.getElementById(`${this.resourceTypeValue}-form`);
    if (form) {
      this.formHandler = form;
      this.boundSubmitHandler = this.handleSubmit.bind(this);
      form.addEventListener("submit", this.boundSubmitHandler);
    }

    // Prevent Enter inside metadata text inputs / selects from submitting
    // the form. Users expect Save to happen only via Cmd/Ctrl+S or the
    // Save button, not from hitting Enter while editing a metadata field.
    // Textareas are unaffected (newline is meaningful there).
    this.boundMetadataKeydown = this.handleMetadataKeydown.bind(this);
    this.element.addEventListener("keydown", this.boundMetadataKeydown);
  }

  handleMetadataKeydown(event) {
    if (event.key !== "Enter") return;

    const target = event.target;
    if (!target) return;

    const tag = target.tagName;
    if (tag === "TEXTAREA") return;
    if (tag === "BUTTON") return;

    // Only intercept inputs inside the metadata editor (not the content
    // textarea or any other inputs elsewhere on the page).
    if (!this.element.contains(target)) return;

    event.preventDefault();
  }

  handleSubmit(e) {
    const finalYaml = this.isYamlView
      ? this.yamlTextareaTarget.value
      : this.formToYaml();

    this.finalInputTarget.value = finalYaml;
  }

  // ========== TOGGLE ACTIONS ==========

  toggleMetadataSection() {
    this.contentTarget.classList.toggle("hidden");
    const isHidden = this.contentTarget.classList.contains("hidden");
    this.arrowTarget.textContent = isHidden ? "▶" : "▼";

    // Save state to sessionStorage
    sessionStorage.setItem("metadataEditorOpen", !isHidden);
  }

  toggleMetadataView() {
    this.isYamlView = !this.isYamlView;

    if (this.isYamlView) {
      // Show the RAW frontmatter from the file (with original quotes)
      this.yamlTextareaTarget.value = this.rawFrontmatterValue;

      this.formViewTarget.classList.add("hidden");
      this.yamlViewTarget.classList.remove("hidden");
      this.toggleBtnTarget.textContent = "Edit as Form";

      if (this.contentTarget.classList.contains("hidden")) {
        this.contentTarget.classList.remove("hidden");
        this.arrowTarget.textContent = "▼";
      }
    } else {
      try {
        this.yamlToForm(this.yamlTextareaTarget.value);
        this.formViewTarget.classList.remove("hidden");
        this.yamlViewTarget.classList.add("hidden");
        this.toggleBtnTarget.textContent = "RAW";

        if (this.contentTarget.classList.contains("hidden")) {
          this.contentTarget.classList.remove("hidden");
          this.arrowTarget.textContent = "▼";
        }
      } catch (e) {
        console.error("YAML parsing error:", e);
        alert("Invalid YAML syntax: " + e.message);
        return;
      }
    }

    this.attachChangeListeners();
    this.setupPostTypeListener();
    this.setupStatusListener();
    this._notifyMetadataChange();
  }

  toggleAddFieldMenu() {
    this.addFieldMenuTarget.classList.toggle("hidden");
  }

  handleClickOutside(e) {
    if (
      this.hasAddFieldMenuTarget &&
      !this.addFieldMenuTarget.classList.contains("hidden") &&
      !e.target.closest('[data-action*="toggleAddFieldMenu"]') &&
      !e.target.closest('[data-metadata-editor-target="addFieldMenu"]')
    ) {
      this.addFieldMenuTarget.classList.add("hidden");
    }
  }

  // ========== FIELD ACTIONS ==========

  addKnownField(event) {
    const fieldName = event.currentTarget.dataset.fieldName;
    const config = this.knownFieldsValue[fieldName];
    const container = this.fieldsContainerTarget;

    const row = document.createElement("div");
    row.className = "metadata-field-row flex items-start gap-2";
    row.dataset.fieldName = fieldName;

    // Use default author if adding author field
    const defaultValue =
      fieldName === "author" && config.default_from_config
        ? this.defaultAuthorValue
        : "";

    const inputHtml = this.buildInputHtml(fieldName, config, defaultValue);

    // Conditionally add delete button (not for required fields)
    const deleteButton = config.required
      ? '<div class="w-6 flex-shrink-0"></div>'
      : `<button type="button"
                 data-action="click->metadata-editor#removeMetadataField"
                 class="mt-px px-2 py-1 text-xs bg-red-100 hover:bg-red-200 text-red-700 flex-shrink-0">
          ×
        </button>`;

    row.innerHTML = `
      <label class="font-mono text-xs px-2 py-1 text-gray-700 w-32 flex-shrink-0 pt-1.5">
        ${config.label}:
      </label>
      ${inputHtml}
      ${deleteButton}
    `;

    // Insert in correct position
    const insertBefore = this.findInsertionPoint(fieldName);
    if (insertBefore) {
      container.insertBefore(row, insertBefore);
    } else {
      container.appendChild(row);
    }

    // Hide this field from the menu
    this.addFieldMenuTarget
      .querySelector(`[data-available-field="${fieldName}"]`)
      ?.remove();

    // Check if menu is now empty (except custom field option)
    const remainingFields = this.addFieldMenuTarget.querySelectorAll(
      "[data-available-field]",
    );
    if (remainingFields.length === 0) {
      this.addFieldMenuTarget.querySelector(".border-t")?.remove();
    }

    this.toggleAddFieldMenu();
    this.attachChangeListeners();

    if (fieldName === "post_type") {
      this.setupPostTypeListener();
    }

    if (fieldName === "status") {
      this.setupStatusListener();
    }

    // Add listeners for audio/video fields
    if (fieldName === "audio" || fieldName === "video") {
      this.setupMediaDurationListeners();
    }

    this._notifyMetadataChange();

    // Focus the input
    const input = row.querySelector("[data-metadata-field]");
    if (input) {
      input.focus();
    }
  }

  addCustomField() {
    const container = this.fieldsContainerTarget;

    const row = document.createElement("div");
    row.className = "metadata-field-row flex items-start gap-2";

    row.innerHTML = `
      <input type="text"
             value=""
             placeholder="field_name"
             class="font-mono text-xs px-2 py-1 border border-gray-300 w-32"
             data-custom-key>
      <input type="text"
             value=""
             placeholder="value"
             class="flex-1 font-mono text-xs px-2 py-1 border border-gray-300"
             data-custom-value>
      <button type="button"
              data-action="click->metadata-editor#removeMetadataField"
              class="mt-px px-2 py-1 text-xs bg-red-100 hover:bg-red-200 text-red-700 flex-shrink-0">
        ×
      </button>
    `;

    container.appendChild(row);
    this.toggleAddFieldMenu();
    this.attachChangeListeners();
    this._notifyMetadataChange();

    // Focus the key input
    const keyInput = row.querySelector("[data-custom-key]");
    if (keyInput) {
      keyInput.focus();
    }
  }

  removeMetadataField(event) {
    // When called via event delegation, find the actual button
    const button =
      event.currentTarget.closest('[data-action*="removeMetadataField"]') ||
      event.currentTarget;
    const row = button.closest(".metadata-field-row");

    if (!row) return;

    const fieldName = row.dataset.fieldName;

    // Double-check we're not removing a required field
    if (fieldName && this.knownFieldsValue[fieldName]?.required) {
      return;
    }

    // Track that this field was explicitly removed
    if (fieldName) {
      this.removedFields.add(fieldName);

      // Add field back to the Add Field menu if it's a known field
      if (this.knownFieldsValue[fieldName]) {
        this.restoreFieldToMenu(fieldName);
      }
    }

    row.remove();
    this._notifyMetadataChange();
  }

  restoreFieldToMenu(fieldName) {
    // Don't add if already in menu
    if (
      this.addFieldMenuTarget.querySelector(
        `[data-available-field="${fieldName}"]`,
      )
    ) {
      return;
    }

    // Create the menu button
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.action = "click->metadata-editor#addKnownField";
    button.dataset.fieldName = fieldName;
    button.className =
      "block w-full text-left px-3 py-1.5 hover:bg-gray-100 text-xs font-mono";
    button.dataset.availableField = fieldName;
    button.textContent = fieldName;

    // Find correct insertion point based on known fields order
    const fieldOrder = Object.keys(this.knownFieldsValue);
    const targetIndex = fieldOrder.indexOf(fieldName);

    // Find the first existing menu item that should come after this one
    let insertBefore = null;
    for (let i = targetIndex + 1; i < fieldOrder.length; i++) {
      const laterField = fieldOrder[i];
      const laterButton = this.addFieldMenuTarget.querySelector(
        `[data-available-field="${laterField}"]`,
      );
      if (laterButton) {
        insertBefore = laterButton;
        break;
      }
    }

    if (insertBefore) {
      this.addFieldMenuTarget.insertBefore(button, insertBefore);
    } else {
      // Insert before the divider (last element before Custom field)
      const divider = this.addFieldMenuTarget.querySelector(".border-t");
      if (divider) {
        this.addFieldMenuTarget.insertBefore(button, divider);
      } else {
        this.addFieldMenuTarget.appendChild(button);
      }
    }

    // Re-show the divider if it was hidden
    const divider = this.addFieldMenuTarget.querySelector(".border-t");
    if (divider) {
      divider.style.display = "";
    }
  }

  // ========== HELPER METHODS ==========

  isFieldRequired(fieldName) {
    // Check base config first
    if (this.knownFieldsValue[fieldName]?.required) {
      return true;
    }

    // Check post-type-specific requirements
    const postTypeField = this.element.querySelector(
      '[data-metadata-field="post_type"]',
    );
    if (!postTypeField) return false;

    const currentType = postTypeField.value;
    if (!currentType || !this.postTypesValue[currentType]) return false;

    const typeConfig = this.postTypesValue[currentType];
    const fieldConfig = typeConfig.metadata_fields?.find(
      (f) => f.name === fieldName,
    );

    return fieldConfig?.required === true;
  }

  buildInputHtml(fieldName, config, value) {
    const escapedValue = String(value)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");

    switch (config.type) {
      case "text":
        const readonlyClass = config.readonly
          ? " bg-gray-100 text-gray-600"
          : "";
        const readonlyAttr = config.readonly ? " readonly" : "";

        // Special handling for category field with autocomplete
        if (fieldName === "category" && this.resourceTypeValue === "product") {
          const categories = this.hasProductCategoriesValue
            ? this.productCategoriesValue
            : [];
          const escapedCategories = JSON.stringify(categories).replace(
            /"/g,
            "&quot;",
          );

          return `<div class="flex-1 relative"
                       data-controller="autocomplete"
                       data-autocomplete-options-value="${escapedCategories}">
                    <input type="text"
                           id="metadata-field-${fieldName}"
                           name="metadata_fields[${fieldName}]"
                           value="${escapedValue}"
                           autocomplete="off"
                           class="w-full font-mono text-xs px-2 py-1 border border-gray-300"
                           data-metadata-field="${fieldName}"
                           data-autocomplete-target="input"
                           data-action="input->autocomplete#filter focus->autocomplete#showDropdown keydown->autocomplete#navigate"
                           ${config.hint ? `placeholder="${config.hint}"` : ""}>
                    <div data-autocomplete-target="dropdown"
                         class="hidden absolute top-full left-0 right-0 mt-1 bg-white border border-gray-800 shadow-lg z-50 max-h-48 overflow-y-auto">
                    </div>
                  </div>`;
        }

        // Media fields (audio/video/image/captions): mirror the ERB
        // partial's media-field + autocomplete wrapper so dynamically-added
        // media fields behave identically to ones rendered on initial load.
        const mediaFieldKinds = { audio: "audio", video: "video", image: "image", captions: "file" };
        if (mediaFieldKinds[fieldName]) {
          const kind = mediaFieldKinds[fieldName];
          const paths = (this.hasMediaPathsValue && this.mediaPathsValue[kind]) || [];
          const acEnabled = paths.length > 0;
          const escapedPaths = JSON.stringify(paths).replace(/"/g, "&quot;");
          const acControllers = acEnabled ? "media-field autocomplete" : "media-field";
          const acOptionsAttr = acEnabled
            ? `data-autocomplete-options-value="${escapedPaths}"`
            : "";
          const acTargetAttr = acEnabled ? 'data-autocomplete-target="input"' : "";
          const acActionFragment = acEnabled
            ? "input->autocomplete#filter keydown->autocomplete#navigate"
            : "";
          const dropdown = acEnabled
            ? `<div data-autocomplete-target="dropdown" class="hidden absolute top-full left-0 right-0 mt-1 bg-white border border-gray-800 shadow-lg z-50 max-h-48 overflow-y-auto"></div>`
            : "";

          return `<div class="flex-1 flex flex-col gap-1 ${acEnabled ? "relative" : ""}"
                       data-controller="${acControllers}"
                       data-media-field-kind-value="${kind}"
                       ${acOptionsAttr}>
                    <input type="text"
                           id="metadata-field-${fieldName}"
                           name="metadata_fields[${fieldName}]"
                           value="${escapedValue}"
                           autocomplete="off"
                           class="w-full font-mono text-xs px-2 py-1 border border-gray-300"
                           data-metadata-field="${fieldName}"
                           data-media-field-target="input"
                           ${acTargetAttr}
                           data-action="input->media-field#checkDebounced ${acActionFragment} blur->media-field#check change->media-field#check"
                           ${config.hint ? `placeholder="${config.hint}"` : ""}>
                    ${dropdown}
                    <p class="text-xs text-red-600 hidden" data-media-field-target="warning">
                      ⚠ File not found under <code>site/media/</code>.
                    </p>
                  </div>`;
        }

        return `<input type="text"
                         id="metadata-field-${fieldName}"
                         name="metadata_fields[${fieldName}]"
                         value="${escapedValue}"
                         autocomplete="off"
                         class="flex-1 font-mono text-xs px-2 py-1 border border-gray-300${readonlyClass}"
                         data-metadata-field="${fieldName}"
                         ${config.hint ? `placeholder="${config.hint}"` : ""}${readonlyAttr}>`;

      case "datetime":
        let datetimeValue = value;
        if (value && value.includes("T")) {
          datetimeValue = value.slice(0, 16);
        }
        return `<input type="datetime-local"
                       id="metadata-field-${fieldName}"
                       name="metadata_fields[${fieldName}]"
                       value="${datetimeValue}"
                       class="flex-1 font-mono text-xs px-2 py-1 border border-gray-300"
                       data-metadata-field="${fieldName}">`;

      case "select":
        const options = config.options
          .map(
            (opt) =>
              `<option value="${opt}" ${opt === value ? "selected" : ""}>${opt}</option>`,
          )
          .join("");
        return `<select id="metadata-field-${fieldName}"
                        name="metadata_fields[${fieldName}]"
                        class="flex-1 font-mono text-xs px-2 py-1 border border-gray-300"
                        data-metadata-field="${fieldName}">
                  <option value="">-- select --</option>
                  ${options}
                </select>`;

      case "textarea":
        return `<textarea id="metadata-field-${fieldName}"
                          name="metadata_fields[${fieldName}]"
                          rows="2"
                          class="flex-1 font-mono text-xs px-2 py-1 border border-gray-300"
                          data-metadata-field="${fieldName}">${value}</textarea>`;

      default:
        return "";
    }
  }

  findInsertionPoint(fieldName) {
    const container = this.fieldsContainerTarget;
    const fieldOrder = Object.keys(this.knownFieldsValue);
    const targetIndex = fieldOrder.indexOf(fieldName);

    if (targetIndex === -1) return null;

    // First, try to find a field that should come AFTER this one (existing behavior)
    for (let i = targetIndex + 1; i < fieldOrder.length; i++) {
      const laterFieldName = fieldOrder[i];
      const laterRow = container.querySelector(
        `.metadata-field-row[data-field-name="${laterFieldName}"]`,
      );

      if (laterRow && laterRow.style.display !== "none") {
        return laterRow;
      }
    }

    // If no field found after, try to find a field that should come BEFORE this one
    // and insert after it (by finding the next field after that one)
    for (let i = targetIndex - 1; i >= 0; i--) {
      const earlierFieldName = fieldOrder[i];
      const earlierRow = container.querySelector(
        `.metadata-field-row[data-field-name="${earlierFieldName}"]`,
      );

      if (earlierRow && earlierRow.style.display !== "none") {
        // Found a field before this one, insert after it
        return earlierRow.nextElementSibling;
      }
    }

    return null;
  }

  // ========== YAML CONVERSION ==========

  formatYamlValue(value, fieldName = null) {
    // Special handling for tags field - convert comma-separated to array
    if (fieldName === "tags") {
      if (value === null || value === undefined || value === "") {
        return "[]";
      }

      const strValue = String(value).trim();
      if (strValue === "" || strValue === "[]") {
        return "[]";
      }

      // Parse comma-separated tags
      const tags = strValue
        .split(",")
        .map((tag) => tag.trim())
        .filter((tag) => tag !== "");

      if (tags.length === 0) {
        return "[]";
      }

      // Format as YAML array with quotes
      return "[" + tags.map((tag) => `"${tag}"`).join(", ") + "]";
    }

    // Standard formatting for other fields
    if (value === null || value === undefined) {
      return '""';
    }

    const strValue = String(value);

    if (strValue === "") {
      return '""';
    }

    if (!isNaN(strValue) && strValue.trim() !== "") {
      return strValue;
    }

    if (strValue === "true" || strValue === "false") {
      return strValue;
    }

    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(strValue)) {
      const minutePrecision = strValue.slice(0, 16);
      return `"${minutePrecision}Z"`;
    }

    return `"${strValue.replace(/"/g, '\\"')}"`;
  }

  formToYaml() {
    const fields = { ...this.originalMetadataValue };

    // Update with form values - ONLY VISIBLE FIELDS
    this.element.querySelectorAll("[data-metadata-field]").forEach((input) => {
      const row = input.closest(".metadata-field-row");

      if (row && row.style.display === "none") {
        return;
      }

      const fieldName = input.dataset.metadataField;
      let value = input.value.trim();
      fields[fieldName] = value;
    });

    // Remove fields that were explicitly deleted by user
    this.removedFields.forEach((field) => {
      delete fields[field];
    });

    // Update with custom fields (only visible)
    this.element.querySelectorAll("[data-custom-key]").forEach((keyInput) => {
      const row = keyInput.closest(".metadata-field-row");

      if (row && row.style.display === "none") {
        return;
      }

      const valueInput = keyInput.nextElementSibling;
      const key = keyInput.value.trim();
      const value = valueInput.value.trim();

      if (key !== "") {
        fields[key] = value;
      }
    });

    // Separate known fields from custom fields
    const knownFields = {};
    const customFields = {};

    for (const [key, value] of Object.entries(fields)) {
      if (this.knownFieldsValue[key]) {
        knownFields[key] = value;
      } else {
        customFields[key] = value;
      }
    }

    let yaml = "";

    // Output known fields in config order
    Object.keys(this.knownFieldsValue).forEach((key) => {
      if (knownFields.hasOwnProperty(key)) {
        yaml += `${key}: ${this.formatYamlValue(knownFields[key], key)}\n`;
      }
    });

    // Then output custom fields (sorted alphabetically)
    Object.keys(customFields)
      .sort()
      .forEach((key) => {
        yaml += `${key}: ${this.formatYamlValue(customFields[key], key)}\n`;
      });

    return yaml;
  }

  yamlToForm(yamlText) {
    const lines = yamlText.split("\n");
    const fields = {};

    lines.forEach((line) => {
      if (!line.trim()) return;

      const colonIndex = line.indexOf(":");
      if (colonIndex === -1) return;

      let key = line.substring(0, colonIndex).trim();
      let value = line.substring(colonIndex + 1).trim();

      // Special handling for tags array
      if (key === "tags") {
        if (value === "[]" || value === "") {
          fields[key] = "";
          return;
        }

        // Parse array format: ["tag1", "tag2"]
        if (value.startsWith("[") && value.endsWith("]")) {
          const arrayContent = value.slice(1, -1);
          const tags = arrayContent
            .split(",")
            .map((tag) => tag.trim().replace(/^["']|["']$/g, ""))
            .filter((tag) => tag !== "");
          fields[key] = tags.join(", ");
          return;
        }
      }

      // Standard parsing for other fields
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }

      value = value.replace(/\\"/g, '"').replace(/\\'/g, "'");

      fields[key] = value;
    });

    // Clear and rebuild form
    const container = this.fieldsContainerTarget;
    container.innerHTML = "";

    // First add known fields in the correct order (based on knownFieldsValue order)
    Object.keys(this.knownFieldsValue).forEach((key) => {
      if (fields.hasOwnProperty(key)) {
        this.addKnownFieldToForm(key, fields[key]);
      }
    });

    // Then add custom fields at the end
    Object.keys(fields).forEach((key) => {
      if (!this.knownFieldsValue[key]) {
        this.addCustomFieldToForm(key, fields[key]);
      }
    });
  }

  addKnownFieldToForm(fieldName, value) {
    const config = this.knownFieldsValue[fieldName];
    const container = this.fieldsContainerTarget;

    const row = document.createElement("div");
    row.className = "metadata-field-row flex items-start gap-2";
    row.dataset.fieldName = fieldName;

    // Build input HTML
    const inputHtml = this.buildInputHtml(fieldName, config, value);

    // Check if required (base config OR post-type-specific)
    const isRequired = this.isFieldRequired(fieldName);
    const asterisk = isRequired
      ? '<span class="text-red-600 ml-0.5">*</span>'
      : "";

    // Define delete button (must be BEFORE row.innerHTML)
    const deleteButton = isRequired
      ? '<div class="w-6 flex-shrink-0"></div>'
      : `<button type="button"
                 data-action="click->metadata-editor#removeMetadataField"
                 class="mt-px px-2 py-1 text-xs bg-red-100 hover:bg-red-200 text-red-700 flex-shrink-0">
          ×
        </button>`;

    // Now use all the variables
    row.innerHTML = `
      <label class="font-mono text-xs px-2 py-1 text-gray-700 w-32 flex-shrink-0 pt-1.5">
        ${config.label}${asterisk}:
      </label>
      ${inputHtml}
      ${deleteButton}
    `;

    // Insert in correct position based on known_fields_config order
    const insertBefore = this.findInsertionPoint(fieldName);
    if (insertBefore) {
      container.insertBefore(row, insertBefore);
    } else {
      container.appendChild(row);
    }

    // Focus the input
    const input = row.querySelector("[data-metadata-field]");
    if (input) {
      input.focus();
    }
  }

  addCustomFieldToForm(key, value) {
    const container = this.fieldsContainerTarget;

    const row = document.createElement("div");
    row.className = "metadata-field-row flex items-start gap-2";

    row.innerHTML = `
      <input type="text"
             value="${key}"
             placeholder="field_name"
             class="font-mono text-xs px-2 py-1 border border-gray-300 w-32"
             data-custom-key>
      <input type="text"
             value="${value}"
             placeholder="value"
             class="flex-1 font-mono text-xs px-2 py-1 border border-gray-300"
             data-custom-value>
      <button type="button"
              data-action="click->metadata-editor#removeMetadataField"
              class="mt-px px-2 py-1 text-xs bg-red-100 hover:bg-red-200 text-red-700 flex-shrink-0">
        ×
      </button>
    `;

    container.appendChild(row);

    // Focus the key input
    const keyInput = row.querySelector("[data-custom-key]");
    if (keyInput) {
      keyInput.focus();
    }
  }

  // ========== POST TYPE HANDLING ==========

  getFieldsForType(postType) {
    if (!postType || !this.postTypesValue) return [];

    const typeConfig = this.postTypesValue[postType];
    if (!typeConfig) return [];

    return (typeConfig.metadata_fields || []).map((field) => field.name);
  }

  handlePostTypeChange(event) {
    const newType = event.target.value;
    this.updateFieldVisibility(newType);
    // Don't notify on initial load - only when user actually changes something
  }

  setupPostTypeListener() {
    const postTypeField = this.element.querySelector(
      '[data-metadata-field="post_type"]',
    );

    if (postTypeField) {
      // Remove old listener if exists
      if (this.postTypeHandler) {
        postTypeField.removeEventListener("change", this.postTypeHandler);
      }

      this.postTypeHandler = this.handlePostTypeChange.bind(this);
      postTypeField.addEventListener("change", this.postTypeHandler);

      // Always run on load to set initial field visibility
      this.handlePostTypeChange({ target: postTypeField });
    }
  }

  setupPostTypeListener() {
    const postTypeField = this.element.querySelector(
      '[data-metadata-field="post_type"]',
    );

    if (postTypeField) {
      // Remove old listener if exists
      if (this.postTypeHandler) {
        postTypeField.removeEventListener("change", this.postTypeHandler);
      }

      this.postTypeHandler = this.handlePostTypeChange.bind(this);
      postTypeField.addEventListener("change", this.postTypeHandler);

      // Always run on load to set initial field visibility
      this.handlePostTypeChange({ target: postTypeField });
    }
  }

  // ========== PODCAST CONFIG AUTO-POPULATION ==========

  setupPodcastListener() {
    const podcastField = this.element.querySelector(
      '[data-metadata-field="podcast"]',
    );

    if (podcastField) {
      // Remove old listener if exists
      if (this.podcastHandler) {
        podcastField.removeEventListener("change", this.podcastHandler);
      }

      this.podcastHandler = this.handlePodcastChange.bind(this);
      podcastField.addEventListener("change", this.podcastHandler);
    }
  }

  handlePodcastChange(event) {
    const selectedPodcast = event.target.value;
    if (!selectedPodcast || !this.podcastConfigsValue[selectedPodcast]) return;

    const podcastConfig = this.podcastConfigsValue[selectedPodcast];

    // Auto-populate explicit if not already set
    const explicitField = this.element.querySelector(
      '[data-metadata-field="explicit"]',
    );
    if (explicitField && (!explicitField.value || explicitField.value === "")) {
      explicitField.value =
        podcastConfig.explicit !== undefined
          ? String(podcastConfig.explicit)
          : "false";
    }

    // Do NOT auto-fill author from podcast config — leave it blank so the
    // podcast.yml author is used as a fallback at render time. Only clear
    // it if it was previously auto-filled with the site default author.
    const authorField = this.element.querySelector(
      '[data-metadata-field="author"]',
    );
    if (authorField && authorField.value === this.defaultAuthorValue) {
      authorField.value = "";
    }

    this._notifyMetadataChange();
  }

  // ========== POST TYPE HANDLING ==========

  // Update visibility of all fields based on current post type
  updateFieldVisibility(postType) {
    const typeSpecificFields = this.getFieldsForType(postType);
    const visibleFields = [...this.coreFieldNames, ...typeSpecificFields];

    // Hide/show existing fields based on new type
    const allRows = this.fieldsContainerTarget.querySelectorAll(
      ".metadata-field-row",
    );

    allRows.forEach((row) => {
      const fieldName = row.dataset.fieldName;
      if (!fieldName) return;

      // Show if it's a visible field, or if it's a custom field (not in knownFields)
      if (
        visibleFields.includes(fieldName) ||
        !this.knownFieldsValue[fieldName]
      ) {
        row.style.display = "";
      } else {
        // Hide and clear value for type-specific fields that no longer apply
        row.style.display = "none";
        const input = row.querySelector("[data-metadata-field]");
        if (input) {
          if (input.tagName === "SELECT") {
            input.selectedIndex = 0;
          } else {
            input.value = "";
          }
        }
      }
    });

    // Add missing type-specific fields
    typeSpecificFields.forEach((fieldName) => {
      const existingRow = this.fieldsContainerTarget.querySelector(
        `.metadata-field-row[data-field-name="${fieldName}"]`,
      );

      if (!existingRow && this.knownFieldsValue[fieldName]) {
        // Field doesn't exist - add it with default value if applicable
        const config = this.knownFieldsValue[fieldName];

        // Determine default value based on field
        const defaultValue = (() => {
          if (fieldName === "author" && config.default_from_config) {
            return this.defaultAuthorValue;
          }
          if (fieldName === "episode_type") {
            return "full";
          }
          if (fieldName === "podcast") {
            // Leave blank — `podcast:` is optional. A podcast post with no
            // value renders on the site but doesn't appear in any RSS feed
            // (matches Substack's "local-only" podcast pattern). Auto-
            // selecting the first option misled imports of episodes that
            // were intentionally never in a feed into looking connected.
            return "";
          }
          return "";
        })();

        this.addKnownFieldToForm(fieldName, defaultValue);
        this.attachChangeListeners();

        // Set up podcast listener when field is added (but don't trigger yet)
        if (fieldName === "podcast") {
          this.setupPodcastListener();
        }
      } else if (existingRow) {
        // Field exists but was hidden - show it
        existingRow.style.display = "";
        existingRow.classList.remove("hidden");
      }
    });

    // AFTER all fields are added, trigger podcast config population
    const podcastField = this.element.querySelector(
      '[data-metadata-field="podcast"]',
    );
    if (podcastField && podcastField.value) {
      // Trigger population from podcast config
      this.handlePodcastChange({ target: podcastField });
    }
  }

  // ========== CHANGE NOTIFICATION ==========

  attachChangeListeners() {
    this.element
      .querySelectorAll(
        "[data-metadata-field], [data-custom-key], [data-custom-value]",
      )
      .forEach((input) => {
        input.removeEventListener("input", this.notifyMetadataChange);
        input.removeEventListener("change", this.notifyMetadataChange);
        input.addEventListener("input", this.notifyMetadataChange);
        input.addEventListener("change", this.notifyMetadataChange);
      });

    if (this.hasYamlTextareaTarget) {
      this.yamlTextareaTarget.removeEventListener(
        "input",
        this.notifyMetadataChange,
      );
      this.yamlTextareaTarget.addEventListener(
        "input",
        this.notifyMetadataChange,
      );
    }
  }

  _notifyMetadataChange() {
    // Don't notify during initialization
    if (this.isInitializing || this.isProgrammaticChange) {
      return;
    }

    const finalYaml = this.isYamlView
      ? this.yamlTextareaTarget.value
      : this.formToYaml();

    this.finalInputTarget.value = finalYaml;

    const event = new CustomEvent("metadata:changed", {
      detail: { yaml: finalYaml },
    });
    document.dispatchEvent(event);
  }

  // ========== MEDIA DURATION AUTO-POPULATION ==========

  setupMediaDurationListeners() {
    // Watch audio and video fields
    const audioField = this.element.querySelector(
      '[data-metadata-field="audio"]',
    );
    const videoField = this.element.querySelector(
      '[data-metadata-field="video"]',
    );

    if (audioField) {
      audioField.addEventListener("blur", (e) =>
        this.handleMediaFieldChange(e),
      );
    }

    if (videoField) {
      videoField.addEventListener("blur", (e) =>
        this.handleMediaFieldChange(e),
      );
    }

    // Check on initial load if duration should be visible
    this.updateDurationFieldVisibility();
  }

  // ========== STATUS / PUBLISH HANDLING ==========

  // When the user changes the status select to 'published' from 'draft'
  // or 'unlisted', open the publish modal instead of letting the change
  // sit in the form. The modal's confirm path will save & publish in
  // one round trip. Cancel reverts the select back.
  setupStatusListener() {
    const statusField = this.element.querySelector(
      '[data-metadata-field="status"]',
    );
    if (!statusField) return;

    this._previousStatus = statusField.value || "draft";

    if (this.statusChangeHandler) {
      statusField.removeEventListener("change", this.statusChangeHandler);
    }
    this.statusChangeHandler = this.handleStatusChange.bind(this);
    statusField.addEventListener("change", this.statusChangeHandler);
  }

  handleStatusChange(event) {
    const newValue = event.target.value;
    const oldValue = this._previousStatus;

    const isPublishingTransition =
      newValue === "published" &&
      (oldValue === "draft" || oldValue === "unlisted");

    if (isPublishingTransition) {
      this._pendingStatusRevert = {
        element: event.target,
        previousValue: oldValue,
      };
      // Hand off to editor controller, which owns the modal.
      document.dispatchEvent(
        new CustomEvent("metadata-editor:publish-requested", { bubbles: true }),
      );
    }

    // Track latest value so subsequent changes compare correctly.
    this._previousStatus = newValue;
  }

  setupPublishModalListeners() {
    this.boundPublishCancel = this.handlePublishModalCancelled.bind(this);
    this.boundPublishConfirm = this.handlePublishModalConfirmed.bind(this);
    document.addEventListener("publish-modal:cancelled", this.boundPublishCancel);
    document.addEventListener("publish-modal:confirmed", this.boundPublishConfirm);
  }

  handlePublishModalCancelled() {
    if (!this._pendingStatusRevert) return;

    const { element, previousValue } = this._pendingStatusRevert;
    element.value = previousValue;
    this._previousStatus = previousValue;
    this._pendingStatusRevert = null;
  }

  handlePublishModalConfirmed() {
    // The publish actually went through — no revert needed. Update our
    // tracked previous value so a follow-up status change compares
    // against 'published'.
    this._previousStatus = "published";
    this._pendingStatusRevert = null;
  }

  handleMediaFieldChange(event) {
    const mediaPath = event.target.value.trim();

    if (mediaPath === "") {
      // Media removed - hide duration field
      this.updateDurationFieldVisibility();
      return;
    }

    // Media path entered - fetch duration
    this.fetchAndPopulateDuration(mediaPath);
  }

  async fetchAndPopulateDuration(mediaPath) {
    const extension = mediaPath.split(".").pop().toLowerCase();
    const isAudio = ["mp3", "m4a", "wav", "ogg", "flac", "aac"].includes(
      extension,
    );
    const isVideo = ["mp4", "webm", "ogv", "mov", "avi", "mkv"].includes(
      extension,
    );

    if (!isAudio && !isVideo) {
      console.warn("Not a supported audio/video file");
      return;
    }

    try {
      // Create a temporary media element to load the file
      const mediaElement = isAudio
        ? new Audio()
        : document.createElement("video");

      // Wait for metadata to load
      const duration = await new Promise((resolve, reject) => {
        mediaElement.addEventListener("loadedmetadata", () => {
          resolve(mediaElement.duration);
        });

        mediaElement.addEventListener("error", (e) => {
          reject(new Error("Failed to load media file"));
        });

        // Set source and load
        mediaElement.src = mediaPath;
        mediaElement.load();
      });

      // Format duration as HH:MM:SS
      const formatted = this.formatDuration(Math.floor(duration));

      // Mark as programmatic change to avoid triggering save warning
      this.isProgrammaticChange = true;

      // Populate duration field
      const durationField = this.element.querySelector(
        '[data-metadata-field="duration"]',
      );

      if (durationField) {
        durationField.value = formatted;
        this._notifyMetadataChange();
      } else {
        // Duration field doesn't exist - add it
        this.addDurationField(formatted);
      }

      // Reset flag after a short delay
      setTimeout(() => {
        this.isProgrammaticChange = false;
      }, 100);
    } catch (error) {
      console.error("Error extracting duration:", error);
    }
  }

  formatDuration(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;

    return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
  }

  addDurationField(durationValue) {
    // Check if duration field is in known fields but not rendered
    if (!this.knownFieldsValue["duration"]) return;

    // Add the duration field with the value
    const container = this.fieldsContainerTarget;
    const config = this.knownFieldsValue["duration"];

    const row = document.createElement("div");
    row.className = "metadata-field-row flex items-start gap-2";
    row.dataset.fieldName = "duration";

    row.innerHTML = `
        <label class="font-mono text-xs px-2 py-1 text-gray-700 w-32 flex-shrink-0 pt-1.5">
          duration:
        </label>
        <input type="text"
               id="metadata-field-duration"
               name="metadata_fields[duration]"
               value="${durationValue}"
               class="flex-1 font-mono text-xs px-2 py-1 border border-gray-300 bg-gray-200 text-gray-600"
               data-metadata-field="duration"
               placeholder="${config.hint || ""}"
               readonly>
        <div class="w-6 flex-shrink-0"></div>
      `;

    // Insert in correct position
    const insertBefore = this.findInsertionPoint("duration");
    if (insertBefore) {
      container.insertBefore(row, insertBefore);
    } else {
      container.appendChild(row);
    }

    // Remove from "Add Field" menu if present
    this.addFieldMenuTarget
      .querySelector('[data-available-field="duration"]')
      ?.remove();

    this._notifyMetadataChange();
  }

  updateDurationFieldVisibility() {
    const audioField = this.element.querySelector(
      '[data-metadata-field="audio"]',
    );
    const videoField = this.element.querySelector(
      '[data-metadata-field="video"]',
    );
    const durationRow = this.element.querySelector(
      '[data-field-name="duration"]',
    );

    const hasMedia =
      audioField?.value.trim() || videoField?.value.trim() ? true : false;

    if (!hasMedia && durationRow) {
      // No media - remove duration field
      durationRow.remove();

      // Add back to menu if not already there
      if (
        !this.addFieldMenuTarget.querySelector(
          '[data-available-field="duration"]',
        )
      ) {
        this.restoreFieldToMenu("duration");
      }

      this._notifyMetadataChange();
    }
  }
}
