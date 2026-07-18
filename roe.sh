#!/bin/bash
# Roe Launcher Script
# Manages the Roe server, setup, and updates.
# Run from the /roe root directory: ./roe.sh {command}

# Detect directory structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_DIR="$(basename "$SCRIPT_DIR")"

if [ "$CURRENT_DIR" = "current" ]; then
    ROE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    APP_DIR="$SCRIPT_DIR"
    SITE_DIR="$ROE_ROOT/site"
elif [ -d "$SCRIPT_DIR/current" ]; then
    ROE_ROOT="$SCRIPT_DIR"
    APP_DIR="$ROE_ROOT/current"
    SITE_DIR="$ROE_ROOT/site"
else
    ROE_ROOT="$SCRIPT_DIR"
    APP_DIR="$SCRIPT_DIR"
    SITE_DIR="$ROE_ROOT/site"
fi

# Put APP_DIR's pinned Ruby (current/.ruby-version) on PATH for THIS
# script process and every child it spawns — chdir-proof and, crucially,
# non-interactive-safe.
#
# We deliberately do NOT use `eval "$(mise activate bash)"` for this. That
# installs a shell *prompt hook* to resolve the version, and the hook
# never fires in a non-interactive script — so it pins whatever Ruby
# matches the script's current directory. When roe.sh is run from the
# /roe root (the normal case), that directory has no .ruby-version, so
# mise falls back to the GLOBAL Ruby instead of current/.ruby-version.
# bin/setup would then run `bundle install` under the wrong Ruby and
# install every gem into the wrong gemset — invisible to the Ruby the app
# actually boots with. `mise env -C "$APP_DIR"` resolves explicitly for
# the app directory regardless of CWD, which is exactly what we need.
# (The `mise activate` we write into the user's *interactive* rc is fine
# as-is — the prompt hook works there.)
mise_pin_app_ruby() {
    command -v mise >/dev/null 2>&1 || return 0
    eval "$(mise env -C "$APP_DIR" 2>/dev/null)" 2>/dev/null || true
}

# Put Homebrew on PATH for this script process if it's installed at a
# standard location but the user's shell hasn't yet picked it up. This
# makes ./roe.sh self-sufficient on the second invocation after a fresh
# Homebrew install — the user shouldn't have to open a new terminal tab
# just so the script can see `brew` again.
if ! command -v brew >/dev/null 2>&1; then
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# Put mise on PATH for this script process if it's installed but the
# user's shell hasn't picked it up yet (same self-sufficiency trick as
# Homebrew above — second invocation after a fresh mise install should
# Just Work without opening a new terminal). mise's standalone
# installer drops the binary at ~/.local/bin/mise by default.
if ! command -v mise >/dev/null 2>&1; then
    for _mise_candidate in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
        if [ -x "$_mise_candidate" ]; then
            export PATH="$(dirname "$_mise_candidate"):$PATH"
            break
        fi
    done
fi

# Activate the correct Ruby version from APP_DIR/.ruby-version.
# Preference order: mise → rbenv → rvm. mise is the modern default
# (single binary, precompiled rubies, cross-platform); rbenv/rvm stay
# as fallbacks so installs that already use them aren't disrupted.
# Works whether the script is run from /roe or /roe/current.
if [ -f "$APP_DIR/.ruby-version" ]; then
    REQUIRED_RUBY=$(cat "$APP_DIR/.ruby-version")
    if command -v mise >/dev/null 2>&1; then
        # Pin ruby/bundle/gem/rails to current/.ruby-version for this
        # script process (and its children) — see mise_pin_app_ruby's note
        # for why this isn't `mise activate`.
        mise_pin_app_ruby
    elif command -v rbenv >/dev/null 2>&1; then
        export PATH="$(rbenv root)/versions/$REQUIRED_RUBY/bin:$PATH"
    elif command -v rvm >/dev/null 2>&1; then
        # shellcheck disable=SC1090
        source "$(rvm env "$REQUIRED_RUBY" --path 2>/dev/null)" 2>/dev/null || true
    fi
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Install logging ───────────────────────────────────────────────────────────
# check/setup tee their progress to a temp log so a failed run leaves a
# paste-able trace for support. On a CLEAN finish the log is deleted
# (surgical: only ever `rm -f "$ROE_LOG"`, the exact mktemp path we
# captured — never a glob). On failure it's kept and its path printed.
# Only check/setup set ROE_LOG; every other command leaves it empty, so
# the EXIT trap is a no-op for start/stop/status/etc.
ROE_LOG=""
ROE_OK=0

_logfile_append() {
    [ -n "$ROE_LOG" ] || return 0
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$ROE_LOG" 2>/dev/null || true
}

start_install_log() {
    # Reuse an already-open log when nested (cmd_check → cmd_setup) so
    # we don't orphan the first log file. Only the outermost caller
    # creates one; the innermost success marks it OK.
    [ -n "$ROE_LOG" ] && { _logfile_append "=== roe.sh $* ==="; return 0; }
    # Full template path (not `mktemp -t`): GNU and BSD/macOS both
    # substitute the X's when given a complete template, producing a
    # clean name like roe-install.aB3xY9. `mktemp -t prefix` instead
    # leaves a literal "XXXXXX" in the name on macOS.
    ROE_LOG="$(mktemp "${TMPDIR:-/tmp}/roe-install.XXXXXX" 2>/dev/null)" || ROE_LOG=""
    ROE_OK=0
    [ -n "$ROE_LOG" ] && _logfile_append "=== roe.sh $* started ==="
}

# Mark the run successful — the EXIT trap will then delete the log.
mark_install_ok() { ROE_OK=1; }

_on_exit() {
    [ -n "$ROE_LOG" ] || return 0
    if [ "$ROE_OK" = "1" ]; then
        rm -f "$ROE_LOG"
    else
        echo "" >&2
        echo -e "${YELLOW}A log of this run was kept for troubleshooting:${NC}" >&2
        echo "  $ROE_LOG" >&2
    fi
}
trap _on_exit EXIT

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; _logfile_append "[INFO] $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; _logfile_append "[OK]   $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; _logfile_append "[WARN] $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; _logfile_append "[FAIL] $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}▶${NC} ${BOLD}$1${NC}"; _logfile_append "== $1 =="; }

