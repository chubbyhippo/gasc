#!/bin/sh
set -eu

REPO_RAW="https://raw.githubusercontent.com/chubbyhippo/gasc/refs/heads/main"

main() {
    locate_source
    home_dir="$(windows_home)"
    startup="$home_dir/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
    [ -d "$home_dir" ] || die "Windows home not found at $home_dir"
    echo "windows home: $home_dir"

    tmp_kbd="$(mktemp)"
    fetch "kanata.kbd" "$tmp_kbd"

    exe="$(windows_kanata || true)"
    if [ -n "$exe" ]; then
        "$exe" --cfg "$(to_native "$tmp_kbd")" --check
    else
        echo "warning: kanata.exe not found — skipping --check. Install it from" >&2
        echo "  https://github.com/jtroo/kanata/releases and put it on your PATH." >&2
    fi

    install -m 644 "$tmp_kbd" "$home_dir/kanata.kbd"
    rm -f "$tmp_kbd"
    echo "installed $home_dir/kanata.kbd"

    tmp_bat="$(mktemp)"
    tmp_bat_crlf="$(mktemp)"
    fetch "wins/katana.bat" "$tmp_bat"
    sed -e 's/\r$//' -e 's/$/\r/' "$tmp_bat" > "$tmp_bat_crlf"
    mkdir -p "$startup"
    install -m 644 "$tmp_bat_crlf" "$startup/kanata.bat"
    rm -f "$tmp_bat" "$tmp_bat_crlf"
    echo "installed $startup/kanata.bat"

    echo ""
    echo "done — run that kanata.bat once (or log off and on) to start kanata."
    echo "test: hold a (LWin) or j (RCtrl) past 300ms"
}

locate_source() {
    local_dir=""
    case "$0" in
        */*) candidate="${0%/*}" ;;
        *)   candidate="." ;;
    esac
    candidate="$(cd "$candidate" 2>/dev/null && pwd || printf '')"
    [ -n "$candidate" ] && [ -r "$candidate/../kanata.kbd" ] \
        && local_dir="$(cd "$candidate/.." && pwd)" || true
}

fetch() {
    if [ -n "$local_dir" ] && [ -r "$local_dir/$1" ]; then
        cp "$local_dir/$1" "$2"
    else
        curl -fsSL "$REPO_RAW/$1" -o "$2"
    fi
}

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
    [ -r /proc/sys/kernel/osrelease ] || return 1
    tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/osrelease | grep -q 'microsoft\|wsl'
}

windows_home() {
    if is_wsl; then
        raw="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')"
        [ -n "$raw" ] || die "could not read %USERPROFILE% from cmd.exe"
        wslpath -u "$raw"
    elif command -v cygpath >/dev/null 2>&1 && [ -n "${USERPROFILE:-}" ]; then
        cygpath -u "$USERPROFILE"
    else
        printf '%s' "${USERPROFILE:-$HOME}"
    fi
}

windows_kanata() {
    command -v kanata.exe 2>/dev/null && return 0
    is_wsl || return 1
    raw="$(cmd.exe /c 'where kanata.exe' 2>/dev/null | head -n 1 | tr -d '\r\n')"
    [ -n "$raw" ] || return 1
    wslpath -u "$raw"
}

to_native() {
    if is_wsl; then
        wslpath -w "$1"
    elif command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

die() { echo "error: $*" >&2; exit 1; }

${__SOURCED__:+return}

main "$@"
