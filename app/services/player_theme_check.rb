# Does the active theme style Roe's player card?
#
# The card's play button and progress bar are drawn by the theme: the
# button is empty and gets its ▶ from `.player-toggle::before`. A theme
# with no player styles (written from scratch, or forked before the card
# shipped in v0.3.0) would show an invisible button once player.js takes
# over. On those themes the card is drawn as the browser's own audio
# controls instead, which work with any theme and any player.js.
#
# Read from the theme file Roe serves (site/theme/<active>.css, or Roe's
# bundled copy when the site has none) and kept until the file changes.
class PlayerThemeCheck
  MARKER = ".player-toggle".freeze

  def self.styled?
    path = theme_path
    return true unless path

    # Modified time is whole seconds on some filesystems, so the size is in
    # the key too: two saves in one second still read as a change.
    stat = File.stat(path)
    key = [ path, stat.mtime, stat.size ]
    cached = @cache
    return cached[:styled] if cached && cached[:key] == key

    styled = File.read(path).include?(MARKER)
    @cache = { key: key, styled: styled }
    styled
  rescue SystemCallError
    true
  end

  def self.theme_path
    name = SiteConfig.get("theme.active").to_s.strip.presence || "default"
    return nil unless name.match?(/\A[\w.-]+\z/)

    [ File.join(RoeSitePaths::SITE_PATH, "theme", "#{name}.css"),
      Rails.root.join("app/themes/#{name}.css").to_s ].find { |p| File.file?(p) }
  end
end
