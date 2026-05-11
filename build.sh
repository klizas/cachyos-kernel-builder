#!/usr/bin/env bash
# Build a custom CachyOS kernel with T2 MacBook patches and apple-bce-drv.
# Runs the build inside a Docker container with an Arch Linux toolchain.
#
# Usage: ./build.sh [--force]
#   --force: rebuild even if the latest version was already built

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKER_IMAGE="cachyos-kernel-builder"
PKGBUILD_REPO="https://github.com/CachyOS/linux-cachyos.git"
OUTPUT_DIR="$SCRIPT_DIR/output"
STATE_DIR="$SCRIPT_DIR/.state"
VARIANT="linux-cachyos"  # the PKGBUILD subdirectory to use
BCE_REPO="https://github.com/klizas/apple-bce-drv.git"
BCE_BRANCH="aur"
PATCHES_REPO="https://github.com/klizas/t2-kernel-patches.git"
PATCHES_BRANCH="main"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "$OUTPUT_DIR" "$STATE_DIR"

# --- Check for latest CachyOS kernel version ---
echo "==> Checking for latest CachyOS kernel version..."
PKGBUILD_RAW_URL="https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/${VARIANT}/PKGBUILD"
REMOTE_PKGBUILD=$(curl -fsSL "$PKGBUILD_RAW_URL") || {
    echo "ERROR: Failed to fetch PKGBUILD from $PKGBUILD_RAW_URL" >&2
    exit 1
}

# Resolve kernel version from PKGBUILD variables
_major=$(grep '^_major=' <<< "$REMOTE_PKGBUILD" | cut -d= -f2)
_minor=$(grep '^_minor=' <<< "$REMOTE_PKGBUILD" | cut -d= -f2)
_pkgrel=$(grep '^pkgrel=' <<< "$REMOTE_PKGBUILD" | cut -d= -f2)
REMOTE_VERSION="${_major}.${_minor}-${_pkgrel}"
LAST_BUILT_VERSION=$(cat "$STATE_DIR/last-built-version" 2>/dev/null || echo "")

if [[ "$REMOTE_VERSION" == "$LAST_BUILT_VERSION" && "$FORCE" -eq 0 ]]; then
    echo "==> Already built kernel $REMOTE_VERSION. Use --force to rebuild."
    exit 0
fi

echo "==> New kernel version: ${REMOTE_VERSION} (last built: ${LAST_BUILT_VERSION:-none})"

# --- Ensure Docker image exists ---
if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
    echo "==> Building Docker image (first time only)..."
    docker build -t "$DOCKER_IMAGE" "$SCRIPT_DIR"
fi

# --- Prepare build context ---
BUILD_CONTEXT="$SCRIPT_DIR/.build-context"
rm -rf "$BUILD_CONTEXT"
mkdir -p "$BUILD_CONTEXT"

# Clone the PKGBUILD repo (shallow)
echo "==> Fetching CachyOS PKGBUILD..."
git clone --depth=1 "$PKGBUILD_REPO" "$BUILD_CONTEXT/linux-cachyos"

# Copy the PKGBUILD variant we want
cp -a "$BUILD_CONTEXT/linux-cachyos/$VARIANT/"* "$BUILD_CONTEXT/"

# Fetch latest T2 kernel patches from upstream
echo "==> Cloning T2 kernel patches from $PATCHES_REPO ($PATCHES_BRANCH)..."
PATCHES_CLONE="$BUILD_CONTEXT/.patches-src"
git clone --depth=1 --branch "$PATCHES_BRANCH" "$PATCHES_REPO" "$PATCHES_CLONE"
PATCHES_COMMIT=$(git -C "$PATCHES_CLONE" rev-parse --short HEAD)
echo "    t2-kernel-patches @ $PATCHES_COMMIT"
cp "$PATCHES_CLONE/"*.patch "$BUILD_CONTEXT/"
rm -rf "$PATCHES_CLONE"

# Fetch latest apple-bce-drv from upstream and bundle as tarball
echo "==> Cloning apple-bce-drv from $BCE_REPO ($BCE_BRANCH)..."
git clone --depth=1 --branch "$BCE_BRANCH" "$BCE_REPO" "$BUILD_CONTEXT/apple-bce-drv"
BCE_COMMIT=$(git -C "$BUILD_CONTEXT/apple-bce-drv" rev-parse --short HEAD)
echo "    apple-bce-drv @ $BCE_COMMIT"
rm -rf "$BUILD_CONTEXT/apple-bce-drv/.git"
tar -czf "$BUILD_CONTEXT/apple-bce-drv.tar.gz" \
    -C "$BUILD_CONTEXT" apple-bce-drv
