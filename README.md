# cachyos-kernel-builder

Builds the [CachyOS kernel](https://github.com/CachyOS/linux-cachyos) (`linux-cachyos` variant) with T2 Mac support, packaged as `linux-cachyos-t2` + `linux-cachyos-t2-headers`.
Built daily by GitHub Actions and published as a pacman repo on the rolling [`latest` release](https://github.com/klizas/cachyos-kernel-builder/releases/tag/latest).

## What it changes vs stock linux-cachyos

- Applies patches from [klizas/t2-kernel-patches](https://github.com/klizas/t2-kernel-patches)
- Ships [klizas/apple-bce-drv](https://github.com/klizas/apple-bce-drv) (`aur` branch) as replacement for `t2bce`.

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
