#!/usr/bin/env bash
# Modifies the CachyOS linux-cachyos PKGBUILD to include custom patches
# and the apple-bce-drv module.
#
# Usage: ./customize-pkgbuild.sh <pkgbuild-dir>
#   pkgbuild-dir: directory containing the PKGBUILD and config files

set -euo pipefail

PKGBUILD_DIR="$1"
PKGBUILD="$PKGBUILD_DIR/PKGBUILD"

if [[ ! -f "$PKGBUILD" ]]; then
    echo "ERROR: PKGBUILD not found at $PKGBUILD" >&2
    exit 1
fi

echo "==> Customizing PKGBUILD..."

# --- 1. Force x86_64_v3 target (matches cachyos-v3 repo) ---
sed -i 's/^: "${_processor_opt:=}"/: "${_processor_opt:=generic_v3}"/' "$PKGBUILD"

# --- 1b. Rename package to linux-cachyos-t2 (installs alongside stock) ---
# Override _pkgsuffix after it's computed so pkgbase becomes linux-cachyos-t2.
# This gives a separate uname -r, separate /boot entries, separate GRUB entry.
sed -i 's/^pkgbase="linux-\$_pkgsuffix"/pkgbase="linux-cachyos-t2"/' "$PKGBUILD"
# Remove replaces=() so it doesn't try to replace the stock kernel
sed -i '/replaces=(linux-cachyos-lto)/d' "$PKGBUILD"
sed -i '/replaces=(linux-cachyos-lto-headers)/d' "$PKGBUILD"

# --- 2. Add custom patches to source array ---
# The prepare() function already applies all .patch files from source,
# so we just need to add ours. We append after the source=() block closes.
# We use local file:// URIs since patches are copied into the build dir.
cat >> "$PKGBUILD" << 'PATCH_SOURCES'

# --- Custom T2 MacBook patches ---
source+=(
    "0001-amdgpu-mclk-override.patch"
    "0001-brcmfmac-suspend-fix.patch"
    "0001-touchbar-suspend-resume.patch"
)
sha256sums+=(SKIP SKIP SKIP)
PATCH_SOURCES

# --- 3. Add apple-bce-drv build to build() ---
# Insert apple-bce-drv module build after the main kernel build line
sed -i '/^build() {/,/^}/ {
    /make "${BUILD_FLAGS\[@\]}" -j"\$(nproc)" all/a\
\
    # Build apple-bce-drv module\
    echo "Building apple-bce-drv module..."\
    make "${BUILD_FLAGS[@]}" -C "${srcdir}/${_srcname}" M="${srcdir}/apple-bce-drv" modules
}' "$PKGBUILD"

# --- 4. Add apple-bce-drv install to _package() ---
# Insert after the main modules_install line
sed -i '/_package() {/,/^}/ {
    /rm "\$modulesdir"\/build/i\
\
    # Install apple-bce-drv module\
    echo "Installing apple-bce-drv module..."\
    install -Dm644 "${srcdir}/apple-bce-drv/apple-bce.ko" \\\
        "${modulesdir}/extramodules/apple-bce.ko"\
    zstd --rm -19 "${modulesdir}/extramodules/apple-bce.ko"
}' "$PKGBUILD"

# --- 5. Add apple-bce-drv as a local source ---
# build.sh clones the latest apple-bce-drv from upstream and tarballs it
# into the build context as apple-bce-drv.tar.gz before invoking makepkg.
cat >> "$PKGBUILD" << 'BCE_SOURCE'

# --- apple-bce-drv module source (fetched fresh by build.sh) ---
source+=("apple-bce-drv.tar.gz")
sha256sums+=(SKIP)
BCE_SOURCE

echo "==> PKGBUILD customized successfully"
