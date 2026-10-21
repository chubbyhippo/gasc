#!/bin/sh
set -eu

REPO_RAW="https://raw.githubusercontent.com/chubbyhippo/gasc/refs/heads/main"
install_hint="Your distro may not package kanata. Install one directly:
      cargo install kanata
  or drop a release binary from https://github.com/jtroo/kanata/releases
  into ~/.local/bin and chmod +x it."

main() {
    locate_source
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/kanata"
    unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    udev_rule="/etc/udev/rules.d/99-input.rules"
    user="$(id -un)"

    [ "$(id -u)" -ne 0 ] || {
        echo "run as your normal user, not root — this script sudos only the steps that need it" >&2
        exit 1
    }

    [ -d /run/systemd/system ] || command -v systemctl >/dev/null 2>&1 || {
        echo "no systemd found — this script only supports systemd Linux" >&2
        exit 1
    }

    kanata_bin="$(command -v kanata || true)"
    [ -n "$kanata_bin" ] || {
        echo "kanata not found on PATH." >&2
        echo "  $install_hint" >&2
        exit 1
    }

    getent group uinput >/dev/null 2>&1 || sudo groupadd --system uinput
    sudo usermod -aG input,uinput "$user"
    sudo modprobe uinput

    tmp_rule="$(mktemp)"
    fetch "systemd/99-input.rules" "$tmp_rule"
    sudo install -m 644 -o root -g root "$tmp_rule" "$udev_rule"
    rm -f "$tmp_rule"
    if command -v udevadm >/dev/null 2>&1; then
        sudo udevadm control --reload-rules
        sudo udevadm trigger
    else
        echo "warning: no udevadm — reboot, or make sure /dev/uinput is 0660 root:uinput" >&2
    fi
    echo "installed $udev_rule"

    mkdir -p "$config_dir"
    tmp_kbd="$(mktemp)"
    fetch "kanata.kbd" "$tmp_kbd"
    "$kanata_bin" --cfg "$tmp_kbd" --check
    install -m 644 "$tmp_kbd" "$config_dir/kanata.kbd"
    rm -f "$tmp_kbd"
    echo "installed $config_dir/kanata.kbd"

    mkdir -p "$unit_dir"
    tmp_unit="$(mktemp)"
    fetch "systemd/kanata.service" "$tmp_unit"
    sed "s|^ExecStart=/usr/bin/kanata |ExecStart=$kanata_bin |" "$tmp_unit" > "$unit_dir/kanata.service"
    rm -f "$tmp_unit"
    systemctl --user daemon-reload
    systemctl --user enable kanata.service
    echo "installed $unit_dir/kanata.service"

    if id -nG | tr ' ' '\n' | grep -qx uinput; then
        systemctl --user restart kanata.service
        echo "done — test: hold a (left Gui) or j (right Ctrl) past 300ms"
        echo "logs: journalctl --user -u kanata -f"
    else
        echo ""
        echo "the uinput group is not active in this login session yet."
        echo "log out and back in, then:  systemctl --user start kanata.service"
    fi
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

${__SOURCED__:+return}

main "$@"
