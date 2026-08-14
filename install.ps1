# Roe one-line installer for Windows.
#
#   irm https://codeberg.org/waotw/roe/raw/branch/development/install.ps1 | iex
#
# The short go-roe.com/install.ps1 and /install URLs aren't serving yet, so
# both URLs below point at the repo. Swap them back once those are live —
# nothing else in this script needs to change.
#
# Roe is a Linux application. On Windows it runs inside WSL — Microsoft's
# built-in Linux environment — where it behaves exactly as it does on a Mac.
# This script's whole job is to get WSL in place and then hand off to the
# normal Unix installer (install.sh) inside it. It deliberately installs
# nothing Roe-specific on the Windows side.
#
# Run it twice on a machine that has never had WSL: once to install WSL
# (Windows requires a restart), once after rebooting to install Roe. That
# restart is Microsoft's, not ours; there's no way to avoid it.
#
# Overrides (environment variables):
#   ROE_WSL_DISTRO   distro to use/install     (default: Ubuntu)
#   ROE_INSTALL_URL  passed through to install.sh for a specific .zip

$ErrorActionPreference = 'Stop'

$InstallUrl   = 'https://codeberg.org/waotw/roe/raw/branch/development/install.sh'
$BootstrapUrl = 'https://codeberg.org/waotw/roe/raw/branch/development/install.ps1'
$Distro     = if ($env:ROE_WSL_DISTRO) { $env:ROE_WSL_DISTRO } else { 'Ubuntu' }

function Say  { param($m) Write-Host $m }
function Ok   { param($m) Write-Host "[/] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Die  { param($m) Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# wsl.exe writes UTF-16LE, which PowerShell reads as text peppered with null
# bytes — every -match and -eq against its output fails for no visible reason.
# This is the single most common way a WSL script breaks, so normalise once
# here and use Invoke-Wsl everywhere below.
function Invoke-Wsl {
    param([string[]]$Arguments)
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        return (& wsl.exe @Arguments 2>&1 | Out-String)
    } finally {
        [Console]::OutputEncoding = $previous
    }
}

function Test-WslPresent {
    $null -ne (Get-Command wsl.exe -ErrorAction SilentlyContinue)
}

# A distro is usable only once it's installed AND initialised (a user account
# exists). `wsl -l -q` lists installed distros; running `true` inside proves
# it actually boots, which is what we need before piping an installer to it.
function Test-DistroReady {
    if (-not (Test-WslPresent)) { return $false }

    $list = Invoke-Wsl @('-l', '-q')
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($list)) { return $false }

    $names = $list -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($names.Count -eq 0) { return $false }

    Invoke-Wsl @('-e', 'true') | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Say ''
Say 'Installing Roe for Windows'
Say ''

# --- 1. Make sure WSL exists ------------------------------------------------

if (-not (Test-DistroReady)) {
    Say 'Roe needs WSL, the Linux environment built into Windows.'
    Say ''

    if (-not (Test-Admin)) {
        Die @"
Installing WSL needs Administrator.

  Close this window, then:
    1. Press the Windows key and type: powershell
    2. Right-click 'Windows PowerShell' and choose 'Run as administrator'
    3. Run this command again:

       irm $BootstrapUrl | iex
"@
    }

    # wsl.exe ships with Windows 10 build 19041 and later. If it's missing, the
    # machine predates WSL2 and no amount of installing will help — say so
    # plainly rather than failing on a command that isn't there.
    if (-not (Test-WslPresent)) {
        $build = [System.Environment]::OSVersion.Version.Build
        Die @"
This version of Windows doesn't include WSL (build $build).

  Roe needs Windows 10 version 2004 (build 19041) or newer, or Windows 11.

  Update Windows, then run this command again.
"@
    }

    # One command covers both cases: no WSL features enabled yet, and WSL
    # enabled but with no usable distro.
    Say "Installing WSL with $Distro. This takes a few minutes."
    Say ''
    & wsl.exe --install -d $Distro

    Say ''
    Warn 'Windows needs to restart before Linux can start.'
    Say ''
    Say '  1. Restart your computer.'
    Say '  2. If you are asked to create a Linux username and password, do that first.'
    Say '     (Any username works. Write the password down — Linux asks for it'
    Say '      when installing tools.)'
    Say '  3. Open PowerShell as Administrator and run this command again:'
    Say ''
    Say "     irm $BootstrapUrl | iex"
    Say ''
    Say 'That second run installs Roe itself.'
    exit 0
}

Ok 'WSL is ready'

# --- 2. Install Roe inside WSL ----------------------------------------------

Say 'Installing Roe inside Linux...'
Say ''

# Install into the Linux home directory, never /mnt/c: Windows drives can't
# store Unix permissions (Roe's launcher would never become executable) and
# they hide file changes from Roe's watcher, so content silently stops syncing.
# install.sh enforces this too — belt and braces, since this is the mistake
# that makes a working Roe look broken.
$command = 'cd ~ && curl -fsSL ' + $InstallUrl + ' | bash'
if ($env:ROE_INSTALL_URL) {
    $command = "export ROE_INSTALL_URL='$($env:ROE_INSTALL_URL)'; " + $command
}

# No Invoke-Wsl here: the Roe installer is interactive and its output should
# stream straight to the console rather than being captured.
& wsl.exe -e bash -lc $command
$installExit = $LASTEXITCODE

Say ''
if ($installExit -ne 0) {
    Die @"
The Roe installer didn't finish.

  Open the Ubuntu app from your Start menu and try again:

      cd ~ && curl -fsSL $InstallUrl | bash
"@
}

Ok 'Roe is installed'
Say ''
Say 'To start Roe later, open the Ubuntu app from your Start menu and run:'
Say ''
Say '    cd ~/roe-<version> && ./roe.sh start'
Say ''
Say 'Your files are visible from Windows at:'
Say ''
Say "    \\wsl`$\$Distro\home\"
Say ''
