#!/usr/bin/env bash
# Cron-friendly wrapper: check for new CachyOS kernel and build if needed.
# Logs to .state/cron.log. Designed to be run by cron/systemd timer.
#
# Example crontab entry (check every 6 hours):
#   0 */6 * * * /path/to/kernel-builder/check-and-build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$SCRIPT_DIR/.state/cron.log"
mkdir -p "$SCRIPT_DIR/.state"

{
    echo "=== $(date -Iseconds) ==="
    "$SCRIPT_DIR/build.sh" 2>&1
    echo "=== done ==="
} >> "$LOG" 2>&1
