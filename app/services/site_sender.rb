# frozen_string_literal: true

# Who Roe's email comes from, and whether it can be sent at all.
#
# Every outgoing email — member sign-in links, newsletters, account notices —
# uses the site's own address. There is no Roe-owned address to fall back on,
# and there can't be: Postmark rejects any From that isn't a verified Sender
# Signature, so a stand-in like noreply@example.com doesn't rescue a send. It
# just turns "you haven't set your email address" into an opaque rejection
# about a domain nobody owns.
#
# So a missing address is a refusal, not a substitution. Nothing crashes; the
# caller gets a clear reason, and the Members and Postmark settings pages warn
# before anyone tries.
#
# Lived in four places reading the same key two different ways — two with
# `.presence` and two with a bare `||`, which is why an EMPTY author_email
# produced `From: " <>"` while a MISSING one worked.
class SiteSender
  MISSING = "This site has no author email set, so Roe can't send email. " \
            "Add an Author Email in Settings → Site.".freeze

  class << self
    # The address, or nil when the site hasn't set one.
    def address = site_value("author_email")

    # Display name for the From header, or nil. The site's title stands in for
    # a missing author name; nothing stands in after that, because from_header
    # drops the name entirely rather than repeating the address as its label.
    def name
      site_value("author") || site_value("title")
    end

    def configured? = address.present?

    # "Name <address>", or nil when there's nothing to send from.
    def from_header
      return nil unless configured?

      name.present? ? "#{name} <#{address}>" : address
    end

    private

    # SiteConfig.get is the single read path for site-level settings: it reads
    # site.yml, which is the source of truth, and works when the database
    # doesn't (the cached-record path goes through Solid Cache, which is
    # database-backed).
    #
    # .presence is the fix this class exists for: the old code used a bare ||,
    # so an author_email that existed but was EMPTY skipped the fallback and
    # produced From: " <>", while a missing one worked.
    def site_value(key)
      SiteConfig.get(key).presence
    end
  end
end
