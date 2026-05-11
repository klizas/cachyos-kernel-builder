#!/usr/bin/env bash
# Serve the package repo over HTTP so the CachyOS machine can use it
# as a pacman repo.
#
# Usage: ./serve-repo.sh [port]
#   Default port: 8765
#
# On the CachyOS machine, add to /etc/pacman.conf (ABOVE [cachyos-v3]):
#
#   [custom-kernel]
#   SigLevel = Optional TrustAll
#   Server = http://<debian-host-ip>:8765

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-8765}"
REPO_DIR="$SCRIPT_DIR/output"

if [[ ! -d "$REPO_DIR" ]]; then
    echo "ERROR: No output directory. Run build.sh first." >&2
    exit 1
fi

echo "Serving pacman repo from $REPO_DIR on port $PORT"
echo ""
echo "Add to /etc/pacman.conf on CachyOS (ABOVE [cachyos-v3]):"
echo ""
echo "  [custom-kernel]"
echo "  SigLevel = Optional TrustAll"
echo "  Server = http://$(hostname -I | awk '{print $1}'):$PORT"
echo ""

cd "$REPO_DIR"
python3 -m http.server "$PORT" --bind 0.0.0.0
