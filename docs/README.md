# MagiskOnWSALocal — Multi-Distro Fork

> A fork of [LSPosed/MagiskOnWSALocal](https://github.com/LSPosed/MagiskOnWSALocal) that runs on **any** Linux distribution, not just Debian-family ones.

The project officially supports Debian, Ubuntu, openSUSE Tumbleweed, and Arch. This fork rewrites the dependency installer so it works on Fedora, RHEL, CentOS, Rocky, Alma, Oracle, Amazon Linux, Gentoo, Alpine, Void, Solus, and any other distro shipping a recognized package manager — with no other changes to the build pipeline.

> ⚠️ Magisk on WSA is no longer available from Microsoft after March 5, 2025. See the [upstream notice](https://learn.microsoft.com/en-us/windows/android/wsa/) for context. This fork still works for building images locally.

## What's different from upstream

The only file with meaningful changes is `scripts/install_deps.sh`. Everything else (`build.sh`, `run.sh`, the Python scripts, the binaries) is identical to upstream.

- **Distro detection now uses `/etc/os-release`** (the freedesktop standard) instead of scanning for legacy `/etc/debian_version`-style files. Falls back to the legacy files, and then to probing `$PATH`, so even unknown distros get a fair shot.
- **Fedora and the rest of the RHEL family are first-class.** The upstream script had `yum` support commented out; this fork enables `dnf5` → `dnf` → `yum` (whichever is present) for Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux, Oracle Linux, Amazon Linux, and openEuler.
- **Fixed a latent bug in the dnf/yum path.** Upstream used `check-update`, which exits with status 100 when updates are available — that would have been treated as a failure even if dnf had been wired up. This fork uses `makecache` instead.
- **Added package-name translation** for every supported package manager (e.g. `whiptail` → `newt` on Fedora, `libnewt` on Arch, `dialog` on openSUSE; `p7zip-full` → `p7zip-plugins` on Fedora, `p7zip` on Arch/Alpine/etc).
- **Added more package managers:** `xbps-install` (Void), `eopkg` (Solus), and broadened the family matching to cover Manjaro, EndeavourOS, Artix, Garuda, Linux Mint, Pop!\_OS, postmarketOS, and openSUSE Leap/SLES.

## Supported distros

| Family   | Examples                                                       | Package manager        |
|----------|----------------------------------------------------------------|------------------------|
| Debian   | Debian, Ubuntu, Linux Mint, Pop!\_OS, elementary, Kali, MX     | `apt-get`              |
| Red Hat  | Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux, Oracle, Amazon  | `dnf5` / `dnf` / `yum` |
| Arch     | Arch, Manjaro, EndeavourOS, Artix, Garuda                      | `pacman`               |
| SUSE     | openSUSE Tumbleweed, openSUSE Leap, SLES                       | `zypper`               |
| Gentoo   | Gentoo                                                         | `emerge`               |
| Alpine   | Alpine, postmarketOS                                           | `apk`                  |
| Void     | Void Linux                                                     | `xbps-install`         |
| Solus    | Solus                                                          | `eopkg`                |

If your distro isn't listed but ships one of the package managers above, the script will detect it via the generic fallback. If detection fails entirely, the script prints the dependency list and exits so you can install them manually.

Architectures: **x86_64** and **aarch64**. Python ≥ **3.7.2**.

## Usage

```bash
git clone https://github.com/<your-username>/MagiskOnWSALocal.git
cd MagiskOnWSALocal/scripts
./run.sh
```

That's it — `run.sh` calls `install_deps.sh`, which detects your distro and installs everything it needs through your native package manager. Then you'll get the standard interactive TUI for picking arch, root solution, GApps, etc.

### Tested on

- [x] Fedora 40, 41
- [x] Ubuntu 22.04, 24.04
- [x] Debian 12
- [ ] Arch (works in upstream, untouched here — should still work)
- [ ] openSUSE Tumbleweed (same)

> Tick the boxes as you confirm each distro. PRs welcome for any distro not on the list.

## Features (unchanged from upstream)

- Integrate Magisk and GApps in a few clicks
- Keep each build up to date
- Support both ARM64 and x64
- Support MindTheGapps
- Remove Amazon Appstore
- Fix VPN dialog not showing (using LSPosed's [VpnDialogs](https://github.com/LSPosed/VpnDialogs))
- Add device administration feature
- Unattended installation

For the full feature list, screenshots, FAQ, and credits, see the [upstream README](https://github.com/LSPosed/MagiskOnWSALocal/blob/main/docs/README.md).

## Credits

All actual WSA-building work belongs to the [LSPosed contributors](https://github.com/LSPosed/MagiskOnWSALocal/graphs/contributors). This fork is just a packaging-layer change to make the existing build pipeline reachable from more distros.

## License

GNU AGPL v3, same as upstream. See [LICENSE](LICENSE).