# Give a `read` prompt breathing room below it: print a few blank lines
# (terminal scrolls up), then move the cursor back up onto the prompt
# row. Leaves empty space beneath the cursor so prompts never sit flush
# against the window's bottom edge. Mirrors bin/bootstrap's helper. Only
# emits cursor control when stdout is a terminal.
breathing_room() {
    [ -t 1 ] || return 0
    local lines="${1:-5}" i
    for ((i = 0; i < lines; i++)); do printf '\n'; done
    printf '\033[%sA' "$lines"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Detect OS
OS="unknown"
case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
esac

is_macos() { [ "$OS" = "macos" ]; }
is_linux() { [ "$OS" = "linux" ]; }

# Check if Homebrew is available (macOS only)
check_brew() { command_exists brew; }

# Are Apple's Command Line Tools actually installed and usable?
#
# We can't trust `command -v git` or even `xcode-select -p` alone: a
# fresh macOS ships *stub* binaries (/usr/bin/git, /usr/bin/clang) that
# do nothing but pop the CLT installer the first time they're run, and
# `xcode-select -p` can print a path before the tools finish installing.
# The reliable signal is the real compiler binary existing inside the
# selected developer dir — so we resolve that dir and check for clang.
clt_installed() {
    is_macos || return 0
    local dir
    dir="$(xcode-select -p 2>/dev/null)" || return 1
    [ -n "$dir" ] && [ -x "$dir/usr/bin/clang" ]
}

# macOS only: make sure the Command Line Tools (the clang/make toolchain)
# are installed *before* anything that needs to compile from source —
# chiefly mise/ruby-build, which builds Ruby and OpenSSL from source.
#
# Without this, macOS auto-triggers the CLT installer the moment the
# compiler is first invoked, but that installer runs asynchronously in a
# GUI window — so the Ruby build races ahead with no compiler present and
# dies with a cryptic OpenSSL `make` error. We trigger the installer
# ourselves, explain what's happening, and then WAIT for it to finish.
ensure_macos_build_tools() {
    is_macos || return 0
    clt_installed && return 0

    # A short guide for anyone who hits trouble with the CLT install.
    local clt_help_url="https://www.mikegopsill.com/posts/install-xcode-command-line-tools/"

    echo ""
    echo -e "  ${BOLD}Roe needs Apple's Command Line Tools for Xcode in order to run.${NC}"
    echo -e "  This is very common when installing open-source software. macOS will"
    echo -e "  take care of this for you in a separate window — when it's finished,"
    echo -e "  come back here to continue."
    echo -e "  ${DIM}This will take around ~5–10 min depending on your download speed…${NC}"
    echo ""
    breathing_room
    read -rp "  [y] install Command Line Tools   [q] quit Roe installation: " REPLY
    case "${REPLY:-y}" in
        [Qq]*)
            echo -e "  No problem — run ${CYAN}./roe.sh check${NC} whenever you're ready."
            exit 0
            ;;
    esac
    echo ""

    # Kick off Apple's installer. This opens a GUI dialog and returns
    # immediately; the actual download/install happens in the background.
    # If the tools are already mid-install (or queued), this is a no-op.
    xcode-select --install 2>/dev/null || true

    log_info "macOS is installing the Command Line Tools in a separate window — this can take several minutes."

    # Wait for completion. We poll for the real compiler, but also pause
    # on a [c] prompt so the user tells us when Apple's installer says
    # it's done — then we re-check before trusting it.
    while ! clt_installed; do
        echo ""
        breathing_room
        read -rp "  When the Command Line Tools have finished installing, press [c] to continue (or [q] to quit): " REPLY
        case "${REPLY:-}" in
            [Qq]*)
                echo -e "  No problem — run ${CYAN}./roe.sh check${NC} whenever you're ready."
                exit 0
                ;;
        esac
        # A fresh CLT install can land tools that only the user's shell rc
        # puts on PATH — source their profile so the new compiler is
        # actually visible to this process before we re-check.
        source_profile
        if ! clt_installed; then
            log_warning "The Command Line Tools don't look ready yet. Let the macOS installer finish, then press [c]."
            echo -e "  ${DIM}Having trouble? This guide walks through it step by step:${NC}"
            echo -e "  ${CYAN}${clt_help_url}${NC}"
        fi
    done

    echo ""
    log_success "Command Line Tools are installed."
}

# Are a C compiler and `make` available? Roe's native gem extensions
# (bcrypt and friends) compile during `bundle install`, which needs both.
check_build_tools() {
    command_exists make && { command_exists gcc || command_exists cc; }
}

# Build the right "install build tools" command for the user's Linux
# distro by sniffing its package manager. Echoes nothing when none is
# recognised (the caller falls back to generic guidance).
linux_build_tools_cmd() {
    if command_exists apt-get; then
        echo "sudo apt-get update && sudo apt-get install -y build-essential"
    elif command_exists dnf; then
        echo "sudo dnf install -y gcc gcc-c++ make"
    elif command_exists yum; then
        echo "sudo yum install -y gcc gcc-c++ make"
    elif command_exists pacman; then
        echo "sudo pacman -S --needed --noconfirm base-devel"
    elif command_exists zypper; then
        echo "sudo zypper install -y gcc gcc-c++ make"
    elif command_exists apk; then
        # Alpine/musl has no precompiled Ruby either, so pull the headers
        # ruby-build needs (OpenSSL + libyaml) alongside the compiler.
        echo "sudo apk add build-base openssl-dev yaml-dev"
    fi
}

# Linux only: make sure a compiler + make are present before bundle
# install compiles native gem extensions. Linux system packages need
# sudo, so — unlike the macOS Command Line Tools step — we can't run the
# install ourselves. Instead we show the right command for the distro and
# wait, re-checking until it's there. Same copy/paste/continue shape, tone
# and colours as the macOS path.
ensure_linux_build_tools() {
    is_linux || return 0
    check_build_tools && return 0

    local cmd
    cmd="$(linux_build_tools_cmd)"

    echo ""
    echo -e "  ${BOLD}Roe needs a C compiler and make to finish installing.${NC}"
    echo -e "  A few of Roe's libraries build small native components the first"
    echo -e "  time they're installed. Your Linux distribution provides these in a"
    echo -e "  single package — install it, then come back here to continue."
    echo ""

    if [ -n "$cmd" ]; then
        echo -e "  1. Copy this command:"
        echo -e "     ${CYAN}${cmd}${NC}"
        echo -e "  2. Run it in another terminal (it'll ask for your password — ${BOLD}sudo${NC})"
        echo -e "  3. Come back here and press [c] to continue"
    else
        log_warning "Couldn't identify your package manager automatically."
        echo -e "  Install your distro's build tools — a C compiler and make"
        echo -e "  (often packaged as ${CYAN}build-essential${NC}, ${CYAN}base-devel${NC}, or ${CYAN}\"Development Tools\"${NC})."
    fi
    echo ""

    while ! check_build_tools; do
        breathing_room
        read -rp "  When the build tools are installed, press [c] to continue (or [q] to quit): " REPLY
        case "${REPLY:-}" in
            [Qq]*)
                echo -e "  No problem — run ${CYAN}./roe.sh check${NC} whenever you're ready."
                exit 0
                ;;
        esac
        # A fresh package install can land binaries the user's rc puts on
        # PATH — re-source so the compiler is visible before we re-check.
        source_profile
        if ! check_build_tools; then
            log_warning "A C compiler + make still aren't detected. Let the install finish, then press [c]."
        fi
    done

    echo ""
    log_success "Build tools are installed."
}

wait_for_enter() {
    echo
    breathing_room
    read -rp "Press Enter when ready to continue..."
    echo
}

# Source the user's shell profile so newly installed tools are found
# without opening a new shell. We're running under bash here, but the
# user's interactive shell may be zsh — so we source the rc files that
# match $SHELL, then fall back to directly putting brew and rbenv onto
# PATH for the cases where bash can't fully evaluate a zsh rc (the
# Homebrew shellenv line in ~/.zprofile is the one that bit us).
source_profile() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"

    case "$shell_name" in
        zsh)
            # ~/.zprofile is where Homebrew writes its shellenv (login
            # shell rc); ~/.zshrc is where rbenv init lands (interactive
            # shell rc). Source both so we pick up whichever the just-
            # finished step touched.
            # shellcheck disable=SC1091
            [ -f "$HOME/.zprofile" ] && source "$HOME/.zprofile" 2>/dev/null || true
            # shellcheck disable=SC1091
            [ -f "$HOME/.zshrc" ]    && source "$HOME/.zshrc"    2>/dev/null || true
            ;;
        bash)
            # shellcheck disable=SC1091
            [ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile" 2>/dev/null || true
            # shellcheck disable=SC1091
            [ -f "$HOME/.bashrc" ]       && source "$HOME/.bashrc"       2>/dev/null || true
            ;;
        *)
            # shellcheck disable=SC1091
            [ -f "$HOME/.profile" ] && source "$HOME/.profile" 2>/dev/null || true
            ;;
    esac

    # Belt-and-suspenders: bash can't perfectly evaluate a zsh rc, so
    # the brew shellenv line in ~/.zprofile may not have taken effect
    # in this process. Add brew to PATH directly if it's at one of the
    # standard install locations. This is what makes the "I just
    # installed Homebrew, press [c] to continue" flow actually detect
    # brew on the next step.
    if ! command -v brew >/dev/null 2>&1; then
        if [ -x /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi

    # Re-init rbenv against THIS bash process (not the user's shell) so
    # newly installed rubies are visible without opening a new terminal.
    if command -v rbenv >/dev/null 2>&1; then
        eval "$(rbenv init - bash)" 2>/dev/null || true
    fi
}

