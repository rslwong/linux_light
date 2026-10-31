LINUX LIGHT - QUICK REFERENCE                       (q closes this window)
=============================

Login: user "user", password "live" (sudo works without a password).

KEYBOARD (Super = the Windows key)
----------------------------------
  Super+p               run a program (dmenu: type a name, Enter)
  Super+Shift+Enter     terminal (Tilix; Ctrl+Alt+R / Ctrl+Alt+D split it)
  Super+w               web browser (Firefox)
  Super+e               file manager
  Super+n               Wi-Fi / network setup in a terminal (nmtui)
  Super+v               volume mixer (pavucontrol)
  Super+Shift+t         touchpad settings
  Super+Shift+p         screens: mirror / extend to an external screen
  Super+F1              this help
  Super+Shift+l         lock the screen
  Super+Shift+e         power menu: lock, suspend, reboot, power off
  Print                 screenshot into ~/Pictures
  Volume / brightness keys work as usual.

  Super+Shift+c         close the focused window
  Super+j / Super+k     focus next / previous window
  Super+Enter           move the focused window to the big (master) area
  Super+h / Super+l     shrink / grow the master area
  Super+t / f / m       layout: tiled / floating / monocle (one window)
  Super+Shift+space     toggle floating for the focused window
  Super+1..9            switch to workspace (tag) 1..9
  Super+Shift+1..9      move the focused window to workspace 1..9
  Super+0               show all workspaces at once
  Super+b               hide / show the top bar
  Super+drag (left)     move a window,  Super+drag (right) resize it
  Super+Shift+q         restart the graphical session

  Full dwm reference: man dwm

NETWORK AND WI-FI
-----------------
  Click the network icon at the top right to pick a Wi-Fi network.
  Without the mouse: Super+n opens nmtui ("Activate a connection").
  From a text console (Ctrl+Alt+F2): run  nmtui  or  nmcli device wifi.
  Names ending in .local (printers, other computers, a Raspberry Pi) work
  through mDNS; this machine answers as linux-light.local. To list what is
  announced on the network:  avahi-browse -at

SOUND
-----
  Volume icon at the top right: scroll to change volume, middle-click to
  mute, left-click to choose the output device. Super+v opens the full
  mixer. In a terminal, alsamixer and wpctl are available too.

PERSISTENCE
-----------
  When the stick has a partition (or Ventoy file) labelled "persistence",
  everything you change - installed packages, settings, files in /home -
  is kept across reboots. The boot menu entry "without persistence" starts
  a clean system that forgets everything at shutdown.
  Check whether persistence is active:  grep persistence /proc/mounts

EXTERNAL SCREENS (HDMI, DisplayPort, USB-C)
--------------------------------------------
  Plug in a screen and it is added to the right of the laptop screen
  ("extend"). To change that, press Super+Shift+p (or the laptop's display
  key) and pick:
    Extend: external screen on the right / on the left
    Mirror: same picture on both screens
    External screen only / Laptop screen only
    Arrange screens (arandr)...   resolution, rotation, any position
  The layout is remembered for each screen: plug the same projector or
  monitor in again and it comes back the way you left it (with
  persistence, also after a reboot). Unplugging returns to the laptop
  screen; windows from the external screen move over.
  If a screen you plugged in is not picked up, Super+Shift+p detects it.
  On many laptops the Fn display key sends Super+P, which opens the
  program launcher instead; Super+Shift+p always works.

  With two screens, each has its own bar and workspaces:
    Super+, / Super+.               focus the other screen
    Super+Shift+, / Super+Shift+.   move the window to the other screen

TOUCHPAD
--------
  These gestures are on by default:

    tap with one finger            left click
    tap with two fingers           right click
    tap with three fingers         middle click (pastes selected text)
    slide two fingers              scroll
    slide three fingers            drag, like on macOS: put three fingers on
                                   a window title, a file or selected text
                                   and slide them to move it. You can lift
                                   the fingers and put them down again
                                   within a moment to continue the drag.
    tap, then touch and slide      drag with one finger
    press the touchpad down        click

  To change them, press Super+Shift+t (or run linux-light-touchpad in a
  terminal). In the menu:

    Up / Down         pick a setting
    Enter             change it: on/off settings switch at once, the
                      others open a list where Enter picks the entry
    Esc, or Tab and Enter on "Done"   close the menu

  The menu turns tap to click, two-finger right click, natural (macOS
  style) scrolling and "ignore the touchpad while typing" on or off, lets
  you drag with three or four fingers (or not at all), and sets the
  pointer speed from -1.0 (slowest) to 1.0 (fastest). Changes apply at
  once and, with persistence, are kept for the next boot. "Reset to
  defaults" brings back the settings listed above.

INSTALLING SOFTWARE
-------------------
  sudo apt update
  sudo apt install <package>
  The kernel is held back on purpose (it is booted from the ISO image);
  rebuild the ISO to get a newer one.

  After moving to a newer Linux Light image, if you had installed
  packages: apt does not know yet about packages the new image added
  (they work, but get no updates). List them, then sudo apt install them
  (leave out any you removed yourself):
    img=/run/live/rootfs/filesystem.squashfs
    comm -23 <(sed -n 's/^Package: //p' $img/var/lib/dpkg/status | sort) \
             <(sed -n 's/^Package: //p' /var/lib/dpkg/status | sort)

CUSTOMISING DWM
---------------
  dwm is configured at compile time:
    sudoedit /usr/local/src/dwm/config.h
    sudo linux-light-rebuild-dwm
  then press Super+Shift+q. Programs to start with the session go into
  ~/.config/linux-light/autostart (an executable shell script).

EXAMPLE: GOOGLE CHROME ON SUPER+W
---------------------------------
  Super+w starts "x-www-browser", Debian's default browser setting, so no
  recompiling is needed. Chrome's .deb makes itself the default:
    sudo apt install ./google-chrome-stable_current_amd64.deb
    sudo update-alternatives --config x-www-browser   (check / switch back)

  To give Chrome its own key instead (Firefox stays on Super+w):
  1. sudoedit /usr/local/src/dwm/config.h and add
       next to the other commands:
         static const char *chromecmd[] = { "google-chrome-stable", NULL };
       in keys[], next to the Super+w line (this makes it Super+Shift+w):
         { MODKEY|ShiftMask, XK_w, spawn, {.v = chromecmd } },
     (or change browsercmd to "google-chrome-stable" to move Super+w)
  2. sudo linux-light-rebuild-dwm      (add --purge to remove the compiler)
  3. Super+Shift+q to restart the session (open windows close).
  With persistence, all of this survives reboots.
