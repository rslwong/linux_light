#!/usr/bin/python3
"""Drives the linux-light-touchpad menu with real keystrokes and checks the
settings file it saves. Runs outside X (settings are only saved, not applied)
and needs whiptail:  python3 tests/test-touchpad-menu.py
"""
import os, pty, select, shutil, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "lb", "config", "includes.chroot_after_packages",
                      "usr", "local", "bin", "linux-light-touchpad")
DOWN, UP, ENTER, ESC = "\x1b[B", "\x1b[A", "\r", "\x1b"
DEFAULTS = "TAP=1\nTAP_RIGHT=1\nDRAG3=3\nSPEED=0\nNATURAL=0\nDWT=1\n"

if not shutil.which("whiptail"):
    sys.exit("whiptail is needed (apt install whiptail)")

def run(keys, initial=None):
    """Type keys into the menu (slowly: whiptail drops keys typed while it
    starts up) and return (settings file, everything shown on screen)."""
    home = tempfile.mkdtemp()
    conf = os.path.join(home, ".config", "linux-light", "touchpad")
    if initial:
        os.makedirs(os.path.dirname(conf))
        open(conf, "w").write(initial)
    env = {"PATH": os.environ["PATH"], "HOME": home, "TERM": "xterm", "LANG": "C.UTF-8"}
    pid, fd = pty.fork()
    if pid == 0:
        os.execve("/bin/bash", ["bash", SCRIPT], env)
    screen = b""
    def drain(seconds):
        nonlocal screen
        end = time.time() + seconds
        while time.time() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try:
                    screen += os.read(fd, 65536)
                except OSError:
                    return
    drain(1.0)
    for k in keys:
        os.write(fd, k.encode())
        drain(1.5)
    drain(1.5)
    os.waitpid(pid, 0)
    return (open(conf).read() if os.path.exists(conf) else None), screen

fails = 0
def check(label, ok):
    global fails
    fails += not ok
    print(f"{'OK  ' if ok else 'FAIL'} {label}")

# Tap off; speed 0 -> 0.5; (highlight stays on speed) up to 3-finger drag ->
# four fingers; natural scrolling on; Esc closes the menu.
conf, screen = run([ENTER,
                    DOWN, DOWN, DOWN, ENTER, DOWN, DOWN, ENTER,
                    UP, ENTER, DOWN, ENTER,
                    DOWN, DOWN, ENTER,
                    ESC])
check("changes made in the menu are saved",
      conf == "TAP=0\nTAP_RIGHT=1\nDRAG3=4\nSPEED=0.5\nNATURAL=1\nDWT=1\n")
check("speed list marks the current value and shows the names",
      b"(current)" in screen and b"faster" in screen)

conf, screen = run([DOWN] * 6 + [ENTER, ESC],
                   initial="TAP=0\nTAP_RIGHT=0\nDRAG3=0\nSPEED=-1.0\nNATURAL=1\nDWT=0\n")
check("saved settings are shown", b"-1.0, slowest" in screen)
check("Reset to defaults restores the defaults", conf == DEFAULTS)

print(f"\n{'ALL PASSED' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
