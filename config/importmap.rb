# Pin npm packages by running ./bin/importmap

pin "application"
pin "clipboard", to: "clipboard.js", preload: true
pin "media_duration", to: "media_duration.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "delete_modal", to: "delete_modal.js", preload: true
pin "theme_reset_modal", to: "theme_reset_modal.js", preload: true
pin "update_theme_modal", to: "update_theme_modal.js", preload: true

pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# The live markdown editor (app/javascript/markdown_editor) and CodeMirror 6,
# vendored by `bin/importmap pin`. preload: false on all of them — importmap
# preloads every pin by default, which would make every page, public ones
# included, download ~900 KB it never uses. They load only when the editor
# imports them.
pin_all_from "app/javascript/markdown_editor", under: "markdown_editor", preload: false
pin "@codemirror/state", to: "@codemirror--state.js", preload: false # @6.7.6
pin "@marijn/find-cluster-break", to: "@marijn--find-cluster-break.js", preload: false # @1.0.4
pin "@codemirror/view", to: "@codemirror--view.js", preload: false # @6.43.14
pin "crelt", preload: false # @1.0.7
pin "style-mod", preload: false # @4.1.4
pin "w3c-keyname", preload: false # @2.2.8
pin "@codemirror/search", to: "@codemirror--search.js", preload: false # @6.7.2
pin "@codemirror/autocomplete", to: "@codemirror--autocomplete.js", preload: false # @6.20.4
pin "@lezer/markdown", to: "@lezer--markdown.js", preload: false # @1.8.0
pin "@lezer/common", to: "@lezer--common.js", preload: false # @1.5.3
pin "@lezer/highlight", to: "@lezer--highlight.js", preload: false # @1.2.5
pin "@codemirror/commands", to: "@codemirror--commands.js", preload: false # @6.11.1
pin "@codemirror/language", to: "@codemirror--language.js", preload: false # @6.13.1
pin "@codemirror/streamparser", to: "@codemirror--streamparser.js", preload: false # @6.0.0

# The theme editor (app/javascript/theme_editor): CodeMirror's CSS language
# and the parser the INSPECT button reads rules with. Same preload: false.
pin_all_from "app/javascript/theme_editor", under: "theme_editor", preload: false
pin "@codemirror/lang-css", to: "@codemirror--lang-css.js", preload: false # @6.3.1
pin "@lezer/css", to: "@lezer--css.js", preload: false # @1.3.9
pin "@lezer/lr", to: "@lezer--lr.js", preload: false # @1.4.12
