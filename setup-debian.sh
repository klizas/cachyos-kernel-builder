#!/usr/bin/env bash
# Run this on the Debian build machine to set everything up:
#   1. Build the Docker image
#   2. Install a systemd timer for periodic builds
#   3. Install a systemd service to serve the repo over HTTP
#
# Usage: sudo ./setup-debian.sh [repo-port]
#   repo-port: HTTP port for the pacman repo (default: 8765)

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0 [port]" >&2
    exit 1
fi

BUILD_USER="${SUDO_USER:?Run with sudo, not as root directly}"
REPO_PORT="${1:-8765}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

echo "==> Setting up kernel builder for user '$BUILD_USER'..."

# --- 1. Build Docker image ---
echo "==> Building Docker image..."
sudo -u "$BUILD_USER" docker build -t cachyos-kernel-builder "$SCRIPT_DIR"

# --- 2. Create output directory ---
mkdir -p "$OUTPUT_DIR"
chown "$BUILD_USER":"$BUILD_USER" "$OUTPUT_DIR"

# --- 3. Install systemd timer for periodic builds ---
cat > /etc/systemd/system/kernel-builder.service << EOF
[Unit]
Description=Build custom CachyOS kernel
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
User=$BUILD_USER
ExecStart=$SCRIPT_DIR/build.sh
TimeoutStartSec=7200
EOF

cat > /etc/systemd/system/kernel-builder.timer << EOF
[Unit]
Description=Check for new CachyOS kernel every 6 hours

[Timer]
OnCalendar=*-*-* 00/6:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- 4. Install systemd service for HTTP repo ---
cat > /etc/systemd/system/kernel-repo.service << EOF
[Unit]
Description=Serve custom kernel pacman repo
After=network.target

[Service]
Type=simple
User=$BUILD_USER
WorkingDirectory=$OUTPUT_DIR
ExecStart=/usr/bin/python3 -m http.server $REPO_PORT --bind 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# --- 5. Enable and start ---
systemctl daemon-reload
systemctl enable --now kernel-repo.service
systemctl enable --now kernel-builder.timer

echo ""
echo "==> Setup complete!"
echo ""
echo "    Build timer:  systemctl status kernel-builder.timer"
echo "    Repo server:  http://$(hostname -I | awk '{print $1}'):$REPO_PORT"
echo "    Manual build: sudo -u $BUILD_USER $SCRIPT_DIR/build.sh --force"
echo ""
echo "    On CachyOS, add to /etc/pacman.conf ABOVE [cachyos-v3]:"
echo ""
echo "      [custom-kernel]"
echo "      SigLevel = Optional TrustAll"
echo "      Server = http://$(hostname -I | awk '{print $1}'):$REPO_PORT"
