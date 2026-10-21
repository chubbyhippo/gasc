#!/bin/sh
set -eu

REPO_RAW="https://raw.githubusercontent.com/chubbyhippo/gasc/refs/heads/main"

tcc_client_allowed() {
    db="$1"
    service="$2"
    client="$3"
    [ -n "$client" ] && [ -r "$db" ] || return 1
    command -v sqlite3 >/dev/null 2>&1 || return 1
    val="$(sqlite3 "$db" "SELECT auth_value FROM access WHERE service='$service' AND client='$client' LIMIT 1;" 2>/dev/null || true)"
    [ "$val" = 2 ]
}

tcc_service_allowed() {
    service="$1"
    shift
    db="/Library/Application Support/com.apple.TCC/TCC.db"
    for client in "$@"; do
        tcc_client_allowed "$db" "$service" "$client" && return 0
    done
    return 1
}

resolved_bin() {
    bin="$1"
    dir="$(cd "$(dirname "$bin")" && pwd -P)"
    printf '%s/%s\n' "$dir" "$(basename "$bin")"
}

print_permission_guide() {
    bin="$1"
    real="$2"
    echo ""
    echo "kanata needs macOS Input Monitoring and Accessibility."
    echo "System Settings -> Privacy & Security -> add these paths to both lists:"
    echo "  $bin"
    [ "$real" = "$bin" ] || echo "  $real"
    echo "unlock -> + -> Cmd+Shift+G -> paste the directory -> select kanata -> toggle on"
    echo "remove any stale kanata row first (Homebrew upgrades change the Cellar path)"
    echo "then:  sudo launchctl kickstart -k system/dev.kanata.kanata"
    echo "re-run this script after granting, or check /var/log/kanata.log"
}

check_macos_permissions() {
    bin="$1"
    real="$(resolved_bin "$bin")"
    missing=0
    tcc_service_allowed kTCCServiceListenEvent "$bin" "$real" || {
        echo "missing: Input Monitoring"
        missing=1
    }
    tcc_service_allowed kTCCServiceAccessibility "$bin" "$real" || {
        echo "missing: Accessibility"
        missing=1
    }
    [ "$missing" -eq 0 ] || {
        print_permission_guide "$bin" "$real"
        return 1
    }
    echo "Input Monitoring and Accessibility granted for $real"
    return 0
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

main() {
    locate_source
    daemons="/Library/LaunchDaemons"
    kanata_plist="dev.kanata.kanata.plist"
    vhid_plist="org.pqrs.Karabiner-VirtualHIDDevice-Daemon.plist"
    driver_ver="6.2.0"
    driver_sha="9e8c46239f0748161241e42444857901224e5c82f5b58a1731df4c70bf0736a8"
    manager="/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

    [ "$(id -u)" -eq 0 ] || {
        echo "must run as root:  curl -fsSL $REPO_RAW/mac/setup.sh | sudo sh" >&2
        exit 1
    }

    if systemextensionsctl list 2>/dev/null | grep "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice" | grep -q "activated enabled"; then
        echo "Karabiner driver already activated"
    else
        if [ ! -x "$manager" ]; then
            pkg_dir="$(mktemp -d)"
            pkg="$pkg_dir/Karabiner-DriverKit-VirtualHIDDevice-$driver_ver.pkg"
            curl -fsSL "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v$driver_ver/Karabiner-DriverKit-VirtualHIDDevice-$driver_ver.pkg" -o "$pkg"
            echo "$driver_sha  $pkg" | shasum -a 256 -c - >/dev/null
            installer -pkg "$pkg" -target /
            rm -rf "$pkg_dir"
        fi
        "$manager" forceActivate
        echo ""
        echo "driver installed — one manual step Apple requires:"
        echo "  System Settings -> General -> Login Items & Extensions -> Driver Extensions -> enable Karabiner-DriverKit-VirtualHIDDevice"
        echo "then re-run this script to finish:  curl -fsSL $REPO_RAW/mac/setup.sh | sudo sh"
        exit 0
    fi

    kanata_bin=""
    for c in /opt/homebrew/bin/kanata /usr/local/bin/kanata; do
        if [ -x "$c" ]; then kanata_bin="$c"; break; fi
    done
    [ -n "$kanata_bin" ] || {
        echo "kanata binary not found — install it first (brew install kanata), then re-run" >&2
        exit 1
    }

    mkdir -p /etc/kanata
    tmp_kbd="$(mktemp /tmp/gasc.kbd.XXXXXX)"
    fetch "kanata.kbd" "$tmp_kbd"
    "$kanata_bin" --cfg "$tmp_kbd" --check
    chmod 644 "$tmp_kbd"
    mv "$tmp_kbd" /etc/kanata/gasc.kbd
    echo "installed /etc/kanata/gasc.kbd"

    if launchctl print system 2>/dev/null | grep -q "Karabiner-VirtualHIDDevice-Daemon"; then
        echo "VirtualHIDDevice daemon already managed — skipping its LaunchDaemon"
    else
        fetch "mac/$vhid_plist" "$daemons/$vhid_plist"
        chown root:wheel "$daemons/$vhid_plist"
        launchctl bootstrap system "$daemons/$vhid_plist"
        echo "installed VirtualHIDDevice daemon"
    fi

    tmp_plist="$(mktemp)"
    fetch "mac/$kanata_plist" "$tmp_plist"
    sed "s|/usr/local/bin/kanata|$kanata_bin|" "$tmp_plist" > "$daemons/$kanata_plist"
    rm -f "$tmp_plist"
    chown root:wheel "$daemons/$kanata_plist"
    launchctl bootout system/dev.kanata.kanata 2>/dev/null || true
    launchctl bootstrap system "$daemons/$kanata_plist"

    if check_macos_permissions "$kanata_bin"; then
        echo "done — test: hold a (left Cmd) or j (right Ctrl) past 300ms   (logs: /var/log/kanata.log)"
    else
        echo "installed, but kanata will crash-loop until those permissions are granted"
        exit 0
    fi
}

${__SOURCED__:+return}

main "$@"
