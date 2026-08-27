# Throwaway posts and pages for exercising Site Sync by hand.
#
# Testing sync means deleting things, syncing, and putting them back — which
# is awkward with real content and tedious to recreate. These are disposable
# and regenerate in a second, so the loop is: seed, sync, delete some, sync,
# restore from history, seed again.
#
# Every file is named `sync-test-*` so it's unmistakable in a file list, a
# conflict list, and the sync history.
#
#   bin/rails content:seed_sync_test    # create them (safe to re-run)
#   bin/rails content:clear_sync_test   # remove every one
#
# Development only. These write into /site, and nobody wants them appearing
# on a real site because a task got run in the wrong place.
module SyncTestContent
  PREFIX = "sync-test".freeze

  POSTS = [
    { slug: "alpha",   title: "Sync Test — Alpha",   status: "published", audience: "everyone" },
    { slug: "beta",    title: "Sync Test — Beta",    status: "published", audience: "everyone" },
    { slug: "gamma",   title: "Sync Test — Gamma",   status: "published", audience: "paid" },
    { slug: "delta",   title: "Sync Test — Delta",   status: "draft",     audience: "everyone" },
    { slug: "epsilon", title: "Sync Test — Epsilon", status: "unlisted",  audience: "everyone" },
    { slug: "zeta",    title: "Sync Test — Zeta",    status: "published", audience: "everyone" }
  ].freeze

  PAGES = [
    { slug: "one",   title: "Sync Test Page One",   status: "published" },
    { slug: "two",   title: "Sync Test Page Two",   status: "published" },
    { slug: "three", title: "Sync Test Page Three", status: "draft" }
  ].freeze

  module_function

  def allowed? = Rails.env.development?

  def posts_dir = File.join(RoeSitePaths::SITE_PATH, "posts")
  def pages_dir = File.join(RoeSitePaths::SITE_PATH, "pages")

  def post_path(slug) = File.join(posts_dir, "#{PREFIX}-#{slug}.md")
  def page_path(slug) = File.join(pages_dir, "#{PREFIX}-#{slug}.md")

  def body(title, kind)
    <<~MD
      This is a throwaway #{kind} for testing Site Sync. Delete it, sync, and
      put it back from Sync History — nothing here matters.

      Its name starts with `#{PREFIX}-` so it's easy to spot in a diff, a
      conflict list, or the sync history.

      ## #{title}

      Some body text so the file has a size worth diffing, and a second
      paragraph so an edit on one side is easy to make and easy to see.
    MD
  end

  def write_post(entry)
    front = {
      "title" => entry[:title],
      # Pinned so the URL matches the filename. Derived from the title it
      # wouldn't, and "which file is /sync-test-page-one?" is the wrong
      # question to be asking while testing deletions.
      "url_name" => "#{SyncTestContent::PREFIX}-#{entry[:slug]}",
      "date" => Time.current.strftime("%Y-%m-%dT%H:%M"),
      "status" => entry[:status],
      "post_type" => "article",
      "tags" => [],
      "audience" => entry[:audience]
    }
    File.write(post_path(entry[:slug]), yaml_front(front) + body(entry[:title], "post"))
  end

  def write_page(entry)
    front = {
      "title" => entry[:title],
      "url_name" => "#{SyncTestContent::PREFIX}-#{entry[:slug]}",
      "status" => entry[:status],
      "tags" => [],
      "audience" => "everyone"
    }
    File.write(page_path(entry[:slug]), yaml_front(front) + body(entry[:title], "page"))
  end

  # Matches how Roe's own files are written: quoted scalars, no leading ---.
  def yaml_front(hash)
    lines = hash.map do |k, v|
      v.is_a?(Array) ? "#{k}: []" : %(#{k}: "#{v}")
    end
    "---\n#{lines.join("\n")}\n---\n\n"
  end
end

namespace :content do
  desc "Create throwaway posts and pages for testing Site Sync (development only)"
  task seed_sync_test: :environment do
    abort "Development only — refusing to run in #{Rails.env}." unless SyncTestContent.allowed?

    FileUtils.mkdir_p(SyncTestContent.posts_dir)
    FileUtils.mkdir_p(SyncTestContent.pages_dir)

    SyncTestContent::POSTS.each { |e| SyncTestContent.write_post(e) }
    SyncTestContent::PAGES.each { |e| SyncTestContent.write_page(e) }

    ContentSync.sync_all

    puts "\nCreated #{SyncTestContent::POSTS.size} posts and #{SyncTestContent::PAGES.size} pages:\n\n"
    SyncTestContent::POSTS.each { |e| puts "  posts/#{SyncTestContent::PREFIX}-#{e[:slug]}.md  (#{e[:status]}, #{e[:audience]})" }
    SyncTestContent::PAGES.each { |e| puts "  pages/#{SyncTestContent::PREFIX}-#{e[:slug]}.md  (#{e[:status]})" }
    puts "\n  Remove them all: bin/rails content:clear_sync_test\n\n"
  end

  desc "Remove the throwaway content created by content:seed_sync_test"
  task clear_sync_test: :environment do
    abort "Development only — refusing to run in #{Rails.env}." unless SyncTestContent.allowed?

    removed = []
    [ SyncTestContent.posts_dir, SyncTestContent.pages_dir ].each do |dir|
      Dir.glob(File.join(dir, "#{SyncTestContent::PREFIX}-*.md")).each do |path|
        removed << path.sub("#{RoeSitePaths::SITE_PATH}/", "")
        File.delete(path)
      end
    end

    if removed.empty?
      puts "Nothing to remove."
    else
      ContentSync.sync_all
      puts "Removed #{removed.size} file(s):"
      removed.sort.each { |r| puts "  #{r}" }
    end
  end
end
