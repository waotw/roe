// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";
import "delete_modal";
import "theme_reset_modal";
import "update_theme_modal";

// Auto-dismiss floating flash messages. Re-runs on both turbo:load
// (initial loads + successful redirects) AND turbo:render (form
// re-renders via 422 responses) so any flash added during a
// re-render still picks up the click + timeout handlers. A
// per-element wired-flag prevents double-binding if both events
// fire for the same DOM node.
function wireDismissibleFlashes() {
  document.querySelectorAll("[data-flash-message]").forEach(function (flash) {
    if (flash.dataset.flashWired === "1") return;
    flash.dataset.flashWired = "1";

    setTimeout(function () {
      flash.remove();
    }, 4000);

    flash.style.cursor = "pointer";
    flash.addEventListener("click", function () {
      flash.remove();
    });
  });
}
document.addEventListener("turbo:load",   wireDismissibleFlashes);
document.addEventListener("turbo:render", wireDismissibleFlashes);