rm -rf "$BUILD_CONTEXT/apple-bce-drv"

# Customize the PKGBUILD
bash "$SCRIPT_DIR/customize-pkgbuild.sh" "$BUILD_CONTEXT"

echo "==> Building kernel ${REMOTE_VERSION}..."

# --- Run the build in Docker ---
echo "==> Starting Docker build..."
if ! docker run --rm \
    -v "$BUILD_CONTEXT:/home/builder/build" \
    -v "$OUTPUT_DIR:/home/builder/output" \
    -e MAKEFLAGS="-j$(nproc)" \
    "$DOCKER_IMAGE" \
    bash -c '
        cd /home/builder/build
        sudo chown -R builder: .
        makepkg -s --noconfirm --skipinteg 2>&1 | tee /home/builder/build.log
        cp -v *.pkg.tar.zst /home/builder/output/
    '; then
    echo "ERROR: Build failed. Check .build-context/build.log" >&2
    exit 1
fi

# --- Clean old packages (keep only current + previous version) ---
echo "==> Cleaning old packages..."
for prefix in linux-cachyos-t2-headers linux-cachyos-t2; do
    old_pkgs=()
    while IFS= read -r f; do
        old_pkgs+=("$f")
    done < <(ls -1t "$OUTPUT_DIR/${prefix}"-[0-9]*.pkg.tar.zst 2>/dev/null | tail -n +3)
    if [[ ${#old_pkgs[@]} -gt 0 ]]; then
        echo "    Removing ${#old_pkgs[@]} old ${prefix} package(s)..."
        rm -f "${old_pkgs[@]}"
    fi
done

# --- Update repo database (add only newly-built packages) ---
# NOTE: We must NOT glob all packages — repo-add processes them in filename
# order, and older versions (e.g. 6.19.9) sort AFTER newer ones (e.g. 6.19.10)
# alphabetically, causing the older version to overwrite the newer entry.
echo "==> Updating pacman repo database..."
NEW_PKGS=("$OUTPUT_DIR"/linux-cachyos-t2-"${REMOTE_VERSION}"-*.pkg.tar.zst
           "$OUTPUT_DIR"/linux-cachyos-t2-headers-"${REMOTE_VERSION}"-*.pkg.tar.zst)

REPO_ADD_LOG="$STATE_DIR/repo-add.log"
run_repo_add() {
    if command -v repo-add &>/dev/null; then
        repo-add "$OUTPUT_DIR/custom-kernel.db.tar.zst" "${NEW_PKGS[@]}" 2>&1
    else
        # Build the package list for inside the container
        local pkg_args=""
        for pkg in "${NEW_PKGS[@]}"; do
            pkg_args+=" /repo/$(basename "$pkg")"
        done
        docker run --rm -v "$OUTPUT_DIR:/repo" "$DOCKER_IMAGE" \
            bash -c "repo-add /repo/custom-kernel.db.tar.zst $pkg_args" 2>&1
    fi
}

if run_repo_add | tee "$REPO_ADD_LOG"; then
    echo "==> Repo database updated."
else
    echo "ERROR: repo-add failed. See $REPO_ADD_LOG" >&2
    exit 1
fi

# --- Verify new version is in database ---
echo "==> Verifying database contains ${REMOTE_VERSION}..."
DB_CONTENTS=$(tar -tf "$OUTPUT_DIR/custom-kernel.db.tar.zst" 2>/dev/null || true)
if echo "$DB_CONTENTS" | grep -q "linux-cachyos-t2-${REMOTE_VERSION}"; then
    echo "    Verified: linux-cachyos-t2-${REMOTE_VERSION} is in the database."
else
    echo "ERROR: linux-cachyos-t2-${REMOTE_VERSION} NOT found in database after repo-add!" >&2
    echo "    Database contents:" >&2
    echo "$DB_CONTENTS" | grep -E '^[^/]+/$' >&2
    exit 1
fi

# --- Record successful build ---
echo "$REMOTE_VERSION" > "$STATE_DIR/last-built-version"

echo ""
echo "==> Build complete!"
echo "    Packages in: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR"/*.pkg.tar.zst 2>/dev/null
echo ""
echo "    To install on CachyOS:"
echo "      scp $OUTPUT_DIR/*.pkg.tar.zst your-machine:/tmp/"
echo "      sudo pacman -U /tmp/linux-cachyos-*.pkg.tar.zst"
