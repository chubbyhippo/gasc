#!/bin/sh
set -eu

REPO_RAW="https://raw.githubusercontent.com/chubbyhippo/gasc/refs/heads/main"

main() {
    locate_source
    if [ -n "$local_dir" ]; then
        kbd_path="$local_dir/kanata.kbd"
    else
        dest="${GASC_DEST:-$HOME/.config/gasc}"
        mkdir -p "$dest"
        curl -fsSL "$REPO_RAW/kanata.kbd" -o "$dest/kanata.kbd"
        kbd_path="$dest/kanata.kbd"
        echo "downloaded $kbd_path"
    fi

    cat <<EOF

Guix is declarative — there is nothing to install imperatively.
(gnu services desktop) already exports kanata-service-type.

Add to your operating-system:

    (use-modules (gnu services desktop)
                 (guix gexp))

    (services
     (cons* (service kanata-service-type
                     (kanata-configuration
                      (keymaps (list (local-file "$kbd_path")))))
            %desktop-services))

Then:  sudo guix system reconfigure /etc/config.scm
EOF
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

${__SOURCED__:+return}

main "$@"
