namespace :content do
  desc "Sync all content from markdown files"
  task sync: :environment do
    ContentSync.sync_all
  end
end