# Show a command to copy, then wait for the user to run it in another terminal.
# After the user returns, sources their shell profile so new tools are visible.
# Usage: install_prompt "description" "command to copy" ["extra note"]
# Returns 0 if user continues, 1 if user quits.
install_prompt() {
    local description="$1"
    local cmd="$2"
    local note="${3:-}"

    echo ""
    echo -e "  ${BOLD}To install ${description}:${NC}"
    [ -n "$note" ] && echo -e "  ${YELLOW}Note:${NC} ${note}"
    echo ""
    echo -e "  1. Copy this command:"
    echo -e "     ${CYAN}${cmd}${NC}"
    echo ""
    echo -e "  2. Open a new terminal window - cmd-t"
    echo -e "  3. Paste and press Enter — wait for it to finish"
    echo -e "  4. Return here and press [c] to continue"
    echo ""
    breathing_room
    read -rp "  When done: [c] continue   [q] quit Roe setup: " REPLY
    echo ""
    if [[ $REPLY =~ ^[Qq]$ ]]; then
        echo "Exiting setup. Run ./roe.sh check when ready."
        exit 0
    fi
    # Source profile so the newly installed tool is visible in this shell
    source_profile
    return 0
}

# After install_prompt completes, the just-installed tool may still not
# be detectable in this process — common causes are PATH changes that
# haven't propagated, the install still running in the other terminal,
# or rbenv shims that need rehashing. Rather than exiting on the first
# miss (which forced the user to re-run roe.sh from the top), loop with
# retry / re-install / quit options so they stay in the flow.
#
# Args:
#   $1 — check function (name), e.g. "check_ruby". Must return 0 when
#        the tool is found.
#   $2 — human description used in messages, e.g. "Ruby 3.4.1"
#   $3 — install command, re-shown if the user picks [i]
#   $4 — optional note for the install prompt
#
# Returns when the check passes. Exits 0 if the user picks [q].
ensure_installed() {
    local check_fn="$1"
    local description="$2"
    local cmd="$3"
    local note="${4:-}"

    while ! "$check_fn"; do
        echo ""
        log_warning "${description} not detected on PATH yet"
        echo "  Common causes:"
        echo "    • The install in the other terminal hasn't finished"
        echo "    • PATH changes from the install haven't reached this terminal"
        echo "    • Newly compiled rbenv shims need a rehash"
        echo ""
        echo "  Choose:"
        echo "    [r] re-source shell + check again  (default — try this first)"
        echo "    [i] show the install command again"
        echo "    [q] quit setup — re-run ./roe.sh check later"
        echo ""
        breathing_room
        read -rp "  Choice [R/i/q]: " REPLY
        echo ""
        case "${REPLY:-r}" in
            [Ii]*)
                install_prompt "$description" "$cmd" "$note"
                ;;
            [Qq]*)
                echo "Exiting. Run ./roe.sh check when ready."
                exit 0
                ;;
            *)
                log_info "Re-sourcing shell profile and rehashing rbenv..."
                source_profile
                # rbenv may have just installed a new Ruby; rehash so
                # the new shims are visible without a fresh terminal.
                command -v rbenv >/dev/null 2>&1 && rbenv rehash 2>/dev/null || true
                ;;
        esac
    done
}

# Detect the user's login shell from $SHELL, pick the right rc file, and
# append the rbenv init line directly. Returns 0 on success / already-
# present, 1 on unsupported shells (caller can fall back to a manual
# install_prompt). Writing the line ourselves avoids the smart-quote
# trap that bites users when they copy `eval "$(rbenv init -)"` out of
# rendered markdown — the rc file gets straight ASCII quotes guaranteed.
ensure_rbenv_in_shell() {
    local shell_name rc_file
    shell_name="$(basename "$SHELL")"
    case "$shell_name" in
        zsh)  rc_file="$HOME/.zshrc" ;;
        bash) rc_file="$HOME/.bash_profile" ;;
        *)
            log_warning "Unsupported shell: $shell_name — can't auto-configure"
            return 1
            ;;
    esac

    # Idempotent: if any of the typical rc files already has the line,
    # skip cleanly. The Step 2 caller's grep does the same up-front
    # check; this is a defence-in-depth so the standalone setup-rbenv
    # command stays safe to run repeatedly.
    if grep -q 'rbenv init' "$rc_file" 2>/dev/null; then
        log_info "rbenv init already in $rc_file"
        return 0
    fi

    # Single-quote the literal portion and break out only to interpolate
    # $shell_name. The line that lands in the rc file is exactly:
    #   eval "$(rbenv init - <shell>)"
    # with straight ASCII quotes regardless of how this script reached
    # the user's machine.
    {
        echo ''
        echo '# Added by Roe (roe.sh) — keeps rbenv-managed Ruby on PATH'
        echo 'eval "$(rbenv init - '"$shell_name"')"'
    } >> "$rc_file"

    log_success "Added rbenv init to $rc_file (shell: $shell_name)"
    return 0
}

# In-place sed that works on regular files AND symlinks (dotfile
# managers symlink rc files; BSD `sed -i ''` refuses to edit those).
# Transform to a temp file, then `cat` the result back through the
# path — that rewrites the symlink's target contents while preserving
# the link itself, and sidesteps the GNU-vs-BSD `-i` syntax split.
_sed_inplace() {
    local expr="$1" file="$2" tmp
    tmp="$(mktemp 2>/dev/null)" || return 1
    if sed "$expr" "$file" > "$tmp" 2>/dev/null; then
        cat "$tmp" > "$file"
    fi
    rm -f "$tmp"
}

# Every shell-startup file we might need to scan or edit, for the
# user's current shell. zsh honours ZDOTDIR — when it's set, the
# active .zshrc/.zprofile/.zlogin live there, NOT in $HOME (a very
# common gotcha with dotfile managers like stow/stash). We list BOTH
# locations so we catch whichever the user's setup actually sources,
# plus the login-shell files (.zprofile/.zlogin) where PATH exports
# usually live, and .zshenv which zsh reads for every shell.
_rc_candidate_files() {
    local shell_name; shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)
            local dirs="$HOME"
            [ -n "${ZDOTDIR:-}" ] && [ "$ZDOTDIR" != "$HOME" ] && dirs="$HOME $ZDOTDIR"
            local d
            for d in $dirs; do
                echo "$d/.zshenv"; echo "$d/.zprofile"; echo "$d/.zshrc"; echo "$d/.zlogin"
            done
            ;;
        bash)
            echo "$HOME/.bash_profile"; echo "$HOME/.bashrc"; echo "$HOME/.profile"
            ;;
        *)
            echo "$HOME/.profile"
            ;;
    esac
}

