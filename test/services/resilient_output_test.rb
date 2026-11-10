require "test_helper"

class ResilientOutputTest < ActiveSupport::TestCase
  # Stands in for a terminal or log file that has gone away.
  class GoneIO
    def write(*) = raise(Errno::EIO, "Input/output error")
    def puts(*) = raise(Errno::EIO, "Input/output error")
    def print(*) = raise(Errno::EIO, "Input/output error")
    def flush = raise(Errno::EPIPE)
    def tty? = false
  end

  test "writes to an output that's gone are dropped, not raised" do
    out = ResilientOutput.wrap(GoneIO.new)
    assert_nothing_raised do
      out.puts "  ✗ Unexpected error: page.md"
      out.print "x"
      out.write "x"
      out << "x"
      out.flush
    end
  end

  test "Kernel#puts through a wrapped $stdout doesn't raise" do
    original = $stdout
    $stdout = ResilientOutput.wrap(GoneIO.new)
    assert_nothing_raised { puts "  ✓ Synced: page.md" }
  ensure
    $stdout = original
  end

  test "a working output gets everything, unchanged" do
    io = StringIO.new
    out = ResilientOutput.wrap(io)
    out.puts "one"
    out.print "two"
    out << "three"
    assert_equal "one\ntwothree", io.string
    assert_equal false, out.tty?
  end

  test "other errors still raise" do
    broken = Object.new
    def broken.puts(*) = raise(ArgumentError, "a real bug")
    assert_raises(ArgumentError) { ResilientOutput.wrap(broken).puts "x" }
  end

  test "wrapping twice keeps one wrapper" do
    once = ResilientOutput.wrap(StringIO.new)
    assert_same once, ResilientOutput.wrap(once)
  end
end
