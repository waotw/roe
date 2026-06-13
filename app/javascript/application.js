// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";
import "delete_modal";
import "theme_reset_modal";
import "update_theme_modal";

// Auto-dismiss floating flash messages
document.addEventListener("turbo:load", function () {
  const flashMessages = document.querySelectorAll("[data-flash-message]");

  flashMessages.forEach(function (flash) {
    // Auto-dismiss after 3 seconds - just remove it
    setTimeout(function () {
      flash.remove();
    }, 4000);

    // Allow manual dismiss on click
    flash.style.cursor = "pointer";
    flash.addEventListener("click", function () {
      flash.remove();
    });
  });
});
