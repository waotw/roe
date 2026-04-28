# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "delete_modal", to: "delete_modal.js", preload: true
pin "theme_reset_modal", to: "theme_reset_modal.js", preload: true
pin "editor", to: "editor.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
