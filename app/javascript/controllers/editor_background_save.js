// Background save for the content editor (posts, pages, products).
//
// A plain Save used to post the form and rebuild the whole page: every editor
// controller torn down, CodeMirror recreated, scroll and cursor put back from
// sessionStorage — and the undo history gone. Here the form is sent with
// fetch and the page stays as it is. Only what the save changed is updated.
//
// What a reload used to refresh, and who does it now:
//   - the save-state dot, the dirty baseline and the local draft: here, and
//     only once the server says the save worked (they were set before the
//     request was even sent);
//   - the metadata panel: the server sends it back, rendered as the edit page
//     would draw it, when the file's metadata now differs from what was sent
//     (a podcast GUID, a filled-in duration, tidied tags). Swapped only if
//     nothing was typed in it during the save;
//   - the saved address the "you changed a live URL" prompt compares against;
//   - the preview window, if open.
//
// Anything that changes more of the page — publishing, a status change, a
// redirect written, a notice to show — comes back as `reload: true`, and the
// page loads as before (EditorController#_prepareForReload keeps the place).
//
// Server side: the EditorSave concern (app/controllers/concerns/editor_save.rb).

const BACKGROUND_TYPES = ["post", "page", "product"];
const ERROR_CLASS = "text-red-700";

// A short line for the save indicator, and a longer one for its tooltip.
class SaveError extends Error {
  constructor([short, detail]) {
    super(short);
    this.lines = [short, detail];
  }
}

// Whether this submit can be saved in the background. Emails keep the old
// path, and so does any button that sends the form somewhere else (the
// invite-mode "Send to N members" sets formaction).
export function wantsBackgroundSave(controller, event) {
  if (!BACKGROUND_TYPES.includes(controller.resourceTypeValue)) return false;
  if (event?.submitter?.hasAttribute("formaction")) return false;
  return typeof window.fetch === "function";
}

// A Save pressed while one is under way runs once more when it finishes, so
// the last thing typed is always what's on disk.
export function backgroundSave(controller) {
  if (controller._backgroundSaveInFlight) {
    controller._backgroundSaveQueued = true;
    return;
  }
  controller._backgroundSaveInFlight = true;
  // Let the form's other submit listeners finish first — the metadata editor
  // writes the final YAML into the hidden field on submit.
  setTimeout(() => run(controller), 0);
}

async function run(controller) {
  const form = controller.formTarget;
  const sentContent = controller.textareaTarget.value;
  const sentMetadata = controller.currentMetadataValue();

  showMessage(controller, "saving…"); // COPY

  let reply;
  try {
    const response = await fetch(form.action, {
      method: "POST",
      body: new FormData(form),
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token":
          document.querySelector('meta[name="csrf-token"]')?.content || "",
      },
    });

    // Signed out: fetch followed the redirect to the sign-in page.
    if (!(response.headers.get("content-type") || "").includes("json")) {
      throw new SaveError(
        response.redirected
          ? ["not saved — signed out", "Sign in again in another tab, then save. Your changes are still here."] // COPY
          : [`not saved — error ${response.status}`, "Your changes are still here. Try saving again."], // COPY
      );
    }
    reply = await response.json();
    if (!response.ok || !reply.saved) {
      throw new SaveError([
        `not saved — error ${response.status}`, // COPY
        reply.error || "Your changes are still here. Try saving again.", // COPY
      ]);
    }
  } catch (error) {
    failed(
      controller,
      error instanceof SaveError
        ? error.lines
        : ["not saved — can't reach roe", "Is Roe still running? Your changes are still here."], // COPY
    );
    finish(controller);
    return;
  }

  if (reply.reload) {
    controller._prepareForReload();
    if (window.Turbo) {
      window.Turbo.visit(reply.url, { action: "replace" });
    } else {
      window.location.href = reply.url;
    }
    return;
  }

  succeeded(controller, reply, sentContent, sentMetadata);
  finish(controller);
}

