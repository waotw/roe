# Downloads the selected external media types into the local library and
# rewrites every reference. Runs in the background (large audio/video would
# time out a request); writes progress to the cache for the Media Import page
# to poll.
class MediaImportJob < ApplicationJob
  queue_as :default

  STATUS_KEY = "media_import:status"
  STATUS_TTL = 1.hour

  def self.status
    Rails.cache.read(STATUS_KEY)
  end

  def self.write_status(attrs)
    Rails.cache.write(STATUS_KEY, attrs, expires_in: STATUS_TTL)
  end

  def self.clear_status
    Rails.cache.delete(STATUS_KEY)
  end

  # types: array of "images"/"audio"/"video".
  def perform(types)
    types = Array(types).map(&:to_sym)
    progress(step: "scanning", total: 0, downloaded: 0, failed: 0, rewritten: 0)

    refs = MediaImporter::Scanner.scan.select { |ref| types.include?(ref.type) }
    urls = refs.map { |ref| [ ref.url, ref.type ] }.uniq
    progress(step: "downloading", total: urls.size, downloaded: 0, failed: 0, rewritten: 0)

    fetcher = MediaImporter::Fetcher.new
    url_map = {}
    failed = 0
    urls.each do |url, type|
      local = fetcher.fetch(url, type)
      local ? url_map[url] = local : failed += 1
      progress(step: "downloading", total: urls.size, downloaded: url_map.size, failed: failed, rewritten: 0)
    end

    records = refs.map(&:record).uniq
    rewritten = 0
    records.each_with_index do |record, i|
      rewritten += 1 if MediaImporter.rewrite_file(record, url_map)
      progress(step: "rewriting", total: urls.size, downloaded: url_map.size, failed: failed,
               rewritten: rewritten, records_total: records.size, records_done: i + 1)
    end

    self.class.write_status(state: "done", step: "done", total: urls.size,
                            downloaded: url_map.size, failed: failed, rewritten: rewritten)
  rescue => e
    self.class.write_status(state: "failed", step: "failed", error: e.message)
    raise
  end

  private

  def progress(attrs)
    self.class.write_status({ state: "running" }.merge(attrs))
  end
end
