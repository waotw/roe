#!/bin/bash
# Roe CMS Launcher Script
# Manages the Roe CMS server, setup, and updates.
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

# Activate the correct Ruby version from APP_DIR/.ruby-version
# Works whether the script is run from /roe or /roe/current
if [ -f "$APP_DIR/.ruby-version" ]; then
    REQUIRED_RUBY=$(cat "$APP_DIR/.ruby-version")
    if command -v rbenv >/dev/null 2>&1; then
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
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}▶${NC} ${BOLD}$1${NC}"; }

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

wait_for_enter() {
    echo
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
        echo '# Added by Roe CMS (roe.sh) — keeps rbenv-managed Ruby on PATH'
        echo 'eval "$(rbenv init - '"$shell_name"')"'
    } >> "$rc_file"

    log_success "Added rbenv init to $rc_file (shell: $shell_name)"
    return 0
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
    echo -e "${BOLD}Roe CMS — Server Management${NC}"
    echo ""
    echo "Usage: roe.sh {command}"
    echo ""
    echo -e "${BOLD}Setup Commands:${NC}"
    echo "  check         Check system requirements and guide installation"
    echo "  setup         Run the full Roe setup (runs check first)"
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

# ── Check command ─────────────────────────────────────────────────────────────

cmd_check() {
    echo -e "${BOLD}"
    echo "╔════════════════════════════════════════╗"
    echo "║     Roe CMS — Requirements Check       ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "I'll check your system for required dependencies."
    echo "If anything is missing, I'll guide you through installing it."
    echo ""
    echo -e "  OS detected: ${BOLD}${OS}${NC}"
    echo ""

    local all_good=true
    local has_optional_missing=false
    local required_ruby
    required_ruby=$(cat "$APP_DIR/.ruby-version" 2>/dev/null || echo "3.2.2")

    # ── Homebrew (macOS only) ─────────────────────────────────────────────
    if is_macos; then
        log_step "Checking Homebrew (macOS package manager)"
        if check_brew; then
            log_success "Homebrew is installed ($(brew --version | head -1 | cut -d' ' -f2))"
        else
            log_warning "Homebrew is not installed"
            echo -e "  Homebrew makes installing dependencies much easier on macOS."
            install_prompt "Homebrew" '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
                "Installing Homebrew is usually the biggest hurdle — after that it's pretty smooth. It can take a few minutes."
            if check_brew; then
                log_success "Homebrew is now installed!"
            else
                log_warning "Homebrew still not found — continuing without it"
                echo -e "  ${YELLOW}Note:${NC} Some install commands below may differ without Homebrew."
            fi
        fi
    fi

    # ── Ruby ──────────────────────────────────────────────────────────────────
    log_step "Checking Ruby ${required_ruby}+ (Required)"
    if check_ruby; then
        actual=$(cd "$APP_DIR" && ruby --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Ruby $actual is installed"
    else
        log_error "Ruby ${required_ruby}+ is not installed or the wrong version"
        all_good=false
        echo -e "  Ruby ${required_ruby} is required. Install via rbenv (recommended):"
        echo ""

        # Step 1 — rbenv itself
        if ! command_exists rbenv; then
            echo -e "  ${BOLD}Step 1${NC} — Install rbenv:"
            if is_macos && check_brew; then
                install_prompt "rbenv" "brew install rbenv"
            elif is_macos; then
                install_prompt "rbenv" '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install rbenv'
            else
                install_prompt "rbenv" 'curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash'
            fi
        else
            log_success "rbenv is already installed — skipping step 1"
        fi

        # Step 2 — rbenv shell init (only if not already in profile).
        # ensure_rbenv_in_shell writes the init line into the right rc
        # file directly. Earlier versions printed the command for the
        # user to copy/paste, which broke when their rendered-markdown
        # viewer substituted smart quotes for ASCII ones — the shell
        # then sat waiting for an unclosed quote. Writing it ourselves
        # sidesteps that entire failure mode.
        if ! grep -q 'rbenv init' "$HOME/.zshrc" 2>/dev/null && \
           ! grep -q 'rbenv init' "$HOME/.bash_profile" 2>/dev/null && \
           ! grep -q 'rbenv init' "$HOME/.bashrc" 2>/dev/null; then
            echo -e "  ${BOLD}Step 2${NC} — Add rbenv to your shell:"
            if ensure_rbenv_in_shell; then
                source_profile
            else
                # Fallback for shells we don't recognise — print a hint
                # and keep going so the rest of check still runs.
                log_warning "Add this line to your shell's rc file manually:"
                echo "  eval \"\$(rbenv init - \$(basename \"\$SHELL\"))\""
            fi
        else
            log_success "rbenv shell init already in profile — skipping step 2"
            source_profile
        fi

        # Step 3 — install the required Ruby version
        if ! command_exists rbenv || ! rbenv versions 2>/dev/null | grep -q "${required_ruby}"; then
            echo -e "  ${BOLD}Step 3${NC} — Install Ruby ${required_ruby}:"
            install_prompt "Ruby ${required_ruby}" \
                "rbenv install ${required_ruby} && rbenv global ${required_ruby}" \
                "This takes 5–10 minutes (compiles from source)"
        else
            log_success "Ruby ${required_ruby} already installed via rbenv — setting as global"
            rbenv global "${required_ruby}" 2>/dev/null || true
            source_profile
        fi

        ensure_installed check_ruby "Ruby ${required_ruby}" \
            "rbenv install ${required_ruby} && rbenv global ${required_ruby}" \
            "This takes 5–10 minutes (compiles from source)"
        log_success "Ruby is now installed!"
        all_good=true
    fi

    # ── Git ───────────────────────────────────────────────────────────────────
    log_step "Checking Git (Required)"
    if check_git; then
        log_success "Git is installed ($(git --version | cut -d' ' -f3))"
    else
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

    # ── Bundler ───────────────────────────────────────────────────────────────
    log_step "Checking Bundler (Required)"
    if check_bundler; then
        log_success "Bundler is installed ($(cd "$APP_DIR" && bundle --version | cut -d' ' -f3))"
    else
        log_warning "Bundler not found — installing now..."
        if cd "$APP_DIR" && gem install bundler 2>/dev/null; then
            log_success "Bundler installed!"
        else
            log_error "Failed to install Bundler."
            install_prompt "Bundler" "gem install bundler"
            check_bundler || { all_good=false; log_error "Bundler still not found"; }
        fi
    fi

    # ── SQLite3 ───────────────────────────────────────────────────────────────
    log_step "Checking SQLite3 (Required)"
    if check_sqlite; then
        log_success "SQLite3 is installed ($(sqlite3 --version | cut -d' ' -f1))"
    else
        log_error "SQLite3 is not installed"
        all_good=false
        local sqlite_cmd
        if is_macos && check_brew; then
            sqlite_cmd="brew install sqlite3"
        elif is_macos; then
            echo -e "  SQLite3 is usually pre-installed on macOS. Install Homebrew first:"
            sqlite_cmd='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install sqlite3'
        else
            sqlite_cmd="sudo apt-get install sqlite3 libsqlite3-dev   # or: sudo dnf install sqlite sqlite-devel"
        fi
        install_prompt "SQLite3" "$sqlite_cmd"
        ensure_installed check_sqlite "SQLite3" "$sqlite_cmd"
        log_success "SQLite3 is now installed!"
    fi

    # ── libvips (optional) ────────────────────────────────────────────────────
    log_step "Checking libvips (Optional — Roe uses this library to optimize all images in Roe. Highly recommended.)"
    if check_libvips; then
        log_success "libvips is installed ($(vips --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))"
    else
        log_warning "libvips is not installed"
        has_optional_missing=true
        echo -e "  libvips is ${BOLD}optional${NC} but recommended for image processing (thumbnails, variants)."
        echo ""
        read -rp "  Install libvips now? [y/n]: " REPLY
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Capture the install command + description once so the
            # retry loop can re-show the same command without the
            # OS-detection ladder being duplicated.
            local vips_desc="libvips" vips_cmd
            if is_macos && check_brew; then
                vips_cmd="brew install libvips"
            elif is_macos; then
                vips_cmd='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install libvips'
            else
                vips_cmd="sudo apt-get install libvips-dev   # or: sudo dnf install vips-devel"
            fi
            install_prompt "$vips_desc" "$vips_cmd"

            # Retry loop. Unlike the required-tool ensure_installed
            # helper, libvips is optional — so [n] skips and continues
            # the rest of `check` instead of exiting the script.
            while ! check_libvips; do
                echo ""
                read -rp "  libvips still not found. Try again? [y/n]: " REPLY
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    install_prompt "$vips_desc" "$vips_cmd"
                else
                    log_info "Skipping libvips — you can install it later"
                    break
                fi
            done

            if check_libvips; then
                log_success "libvips installed!"
                has_optional_missing=false
            fi
        else
            log_info "Skipping libvips — you can install it later"
        fi
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════${NC}"
    echo ""

    if $all_good; then
        log_success "All required dependencies are installed!"
        $has_optional_missing && log_warning "Some optional dependencies are missing (see above)"
        echo ""
        echo -e "${BOLD}Next step:${NC} Run the Roe setup"
        echo -e "   ${CYAN}./roe.sh setup${NC}"
        echo ""
        read -rp "Run setup now? [y/n]: " REPLY
        [[ $REPLY =~ ^[Yy]$ ]] && ROE_FIRST_RUN=1 cmd_setup
    else
        log_error "Some required dependencies are missing"
        echo ""
        echo "Please install the missing dependencies and run: ./roe.sh check"
        exit 1
    fi
}

# ── Setup command ─────────────────────────────────────────────────────────────

cmd_setup() {
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
    "$APP_DIR/bin/setup"
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
#   1. If the thing on the port responds as Roe (HTTP probe → "Roe CMS"
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
# Hits /admin (every Roe install serves it) and looks for "Roe CMS" in
# the response body — that's the <title> on the admin layout, so a
# match is a strong positive. False positives are essentially
# impossible without someone deliberately mimicking the title.
is_roe_on_port() {
    local port="$1"
    command -v curl >/dev/null 2>&1 || return 1
    local body
    body=$(curl -sf --max-time 2 "http://localhost:$port/admin" 2>/dev/null || true)
    [ -n "$body" ] && echo "$body" | grep -q "Roe CMS"
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
    log_info "Starting Roe CMS..."

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
        echo -e "  ${BOLD}${GREEN}Roe CMS is ready to start${NC}"
        echo -e "  Server: ${CYAN}${URL}${NC}"
        echo -e "  Admin:  ${CYAN}${URL}/admin${NC}"
        echo ""
        echo "  Choose:"
        echo "    [y] Start server and open in browser  (default)"
        echo "    [s] Start server only — don't open browser"
        echo "    [q] Quit without starting"
        echo ""
        read -rp "  Choice [Y/s/q]: " REPLY
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

        # Determine which URL to open — welcome page on first run, root otherwise
        if [ "${ROE_FIRST_RUN:-0}" = "1" ]; then
            OPEN_URL="${URL}/admin"
        else
            OPEN_URL="$URL"
        fi

        # Open browser after a short delay to let the server boot.
        # Supports macOS (open) and Linux (xdg-open). Skipped entirely
        # when the user chose [s] (start server only) at the prompt.
        if [ "$OPEN_BROWSER" = "1" ]; then
            (
                sleep 3
                if command -v open >/dev/null 2>&1; then
                    open "$OPEN_URL"
                elif command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "$OPEN_URL"
                fi
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
    log_info "Stopping Roe CMS..."

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
    log_info "Restarting Roe CMS..."
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

    echo -e "${BOLD}Roe CMS Status${NC}"
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
