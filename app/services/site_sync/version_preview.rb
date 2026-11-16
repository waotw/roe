# frozen_string_literal: true

module SiteSync
  # Reading stored versions for Sync History: where a version's contents are,
  # whether they can be shown as text, and a line diff between two of them.
  module VersionPreview
    TEXT_MAX  = 1024 * 1024
    IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .avif].freeze
    # How much working memory a diff may use, in remembered positions. Two
    # versions this far apart aren't worth reading as a diff; the page shows
    # the file instead.
    DIFF_WORK_MAX = 20_000_000
    CONTEXT = 3

    Line = Struct.new(:kind, :text, :old_no, :new_no, keyword_init: true) # kind: :same, :removed, :added, :gap

    module_function

    # The file holding version `sha` of `path`: the stored copy, or the file
    # on disk when it's still that version (large versions are only
    # fingerprinted when a sync leaves them). nil when neither is there.
    def source(sha, path)
      return nil if sha.blank?
      return Versions.object_path(sha) if Versions.object?(sha)

      abs = File.join(RoeSitePaths::SITE_PATH, path.to_s)
      VersionRestore.matches?(path, sha) ? abs : nil
    rescue ArgumentError
      nil
    end

    def image?(path) = IMAGE_EXTENSIONS.include?(File.extname(path.to_s).downcase)

    # Text Roe can show: small enough, no NUL bytes, valid UTF-8.
    def text_of(abs)
      return nil if abs.nil? || File.size(abs) > TEXT_MAX

      body = File.binread(abs)
      return nil if body.byteslice(0, 8000).include?("\0")

      body.force_encoding(Encoding::UTF_8)
      body.valid_encoding? ? body : nil
    end

    # Lines of `a` → `b` as Line structs, unchanged runs trimmed to CONTEXT
    # lines around each change, with :gap where lines are left out. nil when
    # the two are too far apart to diff quickly.
    def diff(a, b)
      old_lines = a.to_s.lines.map(&:chomp)
      new_lines = b.to_s.lines.map(&:chomp)
      ops = line_ops(old_lines, new_lines)
      return nil if ops.nil?

      trim(ops)
    end

    def line_ops(old_lines, new_lines)
      head = 0
      head += 1 while head < old_lines.size && head < new_lines.size && old_lines[head] == new_lines[head]
      tail = 0
      tail += 1 while tail < old_lines.size - head && tail < new_lines.size - head &&
                      old_lines[-1 - tail] == new_lines[-1 - tail]

      a = old_lines[head...(old_lines.size - tail)]
      b = new_lines[head...(new_lines.size - tail)]
      middle = myers(a, b)
      return nil if middle.nil?

      ops = old_lines[0, head].map { |t| [ :same, t ] } + middle
      ops + old_lines.last(tail).map { |t| [ :same, t ] }
    end

    # Myers' diff: the shortest list of removed and added lines that turns
    # `a` into `b`. Fast when the two are close, which a sync's change
    # usually is, however long the file. nil past DIFF_WORK_MAX.
    def myers(a, b)
      n, m = a.size, b.size
      max = n + m
      return [] if max.zero?

      offset = max + 1
      width = 2 * max + 3
      max_d = [ max, DIFF_WORK_MAX / width ].min
      v = Array.new(width, 0)
      trace = []
      found = nil
      (0..max_d).each do |d|
        trace << v.dup
        (-d..d).step(2) do |k|
          x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) ? v[offset + k + 1] : v[offset + k - 1] + 1
          y = x - k
          while x < n && y < m && a[x] == b[y]
            x += 1
            y += 1
          end
          v[offset + k] = x
          if x >= n && y >= m
            found = d
            break
          end
        end
        break if found
      end
      return nil if found.nil?

      x, y = n, m
      ops = []
      found.downto(0) do |d|
        v = trace[d]
        k = x - y
        prev_k = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) ? k + 1 : k - 1
        prev_x = v[offset + prev_k]
        prev_y = prev_x - prev_k
        while x > prev_x && y > prev_y
          ops << [ :same, a[x - 1] ]
          x -= 1
          y -= 1
        end
        next if d.zero?

        if x == prev_x
          ops << [ :added, b[y - 1] ]
          y -= 1
        else
          ops << [ :removed, a[x - 1] ]
          x -= 1
        end
      end
      ops.reverse
    end

    def trim(ops)
      old_no = new_no = 0
      numbered = ops.map do |kind, text|
        old_no += 1 unless kind == :added
        new_no += 1 unless kind == :removed
        Line.new(kind: kind, text: text, old_no: (kind == :added ? nil : old_no), new_no: (kind == :removed ? nil : new_no))
      end

      changed = numbered.each_index.reject { |i| numbered[i].kind == :same }
      return [] if changed.empty?

      keep = changed.flat_map { |i| ((i - CONTEXT)..(i + CONTEXT)).to_a }.select { |i| i.between?(0, numbered.size - 1) }.to_set
      out = []
      numbered.each_with_index do |line, i|
        if keep.include?(i)
          out << line
        elsif out.last&.kind != :gap
          out << Line.new(kind: :gap)
        end
      end
      out
    end
  end
end
