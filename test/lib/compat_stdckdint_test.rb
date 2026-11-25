require "test_helper"
require "open3"

# lib/compat/stdckdint.h stands in for C23's <stdckdint.h> on Macs whose
# compiler hasn't got it (see the Gemfile). It has to behave like the real
# one: report overflow, and give the wrapped result.
class CompatStdckdintTest < ActiveSupport::TestCase
  test "the stand-in header reports overflow like C23's ckd_* macros" do
    skip "no C compiler" unless system("command -v cc > /dev/null 2>&1")

    Dir.mktmpdir do |dir|
      source = File.join(dir, "ckd.c")
      binary = File.join(dir, "ckd")
      File.write(source, <<~C)
        #include "stdckdint.h"
        #include <limits.h>
        #include <stdio.h>
        int main(void) {
          int r;
          int a = ckd_add(&r, INT_MAX, 1);
          int b = ckd_add(&r, 2, 3);
          printf("%d %d %d ", a, b, r);
          long m;
          printf("%d %d\\n", ckd_mul(&m, LONG_MAX, 2L), ckd_sub(&r, INT_MIN, 1));
          return 0;
        }
      C

      include_dir = Rails.root.join("lib/compat").to_s
      _out, err, status = Open3.capture3("cc", "-I", include_dir, "-o", binary, source)
      assert status.success?, "compile failed: #{err}"

      out, _err, status = Open3.capture3(binary)
      assert status.success?
      assert_equal "1 0 5 1 1", out.strip
    end
  end
end
