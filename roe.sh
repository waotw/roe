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
# without opening a new shell. Tries zsh first, then bash.
source_profile() {
    if [ -f "$HOME/.zshrc" ]; then
        # shellcheck disable=SC1091
        source "$HOME/.zshrc" 2>/dev/null || true
    fi
    if [ -f "$HOME/.bash_profile" ]; then
        # shellcheck disable=SC1091
        source "$HOME/.bash_profile" 2>/dev/null || true
    fi
    if [ -f "$HOME/.bashrc" ]; then
        # shellcheck disable=SC1091
        source "$HOME/.bashrc" 2>/dev/null || true
    fi
    # Re-init rbenv if available so newly installed rubies are found
    if command -v rbenv >/dev/null 2>&1; then
        eval "$(rbenv init -)" 2>/dev/null || true
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

        if check_ruby; then
            log_success "Ruby is now installed!"
            all_good=true
        else
            log_error "Ruby ${required_ruby}+ still not found"
            echo "Please complete installation and run: ./roe.sh check"
            exit 1
        fi
    fi

    # ── Git ───────────────────────────────────────────────────────────────────
    log_step "Checking Git (Required)"
    if check_git; then
        log_success "Git is installed ($(git --version | cut -d' ' -f3))"
    else
        log_error "Git is not installed"
        all_good=false
        if is_macos && check_brew; then
            install_prompt "Git" "brew install git"
        elif is_macos; then
            install_prompt "Git (Xcode tools)" "xcode-select --install"
        else
            install_prompt "Git" "sudo apt-get install git   # or: sudo dnf install git"
        fi
        if check_git; then
            log_success "Git is now installed!"
        else
            log_error "Git still not found. Please install and run: ./roe.sh check"
            exit 1
        fi
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
        if is_macos && check_brew; then
            install_prompt "SQLite3" "brew install sqlite3"
        elif is_macos; then
            echo -e "  SQLite3 is usually pre-installed on macOS. Install Homebrew first:"
            install_prompt "SQLite3" '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install sqlite3'
        else
            install_prompt "SQLite3" "sudo apt-get install sqlite3 libsqlite3-dev   # or: sudo dnf install sqlite sqlite-devel"
        fi
        if check_sqlite; then
            log_success "SQLite3 is now installed!"
        else
            log_error "SQLite3 still not found. Please install and run: ./roe.sh check"
            exit 1
        fi
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
            if is_macos && check_brew; then
                install_prompt "libvips" "brew install libvips"
            elif is_macos; then
                install_prompt "libvips" '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install libvips'
            else
                install_prompt "libvips" "sudo apt-get install libvips-dev   # or: sudo dnf install vips-devel"
            fi
            if check_libvips; then
                log_success "libvips installed!"
                has_optional_missing=false
            else
                log_warning "libvips still not found — you can install it later"
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
    URL="http://localhost:${PORT}"

    if [ "$RAILS_ENV" = "development" ]; then
        kill_tailwind_watchers

        echo ""
        echo -e "  ${BOLD}${GREEN}Roe CMS is ready to start${NC}"
        echo -e "  Server: ${CYAN}${URL}${NC}"
        echo -e "  Admin:  ${CYAN}${URL}/admin${NC}"
        echo ""
        read -rp "  Start the app and open in browser? [y/n]: " REPLY
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled. Run './roe.sh start' when ready."
            exit 0
        fi

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

        # Open browser after a short delay to let the server boot
        # Supports macOS (open) and Linux (xdg-open)
        (
            sleep 3
            if command -v open >/dev/null 2>&1; then
                open "$OPEN_URL"
            elif command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$OPEN_URL"
            fi
        ) &

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
