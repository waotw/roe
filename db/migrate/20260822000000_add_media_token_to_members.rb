class AddMediaTokenToMembers < ActiveRecord::Migration[8.1]
  # A per-member credential for reading protected media and private feeds.
  #
  # This exists because `access_token` is the magic-link SIGN-IN token —
  # Members::SessionsController#signin_with_token looks a member up by it and
  # sets session[:member_id]. Putting that in a URL means every protected image
  # and audio tag on a page carries a working credential for the account, and
  # those URLs leak through browser history, Referer headers, shared links and
  # podcast-app logs.
  #
  # media_token grants read access to files and feeds and nothing else. It's
  # verified against the database on every request rather than being a signed,
  # self-contained token, so cancelling or downgrading revokes access on the
  # next request instead of whenever a signature would have expired.
  def change
    add_column :members, :media_token, :string, limit: 36
    add_index :members, :media_token, unique: true

    # Backfill so existing members keep working. Members#ensure_media_token
    # covers anything created between this running and the deploy.
    reversible do |dir|
      dir.up do
        say_with_time "backfilling media_token" do
          execute <<~SQL
            UPDATE members
            SET media_token = lower(hex(randomblob(16)))
            WHERE media_token IS NULL
          SQL
        end
      end
    end
  end
end
