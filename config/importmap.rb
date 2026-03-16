# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "delete_modal", to: "delete_modal.js", preload: true
pin "editor", to: "editor.js", preload: true
