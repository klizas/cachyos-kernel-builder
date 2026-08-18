# cachyos-kernel-builder

Builds the [CachyOS kernel](https://github.com/CachyOS/linux-cachyos) (`linux-cachyos` variant) with T2 Mac support, packaged as `linux-cachyos-t2` + `linux-cachyos-t2-headers`. Built daily by GitHub Actions and published as a pacman repo on the rolling [`latest` release](https://github.com/klizas/cachyos-kernel-builder/releases/tag/latest).

## What it changes vs stock linux-cachyos

- Applies T2 patches from [klizas/t2-kernel-patches](https://github.com/klizas/t2-kernel-patches): amdgpu mclk override, brcmfmac suspend fix, Touch Bar suspend/resume.
- Ships out-of-tree apple-bce from [klizas/apple-bce-drv](https://github.com/klizas/apple-bce-drv) (`aur` branch) as `extramodules/apple-bce.ko`. Disables every in-tree BCE driver CachyOS enables: `CONFIG_APPLE_BCE` (<= 7.1, `drivers/staging/apple-bce`) and `CONFIG_T2BCE_DMA/CORE/VHCI/AUDIO` (>= 7.2, `drivers/staging/t2bce`, claims the same PCI device `106b:1801`). `prepare()` fails the build if any of them survives config reconciliation.
- Target: `x86_64_v3` (matches `cachyos-v3`).

## Install on CachyOS

Add to `/etc/pacman.conf`:

```ini
[custom-kernel]
SigLevel = Optional TrustAll
Server = https://github.com/klizas/cachyos-kernel-builder/releases/download/latest
```

Then:

```sh
sudo pacman -Sy
sudo pacman -S linux-cachyos-t2 linux-cachyos-t2-headers
```

