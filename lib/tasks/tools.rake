# The Rails side of `roe install <tool>`. The CLI (bin/roe) does the talking
# and the confirming; these tasks answer its questions from ManagedTools so
# the knowledge of each tool lives in one place, and print plain
# tab-separated lines that bash can read. Empty fields are printed as "-":
# bash's `read` treats a run of tabs as one separator, so a truly empty
# field would shift every field after it.
namespace :roe do
  namespace :tools do
    find_tool = lambda do |key|
      ManagedTools.find(key.to_s) or abort "Roe doesn't manage a tool called '#{key}'."
    end
    field = ->(value) { value.to_s.tr("\t\n", "  ").strip.presence || "-" }
    yes_no = ->(value) { value ? "yes" : "no" }

    # tool   <TAB> key <TAB> label <TAB> installed <TAB> version <TAB> system
    # method <TAB> key <TAB> label <TAB> usable <TAB> command <TAB> sudo
    #        <TAB> restart <TAB> reason <TAB> detail          (best first)
    desc "List the ways to install a managed tool on this computer (for roe install)"
    task :methods, [ :tool ] => :environment do |_t, args|
      tool = find_tool.(args[:tool])
      platform = ManagedTools::Platform.current
      installed = tool.installed?

      puts [ "tool", tool.key, tool.label, yes_no.(installed), (installed ? tool.version : nil), platform.system_label ]
        .map(&field).join("\t")
      tool.install_methods(platform).each do |m|
        puts [ "method", m.key, m.label, yes_no.(m.usable?), m.command, yes_no.(m.sudo), yes_no.(m.restart), m.reason, m.detail ]
          .map(&field).join("\t")
      end
    end

    # Prints the folder the programs went into. Progress goes to stderr, and
    # only to a terminal.
    desc "Download, check and unpack a managed tool into ~/.roe/tools (for roe install)"
    task :download, [ :tool ] => :environment do |_t, args|
      tool = find_tool.(args[:tool])
      abort "#{tool.label} can't be installed by download." unless tool.respond_to?(:downloader)

      last = nil
      progress = lambda do |name, done, total|
        next unless $stderr.tty?

        line = total&.positive? ? "  #{name}  #{done * 100 / total}% of #{(total / 1_048_576.0).round} MB" : "  #{name}  #{(done / 1_048_576.0).round} MB"
        next if line == last

        last = line
        $stderr.print "\r#{line}\e[K"
      end

      downloader = tool.downloader(progress: progress)
      begin
        dir = downloader.install!(ManagedTools::Platform.current)
        $stderr.print("\r\e[K") if $stderr.tty?
        downloader.remove_other_versions!
        puts dir
      rescue ManagedTools::Downloader::Error => e
        $stderr.print("\r\e[K") if $stderr.tty?
        abort e.message
      rescue SystemCallError, Zip::Error, IOError => e
        $stderr.print("\r\e[K") if $stderr.tty?
        abort "Couldn't install #{tool.label}: #{e.message}"
      end
    end

    # installed <TAB> version <TAB> note — asked after an install to check it
    # really worked, rather than trusting the command's exit status.
    desc "Report whether a managed tool is installed and working (for roe install)"
    task :check, [ :tool ] => :environment do |_t, args|
      tool = find_tool.(args[:tool])
      ManagedTools::Platform.bottle_cache.clear
      installed = tool.installed?
      puts [ yes_no.(installed), (installed ? tool.version : nil), (installed ? nil : tool.note) ].map(&field).join("\t")
    end
  end
end
