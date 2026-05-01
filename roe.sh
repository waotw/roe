#!/bin/bash
# Roe CMS Launcher Script
# This script manages the Roe CMS server and handles version switching

set -e

# Detect directory structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_DIR="$(basename "$SCRIPT_DIR")"

if [ "$CURRENT_DIR" = "current" ]; then
    # We're inside current/ - versioned structure
    ROE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    APP_DIR="$SCRIPT_DIR"
    SITE_DIR="$ROE_ROOT/site"
elif [ -d "$SCRIPT_DIR/current" ]; then
    # We're at root and current/ exists - versioned structure
    ROE_ROOT="$SCRIPT_DIR"
    APP_DIR="$ROE_ROOT/current"
    SITE_DIR="$ROE_ROOT/site"
else
    # Standard structure (pre-Phase 2)
    ROE_ROOT="$SCRIPT_DIR"
    APP_DIR="$SCRIPT_DIR"
    SITE_DIR="$ROE_ROOT/site"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show usage
usage() {
    echo "Roe CMS - Server Management"
    echo ""
    echo "Usage: roe.sh {start|stop|restart|console|status|update}"
    echo ""
    echo "Commands:"
    echo "  start     Start the Roe server"
    echo "  stop      Stop the Roe server"
    echo "  restart   Restart the Roe server"
    echo "  console   Open Rails console"
    echo "  status    Check server status"
    echo "  update    Check for and install updates"
    echo ""
    echo "Root directory: $ROE_ROOT"
    echo "App directory: $APP_DIR"
    echo "Site directory: $SITE_DIR"
}

# Start server
cmd_start() {
    log_info "Starting Roe CMS..."
    
    if [ -f "$APP_DIR/tmp/pids/server.pid" ]; then
        PID=$(cat "$APP_DIR/tmp/pids/server.pid")
        if ps -p "$PID" > /dev/null 2>&1; then
            log_warning "Server is already running (PID: $PID)"
            return 0
        else
            rm -f "$APP_DIR/tmp/pids/server.pid"
        fi
    fi
    
    cd "$APP_DIR"
    
    if [ -f "$APP_DIR/bin/thrust" ]; then
        log_info "Using Thruster..."
        exec "$APP_DIR/bin/thrust" "$APP_DIR/bin/rails" server "$@"
    else
        exec "$APP_DIR/bin/rails" server "$@"
    fi
}

# Stop server
cmd_stop() {
    log_info "Stopping Roe CMS..."
    
    if [ -f "$APP_DIR/tmp/pids/server.pid" ]; then
        PID=$(cat "$APP_DIR/tmp/pids/server.pid")
        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID"
            log_success "Server stopped (PID: $PID)"
        else
            log_warning "PID file exists but process not running"
            rm -f "$APP_DIR/tmp/pids/server.pid"
        fi
    else
        log_warning "Server is not running"
    fi
}

# Restart server
cmd_restart() {
    log_info "Restarting Roe CMS..."
    cmd_stop
    sleep 2
    cmd_start "$@"
}

# Open console
cmd_console() {
    log_info "Opening Rails console..."
    cd "$APP_DIR"
    exec "$APP_DIR/bin/rails" console
}

# Check status
cmd_status() {
    echo "Roe CMS Status"
    echo "=============="
    echo ""
    echo "Root directory: $ROE_ROOT"
    echo "App directory: $APP_DIR"
    echo "Site directory: $SITE_DIR"
    echo "Current version: $(cat "$ROE_ROOT/VERSION" 2>/dev/null | grep 'version:' | cut -d'"' -f2 || echo 'unknown')"
    echo ""
    
    if [ -f "$APP_DIR/tmp/pids/server.pid" ]; then
        PID=$(cat "$APP_DIR/tmp/pids/server.pid")
        if ps -p "$PID" > /dev/null 2>&1; then
            log_success "Server is running (PID: $PID)"
        else
            log_error "PID file exists but process not running"
        fi
    else
        log_warning "Server is not running"
    fi
}

# Check for updates
cmd_update() {
    log_info "Checking for updates..."
    cd "$APP_DIR"
    "$APP_DIR/bin/rails" runner "puts RoeUpdater::VersionChecker.check_for_updates.inspect"
}

# Main command handler
case "${1:-}" in
    start)
        shift
        cmd_start "$@"
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        shift
        cmd_restart "$@"
        ;;
    console)
        cmd_console
        ;;
    status)
        cmd_status
        ;;
    update)
        cmd_update
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        echo ""
        usage
        exit 1
        ;;
esac
