# A server or job runner that has lost its terminal or log file keeps
# working instead of failing on the next `puts` (see ResilientOutput).
# Left alone in tests, which capture output, and in `rails console`, where
# the terminal is the point.
Rails.application.config.after_initialize do
  next if Rails.env.test? || defined?(Rails::Console)

  $stdout = ResilientOutput.wrap($stdout)
  $stderr = ResilientOutput.wrap($stderr)
end
