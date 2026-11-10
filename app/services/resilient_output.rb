# Output that survives losing where it goes.
#
# Roe prints progress lines with `puts` (ContentSync, ContentWatcher,
# generators, jobs). When the terminal or log file a server writes to goes
# away — the terminal it was started from closed, or the drive the log is on
# dropped and came back — every one of those writes raises Errno::EIO, and
# the request it happens in fails. A page save broke that way.
#
# Wrapped around $stdout and $stderr (config/initializers/resilient_output.rb),
# a write whose output is gone is dropped instead. Everything else passes
# straight through, so where the output still works nothing changes.
class ResilientOutput < SimpleDelegator
  GONE = [ Errno::EIO, Errno::EPIPE, Errno::ENXIO, IOError ].freeze

  %i[write puts print printf putc flush syswrite].each do |name|
    define_method(name) do |*args, &block|
      __getobj__.public_send(name, *args, &block)
    rescue *GONE
      nil
    end
  end

  def <<(object)
    write(object)
    self
  end

  # Wrap an output once; anything already wrapped is left as it is.
  def self.wrap(io)
    io.is_a?(ResilientOutput) ? io : new(io)
  end
end
