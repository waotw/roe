// Copy text to the clipboard, wherever the page is served from.
//
// navigator.clipboard only exists in a secure context — https, or plain
// http on localhost. A registered Roe install runs at http://<name>.roe,
// which is neither, so on exactly the address every new install uses the
// API is undefined and every "Copy" button silently did nothing. The
// textarea + execCommand("copy") route is deprecated but still works in
// every browser and has no such restriction, so it's the fallback.
//
// Returns a promise that resolves on success and rejects when neither
// route could copy, so callers can show "Copied" or "Press ⌘/Ctrl-C".
//
// Also exposed as window.copyToClipboard for the inline <script> blocks
// in admin views that aren't Stimulus controllers.
export async function copyToClipboard(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch (_) {
      // Fall through — permission denied, or a browser that has the
      // object but refuses in this context.
    }
  }
  if (!fallbackCopy(text)) throw new Error("clipboard unavailable");
}

function fallbackCopy(text) {
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.setAttribute("readonly", "");
  ta.style.position = "fixed";
  ta.style.top = "0";
  ta.style.left = "0";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.focus();
  ta.select();
  let ok = false;
  try {
    ok = document.execCommand("copy");
  } catch (_) {
    ok = false;
  }
  ta.remove();
  return ok;
}

window.copyToClipboard = copyToClipboard;
