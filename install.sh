#!/usr/bin/env bash
# Roe one-line installer.
#
# Serve this at a stable URL and install Roe with a single command:
#
#   curl -fsSL https://go-roe.com/install | bash
#
# It finds the latest Roe release, downloads the installer zip, unpacks
# it, and hands you off to `./roe.sh check` to finish setup (install
# Ruby/deps + run setup). The interactive parts stay in ./roe.sh, where
# a real terminal is available — this bootstrap is the non-interactive
# "get the files onto the machine" half.
#
# Overrides (env vars):
#   ROE_REPO         Codeberg repo            (default: waotw/roe)
#   ROE_INSTALL_DIR  where to put the folder  (default: current directory)
#   ROE_INSTALL_URL  direct .zip URL          (skips release-asset lookup)
#
# No `set -e`: this script does a lot of best-effort parsing where a
# non-match is expected, so failures are handled explicitly with `die`.
set -uo pipefail

REPO="${ROE_REPO:-waotw/roe}"
# GitHub answers on a separate API host; Forgejo and Gitea answer on the forge
# itself. Overridable so a fork or a mirror needs no edit here.
API_BASE="${ROE_API_BASE:-https://api.github.com/repos/${REPO}}"
INSTALL_PARENT="${ROE_INSTALL_DIR:-$(pwd)}"