# The single rc file we WRITE `mise activate` into — the interactive
# rc, ZDOTDIR-aware for zsh.
_mise_write_target() {
    local shell_name; shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)  echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) echo "$HOME/.bash_profile" ;;
        *)    return 1 ;;
    esac
}

# When an install switches to mise, rbenv must stop managing Ruby — if
# both are active they fight over .ruby-version and rbenv (which won't
# have the new version) wins, producing:
#   rbenv: version `4.0.5' is not installed (set by .../.ruby-version)
# even though mise has it. rbenv hooks in two independent ways, BOTH of
# which we neutralize:
#   1. `eval "$(rbenv init ...)"`           — the shell integration
#   2. `export PATH=".../.rbenv/shims:..."` — a hardcoded shims path,
#      which intercepts even when init never runs
# Comments out any UNcommented occurrence of either, across every
# candidate startup file (ZDOTDIR-aware). Reversible — the user can
# un-comment. Lines already starting with `#` are left alone, so it's
# idempotent.
disable_rbenv_in_shell() {
    local rc
    for rc in $(_rc_candidate_files); do
        [ -f "$rc" ] || continue
        if grep -qE '^[[:space:]]*[^#[:space:]].*rbenv init' "$rc" 2>/dev/null; then
            _sed_inplace 's/^\([[:space:]]*\)\([^#[:space:]].*rbenv init.*\)$/\1# [Roe: disabled — mise manages Ruby now] \2/' "$rc"
            log_info "Disabled rbenv init in $rc"
        fi
        if grep -qE '^[[:space:]]*[^#[:space:]].*\.rbenv/shims' "$rc" 2>/dev/null; then
            _sed_inplace 's|^\([[:space:]]*\)\([^#[:space:]].*\.rbenv/shims.*\)$|\1# [Roe: disabled — mise manages Ruby now] \2|' "$rc"
            log_info "Disabled rbenv shims PATH in $rc"
        fi
    done
    return 0
}

# True if any rc candidate file has an ACTIVE (uncommented) rbenv init or
# .rbenv/shims line — i.e. something disable_rbenv_in_shell would edit.
# This is exactly what we ask permission before touching.
_rbenv_lines_in_rc() {
    local rc
    for rc in $(_rc_candidate_files); do
        [ -f "$rc" ] || continue
        grep -qE '^[[:space:]]*[^#[:space:]].*(rbenv init|\.rbenv/shims)' "$rc" 2>/dev/null && return 0
    done
    return 1
}

# Warn — never edit — about other Ruby managers that can fight mise over
# .ruby-version / PATH. Their shell integration varies too much to rewrite
# safely, so we only make the developer aware in case Ruby later resolves
# to the wrong place.
_warn_other_ruby_managers() {
    local found=""
    if command_exists rvm  || [ -d "$HOME/.rvm" ];  then found="$found rvm";  fi
    if command_exists asdf || [ -d "$HOME/.asdf" ]; then found="$found asdf"; fi
    if [ -d "$HOME/.rubies" ] || [ -f /usr/local/share/chruby/chruby.sh ]; then found="$found chruby"; fi
    found="$(echo "$found" | xargs)"   # trim whitespace
    [ -z "$found" ] && return 0

    echo ""
    log_warning "Other Ruby version manager(s) detected: ${found}"
    echo -e "  Roe uses ${BOLD}mise${NC} and will NOT change your ${found} setup."
    echo -e "  If Ruby later resolves to the wrong version, disable ${found} for this"
    echo -e "  project, or make sure mise activates after it in your shell startup files."
}

# Resolve conflicts with other Ruby managers BEFORE writing mise into the
# shell. rbenv is the one we can cleanly (and reversibly) neutralize — but
# we ASK first rather than editing someone's shell config unprompted.
# Everything else is warn-only. May exit if the user opts to handle rbenv
# themselves.
handle_ruby_manager_conflicts() {
    if _rbenv_lines_in_rc; then
        echo ""
        echo -e "  ${BOLD}You have rbenv set up in your shell.${NC} It can conflict with mise —"
        echo -e "  both manage Ruby, and rbenv can win on PATH."
        echo ""
        echo -e "  Roe can comment out rbenv's startup lines for you. This is reversible:"
        echo -e "  the lines are prefixed with a note, never deleted."
        echo ""
        echo "  How would you like to proceed?"
        echo "    [1] Let Roe handle it      (recommended)"
        echo "    [2] I'll handle it myself  (quit install for now)"
        echo ""
        breathing_room
        read -rp "  Choose [1/2]: " REPLY
        case "${REPLY:-1}" in
            2 | [Qq]*)
                echo ""
                echo -e "  No problem. When you're ready, comment out the ${CYAN}rbenv init${NC} and"
                echo -e "  ${CYAN}.rbenv/shims${NC} lines in your shell startup file, then re-run ${CYAN}./roe.sh check${NC}."
                exit 0
                ;;
            *)
                disable_rbenv_in_shell
                ;;
        esac
    fi

    _warn_other_ruby_managers
}

# mise equivalent of ensure_rbenv_in_shell. Writes `mise activate` to
# the user's interactive rc (ZDOTDIR-aware), AND neutralizes any rbenv
# integration so the two managers don't conflict. Returns 0 on success
# / already-present, 1 on unsupported shells.
# Modern mise (2024+) does NOT read idiomatic version files like
# `.ruby-version` unless the tool is opted in via this setting — without
# it, `mise activate` runs but has no Ruby pinned for the project, so
# `ruby` silently falls through to the system Ruby. Roe keeps a single
# version file (`.ruby-version`, which rbenv also reads), so we enable
# mise to honour it. Idempotent — `set` overwrites to the same value.
configure_mise_for_ruby() {
    command_exists mise || return 0
    mise settings set idiomatic_version_file_enable_tools "ruby" 2>/dev/null \
        && log_info "Configured mise to read .ruby-version" || true

    # Use precompiled Ruby binaries instead of compiling from source.
    # mise's default (until 2026.8.0) is to build Ruby + OpenSSL from
    # source via ruby-build — slow (several minutes) and the source path
    # is where the cryptic OpenSSL `make` failures live. Precompiled
    # binaries download in seconds and Just Work. This becomes mise's
    # default soon; we opt in now. (`set` overwrites to the same value,
    # so this is idempotent.)
    mise settings set ruby.compile false 2>/dev/null \
        && log_info "Configured mise to use precompiled Ruby" || true
}