function succeeded(controller, reply, sentContent, sentMetadata) {
  // The baseline is what was SENT. Anything typed while the save was under
  // way stays unsaved, and the dot says so.
  controller.originalContent = sentContent;

  if (reply.metadata_html && controller.currentMetadataValue() === sentMetadata) {
    swapMetadataPanel(controller, reply.metadata_html);
    controller.originalMetadata = controller.currentMetadataValue();
  } else {
    controller.originalMetadata = sentMetadata;
  }

  // The "you changed a live URL" prompt compares against the saved address.
  if (typeof reply.url_name === "string") {
    controller.originalUrlNameValue = reply.url_name;
  }
  controller._redirectDecisionMade = false;
  if (controller.hasRedirectFromFieldTarget) {
    controller.redirectFromFieldTarget.value = "";
  }

  // The file is now the baseline a later draft is checked against.
  controller.draftBaseline = controller.fingerprint(
    controller.originalContent,
    controller.originalMetadata,
  );
  if (controller.isDirty()) {
    controller.scheduleDraftSave();
  } else {
    controller.clearDraft();
  }

  controller.savedThisSession = true;
  controller.updateSaveState();

  if (controller.previewOpened) controller.pushPreviewUpdate();
}

function failed(controller, [short, detail]) {
  // Nothing changes: the baseline, the draft and the text stay as they were,
  // so the dot stays amber and the work is still covered.
  controller.updateSaveState();
  controller.saveMessageTargets.forEach((el) => {
    el.textContent = short;
    el.title = detail || "";
    el.classList.add(ERROR_CLASS);
  });
}

function finish(controller) {
  controller._backgroundSaveInFlight = false;
  if (controller._backgroundSaveQueued) {
    controller._backgroundSaveQueued = false;
    backgroundSave(controller);
  }
}

function showMessage(controller, text) {
  controller.saveMessageTargets.forEach((el) => {
    el.textContent = text;
    el.title = "";
    el.classList.remove(ERROR_CLASS);
  });
}

// Put the server's metadata panel in place of the current one. Stimulus
// disconnects the old panel's controllers and connects the new ones, exactly
// as on a page load. The writer's place in the panel is kept: the field they
// were in (and the caret in it), and the RAW view if they were using it.
// Open/closed is kept by the panel itself (sessionStorage).
function swapMetadataPanel(controller, html) {
  const current = controller.element.querySelector("#metadata-container");
  if (!current) return;

  const template = document.createElement("template");
  template.innerHTML = html.trim();
  const fresh = template.content.querySelector("#metadata-container");
  if (!fresh) return;

  const active = document.activeElement;
  const hadFocus = active && current.contains(active);
  // Which element to put the caret back in: a form field by name, or the
  // RAW textarea.
  const focusedField = hadFocus ? active.dataset.metadataField : null;
  const focusedRaw =
    hadFocus && active.dataset.metadataEditorTarget === "yamlTextarea";
  const selection =
    hadFocus && typeof active.selectionStart === "number"
      ? [active.selectionStart, active.selectionEnd]
      : null;
  const wasRaw = !current
    .querySelector('[data-metadata-editor-target="yamlView"]')
    ?.classList.contains("hidden");

  current.replaceWith(fresh);

  // Stimulus connects the new panel in a microtask; a timeout runs after it.
  // Both steps wait for that: the panel arrives closed (the server's default)
  // until its controller reopens it, and a hidden field can't take focus. Not
  // requestAnimationFrame — a tab in the background never runs it.
  setTimeout(() => {
    if (wasRaw) {
      const panel = window.Stimulus?.getControllerForElementAndIdentifier(
        fresh,
        "metadata-editor",
      );
      if (panel && !panel.isYamlView) panel.toggleMetadataView();
    }

    let field = null;
    if (focusedRaw) {
      field = fresh.querySelector('[data-metadata-editor-target="yamlTextarea"]');
    } else if (focusedField) {
      field = fresh.querySelector(
        `[data-metadata-field="${CSS.escape(focusedField)}"]`,
      );
    }
    if (!field) return;

    field.focus({ preventScroll: true });
    if (selection && typeof field.setSelectionRange === "function") {
      try {
        field.setSelectionRange(...selection);
      } catch (e) {
        /* inputs like date don't take a selection */
      }
    }
  });
}