# ── Output helpers (plain when not a tty) ──────────────────────────────
if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; NC=""
fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s[✓]%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$*"; }
die()  { printf '%s[✗]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

# ── Bootstrap prerequisites ────────────────────────────────────────────
command -v curl  >/dev/null 2>&1 || die "curl is required to download Roe."
command -v unzip >/dev/null 2>&1 || die "unzip is required. Install it, then re-run."

# On Windows, Roe runs under WSL2 — which is Linux, so everything here works.
# But it has to be installed on the LINUX filesystem, not a mounted Windows
# drive: /mnt/c can't hold Unix permissions, so the `chmod +x roe.sh` below
# silently does nothing and the user is left with a script they can't run.
# (File watching also stops seeing edits made from Windows, which breaks
# content sync later — see require_linux_filesystem in roe.sh.)
if [ -r /proc/version ] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    case "$INSTALL_PARENT" in
        /mnt/*)
            die "Install Roe on the Linux side, not a Windows drive.

  You're in: $INSTALL_PARENT

  Windows drives (/mnt/...) can't store file permissions, so Roe's launcher
  won't be executable and file changes won't be detected.

  Run this instead:

      cd ~ && curl -fsSL https://go-roe.com/install | bash

  Your files stay reachable from Windows at:
      \\\\wsl\$\\${WSL_DISTRO_NAME:-Ubuntu}\\home\\$USER\\"
            ;;
    esac
fi

say "${BOLD}Installing Roe${NC}"
say ""

# ── 1. Resolve the latest release + its installer zip ──────────────────
zip_url="${ROE_INSTALL_URL:-}"
tag=""

if [ -z "$zip_url" ]; then
  say "Finding the latest release…"
  # Use the releases LIST (newest first), not /releases/latest. Parse asset
  # URLs directly, which works the same on GitHub and Forgejo: both return
  # browser_download_url, and both serve assets from
  # .../releases/download/<tag>/<asset>, so the tag parse below holds too. A
  # stable installer asset is named roe-<numeric version>.zip (e.g.
  # roe-0.0.37.zip). Pre-release builds carry a suffix
  # (roe-0.0.38-nightly.zip) and are skipped by the numeric-only match,
  # so users only ever get stable releases. Since the list is newest
  # first, head -1 is the latest stable.
  # per_page is GitHub's spelling; Forgejo calls it limit. Both default to a
  # page big enough, so the parameter is belt and braces either way.
  api_json="$(curl -fsSL "${API_BASE}/releases?per_page=20" 2>/dev/null)" \
    || die "Couldn't reach the release server to find the latest version. Check your connection, or set ROE_INSTALL_URL to a .zip URL."

  zip_url="$(printf '%s' "$api_json" \
        | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*roe-[0-9]+\.[0-9]+\.[0-9]+\.zip"' \
        | sed -E 's/.*"(https[^"]+)"$/\1/' \
        | head -1)"

  [ -n "$zip_url" ] || die "No stable installer .zip found on recent releases.
  Set ROE_INSTALL_URL to the zip's URL and re-run, e.g.:
    ROE_INSTALL_URL='https://…/roe-X.Y.Z.zip' curl -fsSL https://go-roe.com/install | bash"

  # Derive the version tag from the asset URL (.../download/vX.Y.Z/roe-…).
  tag="$(printf '%s' "$zip_url" | sed -E 's#.*/download/(v[^/]+)/.*#\1#')"
fi

[ -n "$tag" ] && ok "Latest release: ${tag}"

# ── 2. Download to a temp dir ──────────────────────────────────────────
tmp="$(mktemp -d 2>/dev/null)" || die "Couldn't create a temp directory."
trap 'rm -rf "$tmp"' EXIT

zip_name="${zip_url##*/}"
say "Downloading ${zip_name}…"
curl -fSL --progress-bar "$zip_url" -o "$tmp/roe.zip" \
  || die "Download failed: $zip_url"
unzip -tq "$tmp/roe.zip" >/dev/null 2>&1 \
  || die "The downloaded file isn't a valid zip. The release asset may be wrong."

# ── 3. Unpack and place ────────────────────────────────────────────────
say "Unpacking…"
mkdir -p "$tmp/extract"
unzip -q "$tmp/roe.zip" -d "$tmp/extract" || die "Failed to unzip."

# The installer zip's top-level folder is roe-<version>/.
pkg_dir="$(find "$tmp/extract" -maxdepth 1 -mindepth 1 -type d -name 'roe-*' 2>/dev/null | head -1)"
[ -n "$pkg_dir" ] || die "Unexpected package layout — no roe-<version>/ folder inside the zip."
[ -f "$pkg_dir/roe.sh" ] || die "Package is missing roe.sh — wrong archive?"

dest="$INSTALL_PARENT/$(basename "$pkg_dir")"
if [ -e "$dest" ]; then
  warn "A folder already exists at:"
  warn "  $dest"
  die "Move or remove it (or set ROE_INSTALL_DIR to another location), then re-run."
fi

mv "$pkg_dir" "$dest" || die "Couldn't move the package into place at $dest."
chmod +x "$dest/roe.sh" 2>/dev/null || true
[ -f "$dest/start.command" ] && chmod +x "$dest/start.command" 2>/dev/null || true

ok "Roe installed to: ${dest}"
say ""

# ── 4. Hand off to ./roe.sh check ──────────────────────────────────────
say "${BOLD}Next step:${NC} finish setup (installs Ruby + dependencies, then configures Roe):"
say "   ${CYAN}cd \"${dest}\" && ./roe.sh check${NC}"
say ""

# Under `curl | bash`, stdin is the piped script — so prompts must read
# from the controlling terminal. Probe /dev/tty by actually trying to
# open it for writing (a plain `[ -r /dev/tty ]` test passes even when
# the device exists but has no controlling terminal, e.g. CI, cron,
# headless installs — which then errors "Device not configured"). Only
# offer the auto-run when /dev/tty truly works; otherwise the printed
# command above is the path forward.
if { : > /dev/tty; } 2>/dev/null; then
  printf "Run setup now? [y/n]: " > /dev/tty 2>/dev/null
  reply=""
  read -r reply < /dev/tty 2>/dev/null || reply=""
  case "$reply" in
    [Yy]*)
      cd "$dest" || die "Couldn't enter $dest"
      exec ./roe.sh check < /dev/tty
      ;;
  esac
fi