ensure_mise_in_shell() {
    local shell_name rc_file
    shell_name="$(basename "$SHELL")"
    rc_file="$(_mise_write_target)" || {
        log_warning "Unsupported shell: $shell_name — can't auto-configure"
        return 1
    }

    # Resolve conflicts with other Ruby managers BEFORE writing mise into
    # the shell. rbenv is asked-about and only disabled on consent (it's
    # reversible); rvm/asdf/chruby are warn-only. This may exit if the user
    # chooses to handle rbenv themselves.
    handle_ruby_manager_conflicts

    # Make mise honour .ruby-version (off by default in modern mise).
    configure_mise_for_ruby

    # mise's standalone installer puts the binary at ~/.local/bin/mise,
    # which is NOT on macOS's default login PATH — so a bare
    # `eval "$(mise activate …)"` line dies with "command not found:
    # mise" in a fresh shell and Ruby never activates. We instead write a
    # self-contained block that FIRST puts mise's own directory on PATH,
    # then activates (guarded, so it's a harmless no-op if mise really is
    # missing). When mise came from Homebrew its dir is already on PATH
    # and re-adding it changes nothing.
    local marker='# Added by Roe — mise (Ruby version manager) activation'
    if grep -qF "$marker" "$rc_file" 2>/dev/null; then
        log_info "mise activation already configured in $rc_file"
        return 0
    fi

    # Comment out any older bare activate line a previous version wrote
    # (no PATH guard — the source of the "command not found: mise"
    # error). The new block below supersedes it.
    if grep -qE 'eval "\$\(mise activate' "$rc_file" 2>/dev/null; then
        _sed_inplace 's|^\(.*eval "\$(mise activate.*\)$|# [Roe: superseded] \1|' "$rc_file"
        log_info "Replaced an older mise activate line in $rc_file"
    fi

    # Resolve mise's install directory so we can put it on PATH. Prefer a
    # $HOME-relative entry so the written rc line stays portable.
    local mise_bin_dir path_frag
    if command -v mise >/dev/null 2>&1; then
        mise_bin_dir="$(cd "$(dirname "$(command -v mise)")" 2>/dev/null && pwd)"
    fi
    case "$mise_bin_dir" in
        "$HOME"/*) path_frag='$HOME'"${mise_bin_dir#"$HOME"}" ;;
        "")        path_frag='$HOME/.local/bin' ;;
        *)         path_frag="$mise_bin_dir" ;;
    esac

    {
        echo ''
        echo "$marker"
        echo "export PATH=\"$path_frag:\$PATH\""
        echo "command -v mise >/dev/null 2>&1 && eval \"\$(mise activate $shell_name)\""
    } >> "$rc_file"

    log_success "Added mise to PATH + activation in $rc_file (shell: $shell_name)"
    return 0
}

# Install mise itself (the version manager), preferring a Homebrew
# install when brew is already present (clean, managed) and falling
# back to mise's standalone installer otherwise — which crucially needs
# NO Homebrew and NO compiler, just curl. After install, put it on PATH
# for the rest of this script process.
# Install mise directly (no copy-paste-in-another-terminal). Both
# install methods are non-interactive and need no sudo. Returns 0 if
# mise ends up on PATH for this process, non-zero otherwise.
install_mise() {
    if is_macos && check_brew; then
        brew install mise
    else
        # The official standalone installer — single self-contained
        # binary to ~/.local/bin, no Homebrew or compiler needed.
        curl -fsSL https://mise.run | sh
    fi
    # Surface the freshly-installed binary to the current process so the
    # rest of the script can use it without a new shell.
    if ! command_exists mise; then
        for _m in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
            [ -x "$_m" ] && export PATH="$(dirname "$_m"):$PATH" && break
        done
    fi
    command_exists mise
}

# ── Requirement checks ────────────────────────────────────────────────────────

# Check Ruby — requires minimum version matching APP_DIR/.ruby-version
# Runs from APP_DIR so rbenv/.ruby-version is honoured.
check_ruby() {
    local required
    required=$(cat "$APP_DIR/.ruby-version" 2>/dev/null || echo "3.2.2")
    local req_major req_minor req_patch
    IFS='.' read -r req_major req_minor req_patch <<< "$required"

    local actual
    actual=$(cd "$APP_DIR" && ruby --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$actual" ] && return 1

    local act_major act_minor act_patch
    IFS='.' read -r act_major act_minor act_patch <<< "$actual"

    # Major must match; minor.patch must be >=
    [ "$act_major" -eq "$req_major" ] || return 1
    [ "$act_minor" -gt "$req_minor" ] && return 0
    [ "$act_minor" -eq "$req_minor" ] && [ "$act_patch" -ge "$req_patch" ] && return 0
    return 1
}

check_git()     { command_exists git; }
check_sqlite()  { command_exists sqlite3; }
check_libvips() { command_exists vips; }
check_bundler() { cd "$APP_DIR" && command_exists bundle; }

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    echo -e "${BOLD}Roe — Server Management${NC}"
    echo ""
    echo "Usage: roe.sh {command}"
    echo ""
    echo -e "${BOLD}Setup Commands:${NC}"
    echo "  check         Check system requirements and guide installation"
    echo "  setup         Run the full Roe setup (runs check first)"
    echo "  setup-mise    Add 'mise activate' to your shell rc file (zsh / bash)"
    echo "  setup-rbenv   Add 'rbenv init' to your shell rc file (zsh / bash)"
    echo ""
    echo -e "${BOLD}Server Commands:${NC}"
    echo "  start     Start the Roe server"
    echo "  stop      Stop the Roe server (Rails + Tailwind watcher)"
    echo "  restart   Restart the Roe server"
    echo "  console   Open Rails console"
    echo "  status    Show server status and requirements"
    echo ""
    echo -e "${BOLD}Maintenance:${NC}"
    echo "  update    Check for Roe updates"
    echo ""
    echo "Examples:"
    echo "  ./roe.sh check     # First time? Start here!"
    echo "  ./roe.sh setup     # Install Roe after requirements are met"
    echo "  ./roe.sh start     # Start the server"
    echo ""
    echo "Directories:"
    echo "  Root: $ROE_ROOT"
    echo "  App:  $APP_DIR"
    echo "  Site: $SITE_DIR"
}

# Read-only preflight: scan the boot-essential dependencies and print a
# one-glance status table BEFORE the interactive install steps. Pure
# probes — no prompts, no installs, no side effects.
#
# This check is deliberately minimal: only what Roe needs to RUN. Ruby
# is the irreducible floor (everything past this point — gem install,
# DB setup, the admin TUI — is Ruby). Git is here because the in-app
# updater needs it. Everything else (gems, database, optional image
# tooling) is handled in the friendlier setup flow once Ruby is present.
print_requirements_summary() {
    local required_ruby
    required_ruby=$(cat "$APP_DIR/.ruby-version" 2>/dev/null || echo "3.2.2")

    log_step "Checking what's already installed"

    if check_ruby; then
        local r; r=$(cd "$APP_DIR" && ruby --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Ruby ${r}"
    else
        log_warning "Ruby ${required_ruby} — will install"
    fi
    check_git && log_success "Git" || log_warning "Git — will install"
    echo ""
}

# ── Check command ─────────────────────────────────────────────────────────────

cmd_check() {
    start_install_log check
    echo -e "${BOLD}"
    echo "╔════════════════════════════════════════╗"
    echo "║        Roe — Requirements Check        ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "I'll check your system for required dependencies."
    echo "If anything is missing, I'll guide you through installing it."
    echo ""
    echo -e "  OS detected: ${BOLD}${OS}${NC}"
    echo ""
    echo -e "  For the full list of what Roe needs (and the optional extras), see"
    echo -e "  ${CYAN}README.md${NC} — the ${BOLD}Requirements${NC} section — in this folder."
    echo ""

    local all_good=true
    local required_ruby
    required_ruby=$(cat "$APP_DIR/.ruby-version" 2>/dev/null || echo "3.2.2")

    print_requirements_summary

    # The blocks below only engage when something is MISSING — the
    # summary above already reported what's present, so re-printing
    # "✓ X is installed" would just be noise.
    #
    # Homebrew is no longer installed proactively: mise installs Ruby via
    # its own standalone installer (no brew needed), and Git falls back
    # to Xcode CLT. Where a dep CAN use brew it still prefers it when
    # present — but we never make Homebrew a prerequisite of its own.

    # ── Ruby ──────────────────────────────────────────────────────────────────
    if ! check_ruby; then
        log_step "Installing Ruby ${required_ruby} (Required)"
        log_error "Ruby ${required_ruby}+ is not installedu"
        all_good=false

        # Two install paths. mise is the default for fresh installs:
        # one self-contained binary, precompiled rubies (seconds, not a
        # 5–10 min source compile), no Homebrew or build-tools
        # prerequisite. rbenv stays as the fallback ONLY for users who
        # already have it — we don't steer anyone new toward it.
        if command_exists rbenv && rbenv versions 2>/dev/null | grep -q "${required_ruby}"; then
            # Existing rbenv user who already has the right Ruby built —
            # just select it, no reinstall.
            log_success "Ruby ${required_ruby} already installed via rbenv — setting as global"
            rbenv global "${required_ruby}" 2>/dev/null || true
            source_profile
            ensure_installed check_ruby "Ruby ${required_ruby}" \
                "rbenv install ${required_ruby} && rbenv global ${required_ruby}"
            log_success "Ruby is now installed!"
            all_good=true
        else
            # ── One-prompt, install-it-for-you path ───────────────────
            # No copy-paste, no second terminal: with the user's OK, we
            # run the mise + Ruby installs right here and keep going.
            echo -e "  ${BOLD}Roe needs Ruby ${required_ruby}.${NC}"
            echo -e "  I'll install mise (a small version manager) and Ruby ${required_ruby} for you — no extra steps."
            echo ""
            breathing_room
            read -rp "  Install now? [y/q]: " REPLY
            case "${REPLY:-y}" in
                [Qq]*)
                    echo "  No problem — run ${CYAN}./roe.sh check${NC} whenever you're ready."
                    exit 0
                    ;;
            esac
            echo ""

            # 1. mise itself
            if ! command_exists mise; then
                log_step "Installing mise"
                if ! install_mise; then
                    log_error "Couldn't install mise automatically."
                    echo "  Install it manually, then re-run ./roe.sh check:"
                    echo "    ${CYAN}curl https://mise.run | sh${NC}"
                    exit 1
                fi
                log_success "mise installed"
            fi

            # 2. Make mise honour .ruby-version, activate it for THIS
            #    process, and persist activation to the user's shell rc
            #    (so future terminals see it too).
            configure_mise_for_ruby
            mise_pin_app_ruby
            ensure_mise_in_shell

            # 3. Native builds need a compiler + make. On macOS that's
            #    Apple's Command Line Tools; on Linux it's the distro's
            #    build tools. Make sure they're present BEFORE we install
            #    Ruby and (later) compile native gems, so nothing races
            #    ahead of the compiler and fails. Each no-ops off its OS.
            ensure_macos_build_tools
            ensure_linux_build_tools

            # 4. Install + pin Ruby. Runs right here — output streams, and
            #    the first build can take a few minutes.
            log_step "Installing Ruby ${required_ruby}"
            log_info "Downloading Ruby — the first build can take a few minutes…"
            if ! mise use --global "ruby@${required_ruby}"; then
                log_error "Ruby install failed — see the output above."
                exit 1
            fi
            mise_pin_app_ruby

            # 4. Verify it's now visible.
            if check_ruby; then
                log_success "Ruby ${required_ruby} is ready!"
                all_good=true
            else
                log_error "Ruby installed but isn't being detected yet."
                echo "  Open a new terminal and re-run ${CYAN}./roe.sh check${NC}."
                exit 1
            fi
        fi
    fi

    # ── Git ───────────────────────────────────────────────────────────────────
    if ! check_git; then
        log_step "Installing Git (Required)"
        log_error "Git is not installed"
        all_good=false
        local git_desc git_cmd
        if is_macos && check_brew; then
            git_desc="Git"; git_cmd="brew install git"
        elif is_macos; then
            git_desc="Git (Xcode tools)"; git_cmd="xcode-select --install"
        else
            git_desc="Git"; git_cmd="sudo apt-get install git   # or: sudo dnf install git"
        fi
        install_prompt "$git_desc" "$git_cmd"
        ensure_installed check_git "$git_desc" "$git_cmd"
        log_success "Git is now installed!"
    fi

    # Bundler ships with Ruby (default gem) — no separate check needed.
    # SQLite3's CLI is not required: the sqlite3 gem bundles its own
    # library, and backups copy DB files via rsync. Image tooling
    # (libvips) is optional and offered later in the friendlier setup
    # flow, not here.

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════${NC}"
    echo ""

    if $all_good; then
        log_success "Ready — Ruby and Git are in place."
        echo ""
        echo -e "${BOLD}Next step:${NC} Run the Roe setup"
        echo -e "   ${CYAN}./roe.sh setup${NC}"
        echo ""
        breathing_room
        read -rp "Run setup now? [y/n]: " REPLY
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # cmd_setup reuses this log (nesting guard) and marks the
            # whole run OK only once the app boots cleanly.
            cmd_setup
        else
            # Check-only success — deps are in place, user deferred setup.
            mark_install_ok
        fi
    else
        log_error "Some required dependencies are missing"
        echo ""
        echo "Please install the missing dependencies and run: ./roe.sh check"
        exit 1
    fi
}

# ── Setup command ─────────────────────────────────────────────────────────────

cmd_setup() {
    start_install_log setup
    log_step "Checking Requirements"

    local all_good=true
    check_ruby    || { log_error "Ruby $(cat "$APP_DIR/.ruby-version" 2>/dev/null || echo "3.2.2")+ required"; all_good=false; }
    check_git     || { log_error "Git required"; all_good=false; }
    check_bundler || { log_error "Bundler required"; all_good=false; }

    if ! $all_good; then
        echo ""
        echo -e "Please run: ${CYAN}./roe.sh check${NC}"
        exit 1
    fi

    log_success "All requirements met!"
    echo ""
    log_step "Running Roe Setup"
    echo ""
    cd "$APP_DIR"
    "$APP_DIR/bin/setup" || { log_error "bin/setup failed — see the log path printed below."; exit 1; }

    # ── Final verification ─────────────────────────────────────────
    # Confirm the app actually boots (gems load, DB connects, config
    # parses) rather than just assuming setup worked. A non-interactive
    # `runner` is a faithful proxy for "the server will start" without
    # the port/background dance of a full boot.
    log_step "Verifying installation"
    if "$APP_DIR/bin/rails" runner 'print "ok"' 2>/dev/null | grep -q "ok"; then
        log_success "Roe booted cleanly"
        echo ""
        echo -e "  ${BOLD}You're ready.${NC} Start Roe with:"
        echo -e "     ${CYAN}./roe.sh start${NC}"
        echo -e "  Then open ${CYAN}http://localhost:3000${NC}"
        mark_install_ok
    else
        log_error "Setup ran, but the app failed to boot."
        echo -e "  Try ${CYAN}./roe.sh start${NC} to see the full error, or check the log path below."
        exit 1
    fi
}

# ── setup-rbenv command ───────────────────────────────────────────────────────

# Standalone command: configure the user's shell to load rbenv. cmd_check
# already does this as part of its Step 2 when rbenv is missing; this is
# the targeted command you run when you've installed rbenv another way
# (or trashed your rc file) and just want the init line written back.
cmd_setup_rbenv() {
    if ! command_exists rbenv; then
        log_error "rbenv isn't installed."
        echo "Install it first, then re-run this command:"
        echo "  brew install rbenv"
        echo "  rbenv install \$(cat \"$APP_DIR/.ruby-version\")"
        echo "  rbenv global \$(cat \"$APP_DIR/.ruby-version\")"
        exit 1
    fi

    if ensure_rbenv_in_shell; then
        echo ""
        log_info "Open a new terminal or run this in the current one:"
        case "$(basename "$SHELL")" in
            zsh)  echo "  source ~/.zshrc" ;;
            bash) echo "  source ~/.bash_profile" ;;
        esac
    else
        exit 1
    fi
}

# ── setup-mise command ────────────────────────────────────────────────────────

# Standalone command: configure the user's shell to load mise. cmd_check
# does this in its Step 2 when installing Ruby; this is the targeted
# command for when you installed mise another way (or trashed your rc
# file) and just want the activation line written back.
cmd_setup_mise() {
    if ! command_exists mise; then
        log_error "mise isn't installed."
        echo "Install it first, then re-run this command:"
        echo "  curl https://mise.run | sh   # or: brew install mise"
        echo "  mise use --global ruby@\$(cat \"$APP_DIR/.ruby-version\")"
        exit 1
    fi

    if ensure_mise_in_shell; then
        echo ""
        # A script can't reload its *parent* shell — sourcing the rc in
        # this short-lived process would change nothing for the terminal
        # the user is sitting in. The closest thing to "it just works" is
        # to replace THIS process with a fresh login shell, which sources
        # the updated rc on startup: the user lands in a working shell
        # immediately (mise active, `bundle`/`ruby` resolved), and a later
        # `exit` simply returns them to where they were.
        local login_shell="${SHELL:-}"
        if [ -t 1 ] && [ -n "$login_shell" ] && [ -x "$login_shell" ]; then
            log_success "mise is configured — reloading your shell so it's active now…"
            echo -e "  ${DIM}(You're in a fresh shell. Type ${NC}${CYAN}exit${NC}${DIM} to return to your previous one.)${NC}"
            echo ""
            exec "$login_shell" -l
        fi
        # Non-interactive (piped/CI) or no usable $SHELL: fall back to the
        # manual instruction.
        log_info "Open a new terminal or run this in the current one:"
        case "$(basename "$login_shell")" in
            zsh)  echo "  source ~/.zshrc" ;;
            bash) echo "  source ~/.bash_profile" ;;
            *)    echo "  source your shell's startup file" ;;
        esac
    else
        exit 1
    fi
}

# ── Start command ─────────────────────────────────────────────────────────────

# Kill any orphaned Tailwind watcher processes from previous runs
kill_tailwind_watchers() {
    local pids
    pids=$(pgrep -f "tailwindcss:watch" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        log_info "Killing orphaned Tailwind watcher(s)..."
        echo "$pids" | xargs kill 2>/dev/null || true
    fi
}

# ── Port collision handling ──────────────────────────────────────────
#
# When a user runs ./roe.sh start and something is already bound to
# port 3000 (a different Roe install, a Rails app, a React dev server,
# etc.), Puma fails with EADDRINUSE and the user sees a wall of stack
# trace they can't interpret. The helpers below let us recover
# gracefully:
#
#   1. If the thing on the port responds as Roe (HTTP probe → "Roe"
#      in the /admin page title), we kill it. Two Roes on one port is
#      impossible and starting a new one is what the user asked for.
#
#   2. If the thing on the port is something else, we pick an
#      alternate port (next free above the requested one). Killing an
#      unknown process is too dangerous — could be the user's other
#      dev work.
#
# Requires lsof (for port checks and finding the PID — ships on macOS,
# universally available on Linux). curl is used for the Roe HTTP probe.
# Without either, we degrade to "let Puma's bind fail" which is the
# pre-existing behaviour.

# Returns 0 if the given TCP port is bound by some process, 1 otherwise.
port_in_use() {
    local port="$1"
    command -v lsof >/dev/null 2>&1 || return 1
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

# Returns 0 if whatever's on the given port responds as a Roe install.
# Hits /admin (every Roe install serves it) and looks for "Roe" in
# the response body — that's the <title> on the admin layout, so a
# match is a strong positive. False positives are essentially
# impossible without someone deliberately mimicking the title.
is_roe_on_port() {
    local port="$1"
    command -v curl >/dev/null 2>&1 || return 1
    local body
    body=$(curl -sf --max-time 2 "http://localhost:$port/admin" 2>/dev/null || true)
    [ -n "$body" ] && echo "$body" | grep -q "Roe"
}

# Soft-kill (SIGTERM) the process bound to a port. Waits a moment for
# graceful shutdown, then SIGKILLs if still alive.
kill_pid_on_port() {
    local port="$1"
    command -v lsof >/dev/null 2>&1 || return 1
    local pid
    pid=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)
    [ -z "$pid" ] && return 1

    kill "$pid" 2>/dev/null || true
    sleep 2
    if ps -p "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" 2>/dev/null || true
        sleep 1
    fi
}

# Find the next free port at or above the given start, up to start+20.
# Echoes the port to stdout, or returns 1 if nothing's free in the
# scan range (unusual — would mean 20 consecutive busy ports).
find_free_port() {
    local candidate="$1"
    local max=$((candidate + 20))
    while [ "$candidate" -lt "$max" ]; do
        if ! port_in_use "$candidate"; then
            echo "$candidate"
            return 0
        fi
        candidate=$((candidate + 1))
    done
    return 1
}

# Main entry point: resolve a collision on $PORT before we actually
# try to bind. Updates $PORT in place if we shift to an alternate
# (anything calling this should re-derive $URL afterward).
resolve_port_collision() {
    port_in_use "$PORT" || return 0    # Port is free, nothing to do.

    if is_roe_on_port "$PORT"; then
        log_warning "Roe is already running on port $PORT. Stopping it before starting fresh…"
        kill_pid_on_port "$PORT"
        if ! port_in_use "$PORT"; then
            log_info "Port $PORT is now free."
            return 0
        fi
        log_warning "Port $PORT didn't free up after stopping the other Roe. Looking for an alternate."
    else
        log_warning "Port $PORT is in use by another app (not Roe). Looking for an alternate port."
    fi

    local original_port="$PORT"
    local new_port
    new_port=$(find_free_port "$((original_port + 1))")
    if [ -n "$new_port" ]; then
        PORT="$new_port"
        log_info "Using port $PORT instead of $original_port."
    else
        log_error "Couldn't find a free port near $original_port. Free up a port, or set PORT=<n> ./roe.sh start to choose one yourself."
        exit 1
    fi
}

cmd_start() {
    log_info "Starting Roe..."

    if [ -f "$APP_DIR/tmp/pids/server.pid" ]; then
        PID=$(cat "$APP_DIR/tmp/pids/server.pid")
        if ps -p "$PID" > /dev/null 2>&1; then
            log_warning "Server is already running (PID: $PID)"
            log_info "View: http://localhost:3000/welcome in your browser to use Roe."
            return 0
        else
            rm -f "$APP_DIR/tmp/pids/server.pid"
        fi
    fi

    cd "$APP_DIR"
    export SOLID_QUEUE_IN_PUMA=1
    RAILS_ENV="${RAILS_ENV:-development}"

    PORT="${PORT:-3000}"

    # Recover gracefully if something is already on PORT — either kill
    # it (if it identifies as another Roe install via HTTP probe) or
    # shift to the next free port (if it's some other app). Modifies
    # $PORT in place, so $URL has to be derived AFTER this call.
    resolve_port_collision

    URL="http://localhost:${PORT}"

    if [ "$RAILS_ENV" = "development" ]; then
        kill_tailwind_watchers

        echo ""
        echo -e "  ${BOLD}${GREEN}Roe is ready to start${NC}"
        echo -e "  Site: ${CYAN}${URL}${NC}"
        echo -e "  Admin:  ${CYAN}${URL}/admin${NC}"
        echo ""
        echo "  Choose:"
        echo "    [y] Start server and open in browser  (default)"
        echo "    [s] Start server only — don't open browser"
        echo "    [q] Quit without starting"
        echo ""
        breathing_room
        read -rp "  Choice [y/s/q]: " REPLY
        echo ""

        # Default (empty input) = launch browser. Anything starting with
        # s/S = start server but skip the auto-open. q/Q = bail out
        # entirely. Unknown input falls through to the default (launch)
        # rather than quitting — safer on a wrong keystroke.
        case "${REPLY:-y}" in
            [Qq]*)
                log_info "Cancelled. Run './roe.sh start' when ready."
                exit 0
                ;;
            [Ss]*)
                OPEN_BROWSER=0
                log_info "Starting server — browser will not open automatically."
                ;;
            *)
                OPEN_BROWSER=1
                ;;
        esac

        log_info "Starting Tailwind CSS watcher..."
        "$APP_DIR/bin/rails" tailwindcss:watch &
        TAILWIND_PID=$!
        echo "$TAILWIND_PID" > "$APP_DIR/tmp/pids/tailwind.pid"
        log_info "Tailwind watcher running (PID: $TAILWIND_PID)"

        cleanup() {
            log_info "Stopping Tailwind CSS watcher..."
            kill "$TAILWIND_PID" 2>/dev/null || true
            rm -f "$APP_DIR/tmp/pids/tailwind.pid"
        }
        trap cleanup EXIT INT TERM

        # Open browser after a short delay to let the server boot.
        # Supports macOS (open) and Linux (xdg-open). Skipped entirely
        # when the user chose [s] (start server only) at the prompt.
        #
        # Two tabs: the public site (/) first, then the admin (/admin)
        # LAST so admin ends up the focused/frontmost tab — the user
        # lands ready to sign in, with their live site one tab over.
        if [ "$OPEN_BROWSER" = "1" ]; then
            (
                sleep 3
                _open_url() {
                    if command -v open >/dev/null 2>&1; then
                        open "$1"
                    elif command -v xdg-open >/dev/null 2>&1; then
                        xdg-open "$1"
                    fi
                }
                _open_url "${URL}/"
                sleep 1   # let the first tab open before the second steals focus
                _open_url "${URL}/admin"
            ) &
        fi

        # bin/thrust is shipped by Rails 8 (the thruster gem) and would
        # otherwise be preferred here, but Thruster binds port 80 by
        # default — privileged on macOS/Linux, almost always already
        # in use locally, and not how Roe is meant to run anywhere.
        # Production deploys (Fly + Kamal) launch bin/rails server
        # directly per the generated configs; dev wants the standard
        # Puma on PORT (defaults to 3000).
        "$APP_DIR/bin/rails" server "$@"
    else
        exec "$APP_DIR/bin/rails" server "$@"
    fi
}

# ── Stop command ──────────────────────────────────────────────────────────────

cmd_stop() {
    log_info "Stopping Roe..."

    # Stop Rails server
    if [ -f "$APP_DIR/tmp/pids/server.pid" ]; then
        PID=$(cat "$APP_DIR/tmp/pids/server.pid")
        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID"
            log_success "Rails server stopped (PID: $PID)"
        else
            log_warning "PID file exists but Rails server not running"
        fi
        rm -f "$APP_DIR/tmp/pids/server.pid"
    else
        log_warning "Rails server is not running"
    fi

    # Stop Tailwind watcher (pid file)
    if [ -f "$APP_DIR/tmp/pids/tailwind.pid" ]; then
        TW_PID=$(cat "$APP_DIR/tmp/pids/tailwind.pid")
        if ps -p "$TW_PID" > /dev/null 2>&1; then
            kill "$TW_PID"
            log_success "Tailwind watcher stopped (PID: $TW_PID)"
        fi
        rm -f "$APP_DIR/tmp/pids/tailwind.pid"
    fi

    # Kill any remaining orphaned Tailwind watchers
    kill_tailwind_watchers
}

# ── Restart command ───────────────────────────────────────────────────────────

cmd_restart() {
    log_info "Restarting Roe..."
    cmd_stop
    sleep 1
    cmd_start "$@"
}

# ── Console command ───────────────────────────────────────────────────────────

cmd_console() {
    log_info "Opening Rails console..."
    cd "$APP_DIR"
    exec "$APP_DIR/bin/rails" console
}

# ── Status command ────────────────────────────────────────────────────────────

cmd_status() {
    local required_ruby
    required_ruby=$(cat "$APP_DIR/.ruby-version" 2>/dev/null || echo "3.2.2")

    echo -e "${BOLD}Roe Status${NC}"
    echo "=============="
    echo ""
    echo "Root:    $ROE_ROOT"
    echo "App:     $APP_DIR"
    echo "Site:    $SITE_DIR"
    echo "Version: $(grep 'version:' "$ROE_ROOT/VERSION" 2>/dev/null | cut -d'"' -f2 || echo 'unknown')"
    echo ""

    # Server
    if [ -f "$APP_DIR/tmp/pids/server.pid" ]; then
        PID=$(cat "$APP_DIR/tmp/pids/server.pid")
        if ps -p "$PID" > /dev/null 2>&1; then
            log_success "Rails server running (PID: $PID)"
        else
            log_error "PID file exists but server not running (stale)"
        fi
    else
        log_warning "Rails server is not running"
    fi

    if [ -f "$APP_DIR/tmp/pids/tailwind.pid" ]; then
        TW_PID=$(cat "$APP_DIR/tmp/pids/tailwind.pid")
        if ps -p "$TW_PID" > /dev/null 2>&1; then
            log_success "Tailwind watcher running (PID: $TW_PID)"
        else
            log_warning "Tailwind PID file exists but watcher not running (stale)"
        fi
    fi

    # Requirements
    echo ""
    echo -e "${BOLD}Requirements:${NC}"
    if check_ruby; then
        actual=$(cd "$APP_DIR" && ruby --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Ruby $actual (>= ${required_ruby} required)"
    else
        log_error "Ruby ${required_ruby}+ not found"
    fi
    check_git     && log_success "Git $(git --version | cut -d' ' -f3)"   || log_error "Git not found"
    check_bundler && log_success "Bundler"                                  || log_error "Bundler not found"
    check_sqlite  && log_success "SQLite3"                                  || log_error "SQLite3 not found"
    check_libvips && log_success "libvips (optional)" || log_warning "libvips not installed (optional)"
}

# ── Update command ────────────────────────────────────────────────────────────

cmd_update() {
    log_info "Checking for Roe updates..."
    cd "$APP_DIR"
    "$APP_DIR/bin/rails" runner "
      result = RoeUpdater::VersionChecker.check_for_updates
      if result
        puts \"Current: \#{RoeUpdater::VersionChecker.current_version}\"
        puts \"Latest:  \#{result[:latest_version]}\"
        if result[:update_available]
          puts \"\\nUpdate available! Visit Admin → Updates to install.\"
        else
          puts \"\\nRoe is up to date.\"
        end
      else
        puts 'Could not reach update server.'
      end
    "
}

# ── Main ──────────────────────────────────────────────────────────────────────

case "${1:-}" in
    check)        cmd_check ;;
    setup)        cmd_setup ;;
    setup-mise)   cmd_setup_mise ;;
    setup-rbenv)  cmd_setup_rbenv ;;
    start)        shift; cmd_start "$@" ;;
    stop)    cmd_stop ;;
    restart) shift; cmd_restart "$@" ;;
    console) cmd_console ;;
    status)  cmd_status ;;
    update)  cmd_update ;;
    help|--help|-h) usage ;;
    *)
        log_error "Unknown command: ${1:-}"
        echo ""
        usage
        exit 1
        ;;
esac
