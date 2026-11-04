# Run using bin/ci

CI.run do
  # Not Rails' stock `bin/setup --skip-server`: Roe's bin/setup is the
  # installer (keys, site, database, styles, then bin/bootstrap's admin
  # questions), and bin/bootstrap reads the terminal directly, so under
  # bin/release it waited on a question nobody could see. The checks below
  # only need the gems: the tests build their own site in tmp/test_site and
  # prepare their own database.
  step "Setup: Gems", "bundle check > /dev/null || bundle install"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
