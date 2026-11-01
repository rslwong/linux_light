# Linux Light

A portable, lightweight Linux desktop on a USB stick. It's a Debian 13 (trixie)
live system with the **dwm** window manager, **persistent storage** and as
much Wi-Fi, network, Bluetooth and sound hardware support as Debian offers.
Write it to a dedicated stick or drop it onto a **Ventoy** stick, and
**install it** on a laptop's SSD like any other distribution.

| | |
|---|---|
| Base | Debian 13 "trixie" (amd64), Linux 6.12, live-boot/live-config |
| Hardware support | all of Debian's firmware for PC hardware (Intel, Realtek, Atheros, Broadcom, MediaTek and older Wi-Fi; Bluetooth; Intel SOF and other sound; AMD, Intel and NVIDIA GPUs; NICs) plus CPU microcode, on Debian's kernel with all its drivers |
| Desktop | dwm 6.8 with systray, dmenu, dunst notifications, status bar with network, volume, battery and clock |
| Wi-Fi | `nm-applet` tray icon (NetworkManager), `nmtui` as the text-mode fallback (Super+n), plus ModemManager for USB modems |
| Local network | `<name>.local` names resolve via mDNS (Avahi); the stick is reachable as `linux-light.local` |
| Screens | external screens (HDMI, DisplayPort, USB-C) extend automatically when plugged in; Super+Shift+p switches between extend, mirror, external only and laptop only; layouts are remembered per monitor |
| Sound | PipeWire (PulseAudio and ALSA compatible), `pasystray` volume tray icon, `pavucontrol` mixer, `alsamixer`, Bluetooth audio via `blueman` |
| Apps | Tilix (terminal), Firefox ESR, PCManFM, Mousepad, Xarchiver, GParted, arandr |
| Fonts | DejaVu and Liberation, plus Noto CJK for Chinese (Simplified and Traditional), Japanese and Korean |
| Packages | `apt` with the full Debian archive (main, contrib, non-free, non-free-firmware) and security updates |
| Boot | BIOS and UEFI, including Secure Boot (Debian's signed shim, GRUB and kernel) |
| Persistence | partition or Ventoy file labelled `persistence`, 32 GB by default, size configurable |
| Installer | Calamares (Super+Shift+i on the stick): erase a disk, install alongside Windows, manual partitions, optional encryption; works offline |
| Login | live system: automatic; installed system: LightDM login screen, optional auto-login |

On the stick, login is automatic: the user is `user`, the password is `live`,
and `sudo` works without a password.

## 1. Build the ISO

Needs `podman` (or `docker`), about 10 GB of free disk space and an internet
connection. No root access is needed with podman.

```sh
./build.sh
```

The result is `out/linux-light-amd64.iso` (about 1.3 GB, plus a `.sha256`
and a package list). The first build downloads about 1 GB of packages and
takes roughly 15 to 30 minutes. The packages are cached in `build/cache`, so
later builds are faster.

| Command | What it does |
|---|---|
| `./build.sh` | clean build of the ISO |
| `./build.sh resume` | continue a build that was interrupted |
| `./build.sh clean` | delete the build tree but keep the package cache |
| `./build.sh purge` | delete the build tree and the package cache |

The build runs as (namespaced) root inside the container, so some files under
`build/` belong to sub-UIDs. Remove them with `./build.sh purge` rather than
`rm -rf build`.

### Settings

Edit [`settings.conf`](settings.conf) to change the Debian release, mirror,
hostname, user name, locale, keyboard layout, time zone and the default
persistence size. Each value can also be overridden for one run:

```sh
LIVE_KEYBOARD=de LIVE_LOCALE=de_DE.UTF-8 LIVE_TIMEZONE=Europe/Berlin ./build.sh
```

## 2. Put it on a USB stick

### Option A: dedicated stick with a persistence partition

```sh
lsblk -d -o NAME,SIZE,MODEL,TRAN          # find the stick, e.g. /dev/sdb
sudo tools/make-usb.sh /dev/sdb           # 32 GB persistence (the default)
sudo tools/make-usb.sh -s 64G /dev/sdb    # choose the size
sudo tools/make-usb.sh -s max /dev/sdb    # use all the space left on the stick
```

The script writes the ISO, then adds an ext4 partition labelled `persistence`
behind it with a `persistence.conf` containing `/ union`. It asks for
confirmation before it erases the stick (`-y` skips the question) and refuses
to touch the disk that holds the running system. The stick needs to be larger
than the ISO plus the persistence size.

Given a file name instead of a device, `make-usb.sh` builds a complete disk
image without root, which you can write later with `dd` or any image writer:

```sh
tools/make-usb.sh -s 8G linux-light-usb.img
```

### Option B: Ventoy

```sh
tools/make-ventoy-persistence.sh --ventoy /media/$USER/Ventoy          # 32 GB
tools/make-ventoy-persistence.sh -s 16G --ventoy /media/$USER/Ventoy   # 16 GB
```

This copies the ISO to the Ventoy drive, creates
`persistence/linux-light.dat` there and registers the pair in
`ventoy/ventoy.json` with `"autosel": 1`, so Ventoy uses that file
automatically when you boot the ISO. Other entries in `ventoy.json` are
kept. The Ventoy data partition must be exFAT, NTFS or ext4: FAT32
cannot hold files of 4 GB or more. Creating the file on exFAT writes its
whole size once, so a 32 GB file takes around 18 minutes on a USB 3 SSD
(longer on a slow stick). Without `--ventoy` the script only
creates the file (by default `out/linux-light-persistence.dat`) and prints
the `ventoy.json` snippet to add yourself.

### Option C: no persistence

Write `out/linux-light-amd64.iso` with `dd`, GNOME Disks, balenaEtcher,
Rufus (in DD mode) or similar, or copy it onto a Ventoy stick as it is.

### Persistence size

The size is set in this order, from lowest to highest priority:

1. `PERSISTENCE_SIZE` in `settings.conf` (default `32G`)
2. the `PERSISTENCE_SIZE` environment variable
3. the `-s`/`--size` option of `make-usb.sh` or `make-ventoy-persistence.sh`

Sizes accept `K`, `M`, `G` and `T` suffixes (`32G`, `8192M`). `make-usb.sh`
also accepts `max`.

To enlarge an existing persistence store later without losing its contents,
do it from another Linux system while the stick is not booted:

```sh
# Ventoy file: add 16 GB
truncate -s +16G /media/$USER/Ventoy/persistence/linux-light.dat
e2fsck -f /media/$USER/Ventoy/persistence/linux-light.dat
resize2fs /media/$USER/Ventoy/persistence/linux-light.dat

# Persistence partition (partition 4) on a stick: grow it into free space behind it
sudo growpart /dev/sdb 4        # from the cloud-guest-utils package, or use GParted
sudo e2fsck -f /dev/sdb4 && sudo resize2fs /dev/sdb4
```

### Updating to a newly built ISO

- **Ventoy:** run `tools/make-ventoy-persistence.sh --ventoy /media/$USER/Ventoy`
  again. It replaces the ISO and keeps the existing persistence file.
- **Dedicated stick:** `make-usb.sh` recreates the whole stick, which also
  erases the persistence partition, so copy your files off it first.

The persistence store records changes relative to the image it was used
with. After switching to a new image, files in `/home` carry over fine, but
system changes (installed packages, edits in `/etc`) can clash with the new
image. If something misbehaves, start with a fresh persistence store.

If you installed packages with apt, the persistence store also holds apt's
package database from the old image. Everything keeps working, but apt does
not know about packages the newer image added, so they get no updates. After
booting the new image, list those packages and record them with apt:

```sh
img=/run/live/rootfs/filesystem.squashfs
comm -23 <(sed -n 's/^Package: //p' $img/var/lib/dpkg/status | sort) \
         <(sed -n 's/^Package: //p' /var/lib/dpkg/status | sort)
sudo apt install <the packages listed>
```

Packages you removed yourself also appear in that list; leave those out.

## 3. Using it

The boot menu has four entries:

| Entry | Use it for |
|---|---|
| **Linux Light** (default, starts after 5 s) | normal use; uses the persistence store if there is one |
| without persistence | a clean session that forgets everything at shutdown |
| safe graphics | machines where the normal entry gives a black screen (`nomodeset`) |
| copy to RAM | loads the whole system into memory (about 2 GB RAM needed) so the stick can be removed |

**Wi-Fi.** Click the network icon at the top right and pick a network.
Without a mouse, press **Super+n** for `nmtui`, or switch to a text console
with Ctrl+Alt+F2 and run `nmtui`.

**Sound.** The speaker icon at the top right changes the volume (scroll),
mutes (middle-click) and picks the output device (left-click). **Super+v**
opens the full mixer. The volume keys work too.

**External screens.** A screen plugged into HDMI, DisplayPort or USB-C is
added to the right of the laptop screen. **Super+Shift+p** (or the laptop's
display key) opens a menu to extend to the right or left, mirror, use only
one of the screens, or open arandr for resolution, rotation and free
placement. Whatever layout you use is remembered for that monitor (told apart
by its EDID) and restored when you plug it in again; unplugging returns to
the laptop screen. With two screens each has its own dwm bar; Super+, and
Super+. move the focus between them, Super+Shift+, and Super+Shift+. move
windows. If a screen you plugged in is not picked up, Super+Shift+p detects
it. On many laptops the Fn display key sends Super+P, which opens the program
launcher instead; Super+Shift+p always works.

**Touchpad.** Tap to click, two-finger tap for a right click, three-finger
tap for a middle click, two-finger scrolling and macOS-style three-finger
dragging are on by default. For three-finger drag, put three fingers on a
window title, a file or selected text and slide them; lift and put them down
again within a moment to continue the same drag. **Super+Shift+t** opens a
text menu (arrow keys and Enter) to switch each of these on or off, drag
with four fingers instead, set the pointer speed, and turn on natural
scrolling or "ignore the touchpad while typing". Changes apply immediately
and are kept with persistence.

**Software.** `sudo apt update && sudo apt install <package>`. With
persistence, installed packages survive reboots. On the stick the kernel
package is held on purpose, because the kernel is always booted from the
ISO; rebuild the ISO to update it. An installed system updates its kernel
normally.

**Keys** (Super is the Windows key; **Super+F1** shows the full list):

| Key | Action |
|---|---|
| Super+p | run a program (dmenu) |
| Super+Shift+Enter | terminal (Tilix) |
| Super+w / Super+e | web browser / file manager |
| Super+n / Super+v | network setup (nmtui) / volume mixer |
| Super+Shift+t | touchpad settings |
| Super+Shift+p | screens: extend / mirror / external only / laptop only |
| Super+Shift+i | install Linux Light on this computer (on the stick) |
| Super+Shift+c | close window |
| Super+j / Super+k | focus next / previous window |
| Super+1…9, Super+Shift+1…9 | switch to / move window to workspace |
| Super+t / f / m | tiled / floating / monocle layout |
| Super+Shift+l | lock screen |
| Super+Shift+e | power menu (lock, suspend, restart session, reboot, power off) |
| Print | screenshot to `~/Pictures` |

To check whether persistence is active, run `grep persistence /proc/mounts`
in a terminal. It lists the persistence partition (or Ventoy file) when one is
in use.

## 4. Installing on a disk (SSD)

Boot the stick (or the ISO in a VM) and press **Super+Shift+i**; the welcome
notification on the stick mentions it too. The installer (Calamares, as on
Debian's own live images) asks for:

1. language and time zone,
2. keyboard layout,
3. the disk: erase a whole disk, install alongside Windows or another
   system (it shrinks a partition to make room), replace a partition, or
   partition by hand; any of them can be encrypted,
4. your name, user name, computer name and password, and whether to log in
   automatically.

It then copies the same system that runs on the stick, without the
live-system parts (live-boot, live-config) and without the installer itself,
installs GRUB for UEFI (with Secure Boot support) or legacy BIOS, and asks to
restart. The installed system starts with a LightDM login screen, has the
same desktop, keys and tools, and gets kernel updates with
`sudo apt upgrade`. Its apt sources are Linux Light's (main, contrib,
non-free, non-free-firmware).

Notes:

- No internet is needed: the GRUB packages the installer adds come from a
  small package pool on the ISO.
- What the installer copies is the clean image. Changes made on the stick
  (persistence) are not copied, except saved Wi-Fi networks.
- Erasing a disk cannot be undone; back up first. To dual boot with Windows,
  turn off BitLocker and Fast Startup in Windows beforehand.
- In the computer's own boot menu (F12, F9, Esc, ... at power-on) the
  installed system is listed as "linux" (or "debian" if the firmware had to
  recreate the entry). Secure Boot can stay on.

## Customizing

| What | Where |
|---|---|
| Installed packages | `lb/config/package-lists/*.list.chroot` |
| Files added to the image | `lb/config/includes.chroot_after_packages/` |
| Session start-up (applets, status bar) | `.../usr/local/bin/linux-light-session`, `linux-light-status` |
| dwm keys, colors, rules | `.../usr/local/src/dwm/config.h` |
| Boot menu | `lb/config/bootloaders/grub-pc/grub.cfg` |
| Screen switching and hotplug | `.../usr/local/bin/linux-light-display` |
| Touchpad defaults / settings menu | `.../etc/X11/xorg.conf.d/40-linux-light-touchpad.conf`, `.../usr/local/bin/linux-light-touchpad` |
| Patched Debian packages | `packages/<source package>/*.patch` |
| Installer steps, branding, packages removed after install | `.../etc/calamares/` (based on Debian's `calamares-settings-debian`) |
| Login screen | `.../etc/lightdm/lightdm.conf.d/`, `.../usr/share/lightdm/lightdm-gtk-greeter.conf.d/` |
| Build-time scripts | `lb/config/hooks/normal/*.hook.chroot` |
| live-build options | `lb/auto/config` |

dwm is compiled from source during the build because Debian's dwm package has
no system tray. The source in `/usr/local/src/dwm` is dwm 6.8 with the
[systray patch](https://dwm.suckless.org/patches/systray/), ported to 6.8
and extended with `_NET_SYSTEM_TRAY_COLORS` so that GTK draws symbolic tray
icons in the bar's text color (see `systray.diff` there). On a running
system, edit `config.h`, run `sudo linux-light-rebuild-dwm` and press
Super+Shift+q. Commands to start with the session go into
`~/.config/linux-light/autostart`, which must be executable.

### Example: open Google Chrome with Super+w

Super+w runs `x-www-browser`, Debian's default-browser setting, so no
recompiling is needed. Chrome's `.deb` registers itself there with a higher
priority than Firefox, so after installing it Super+w opens Chrome:

```sh
sudo apt install ./google-chrome-stable_current_amd64.deb
sudo update-alternatives --config x-www-browser   # check, or switch back to Firefox
```

To give Chrome its own key instead (and keep Firefox on Super+w), change dwm:

1. `sudoedit /usr/local/src/dwm/config.h` and add

   ```c
   /* next to the other commands */
   static const char *chromecmd[] = { "google-chrome-stable", NULL };

   /* in keys[], next to the Super+w line: Super+Shift+w */
   { MODKEY|ShiftMask,             XK_w,      spawn,          {.v = chromecmd } },
   ```

   or point Super+w itself at Chrome:
   `static const char *browsercmd[] = { "google-chrome-stable", NULL };`
2. `sudo linux-light-rebuild-dwm` (installs the compiler, about 70 MB; add
   `--purge` to remove it again afterwards).
3. Press Super+Shift+q to restart the session; open windows close.

With persistence, Chrome, the browser choice and the rebuilt dwm all survive
reboots. A rebuilt dwm and its `config.h` stay in the persistence store, so
they keep overriding the image's dwm after you move to a newer ISO.

## Testing

### In a virtual machine

```sh
tools/test-vm.sh                                   # UEFI, boots the ISO as a USB stick
tools/test-vm.sh --bios                            # legacy BIOS
tools/test-vm.sh --secure-boot                     # UEFI with Secure Boot enforced
tools/make-ventoy-persistence.sh -s 4G -o /tmp/p.dat
tools/test-vm.sh --persistence /tmp/p.dat          # with persistence
tools/make-usb.sh -y -s 4G /tmp/usb.img && tools/test-vm.sh /tmp/usb.img
tools/test-vm.sh --disk /tmp/ssd.qcow2              # try the installer on an empty 20 GB disk
tools/test-vm.sh --no-stick --disk /tmp/ssd.qcow2   # then boot the installed system
```

### Automated tests

These run on the build machine, without a VM or root:

```sh
python3 tests/test-display.py         # screen switching and hotplug, against a fake xrandr
python3 tests/test-touchpad-menu.py   # touchpad menu driven with keystrokes (needs whiptail)
```

## Project layout

```
build.sh                  build entry point (runs live-build in a container)
settings.conf             build and persistence settings
Containerfile             build environment (Debian trixie + live-build)
scripts/lb-build.sh       live-build driver, runs inside the container
scripts/build-packages.sh rebuilds the Debian packages in packages/ with their patches
packages/                 local patches to Debian packages (3-finger drag)
lb/auto/config            live-build configuration
lb/config/                package lists, hooks, boot menu, files for the image
lb/pool/                  packages the installer adds to an installed system (GRUB)
tools/make-usb.sh         write a stick with a persistence partition
tools/make-ventoy-persistence.sh   persistence file for Ventoy
tools/test-vm.sh          boot the image in QEMU
tests/                    automated tests for the screen and touchpad scripts
```

## Notes

- Drivers that have to be compiled for the running kernel are not
  included: the proprietary NVIDIA driver and Broadcom's `wl`
  (`broadcom-sta-dkms`). The open `nouveau` and `b43`/`brcmsmac` drivers are
  included. With persistence you can still install those packages together
  with `linux-headers-$(uname -r)`.
- The ISO takes about 1.3 GB; the rest of the stick is available for
  persistence.
- After live-build finishes, `scripts/lb-build.sh` re-masters the ISO with
  xorriso so that partition 1 holds the ISO filesystem and the EFI partition
  is appended. With live-build's own GRUB layout, live-boot would not look
  for a persistence partition on the stick it booted from.
- Three-finger drag is built into libinput (since 1.27), but Debian's X
  touchpad driver (xserver-xorg-input-libinput 1.5.0, also the latest
  upstream release) has no setting for it. The build rebuilds that package
  with `packages/xserver-xorg-input-libinput/3fg-drag.patch`, which adds an
  Xorg option `ThreeFingerDrag` and an xinput property
  `libinput 3-Finger Drag Enabled` (0, 3 or 4 fingers). The rebuilt package
  is versioned `+linuxlight1`, so apt keeps it unless Debian ships a newer
  upstream version.
- The installer configuration is Debian's (`calamares-settings-debian`)
  with these changes: Linux Light branding; Linux Light's apt sources
  instead of Debian's defaults; a swap choice (none, small, suspend, file;
  default small: as much as RAM, at most 8 GB and 10% of the disk); and a
  last step, `/usr/local/sbin/linux-light-finish-install`, that lifts the
  live system's kernel hold, removes the installer and sets up the boot
  loader for later GRUB updates (below).
- The GRUB packages for the target (`lb/pool/*.list`) go into a package
  pool on the ISO, which `scripts/lb-build.sh` builds after live-build
  (live-build's own `*.list.binary` needs DNS inside the chroot, which it
  does not have at that stage).
- UEFI installs put shim and GRUB in `EFI/linux` (named after the first word
  of GRUB_DISTRIBUTOR, which is where Debian's GRUB updates reinstall to)
  and in the removable-media path `EFI/BOOT`, so the disk still boots with
  Secure Boot if the firmware loses its boot entry. Debian's signed GRUB
  reads `EFI/debian/grub.cfg` first, so a copy of the small redirect file
  goes there unless another Debian already has one. BIOS installs record
  the disk for grub-pc's updates.
- Persistence stores made with an older image keep that image's
  `/etc/passwd`. Packages that create system users in their install scripts
  (Avahi, LightDM) are therefore also declared in
  `/usr/lib/sysusers.d/linux-light.conf`, and systemd-sysusers runs on every
  boot to add missing users.
- Firmware for old Broadcom b43 Wi-Fi cards is not redistributable; Debian's
  `firmware-b43-installer` downloads it (checksum-verified) during the build.
