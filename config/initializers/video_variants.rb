# When the jobs program starts — roe start, roe restart, a foreground
# ./roe.sh start, anything that runs bin/jobs — finish any video whose web
# versions stopped part-way: the jobs program was ended mid-encode and
# nothing was left to make the rest. Versions already made are skipped, so
# only the missing ones are encoded, straight away. Between starts, the
# Media Browser's OPTIMIZE VIDEOS button does the same for any video that
# needs it. See VideoVariantGenerator.resume_interrupted!.
#
# Not on the live site: it never makes web versions. The hook only ever
# runs in the jobs program's supervisor; registering it elsewhere is inert.
unless Rails.env.production?
  Rails.application.config.after_initialize do
    SolidQueue.on_start do
      Rails.application.executor.wrap do
        count = VideoVariantGenerator.resume_interrupted!
        Rails.logger.info "[VideoVariants] Resumed #{count} #{'video'.pluralize(count)} that stopped part-way" if count.positive?
      end
    rescue => e
      # Never stop the jobs program from starting over this.
      Rails.logger.warn "[VideoVariants] couldn't check for videos that stopped part-way: #{e.class} #{e.message}"
    end
  end
end
