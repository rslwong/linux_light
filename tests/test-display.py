#!/usr/bin/python3
"""Scenario test for linux-light-display (screen switching and hotplug).

Runs the real script against tests/bin/xrandr, a fake that keeps simulated
screens in a JSON file. No X server or root needed:  python3 tests/test-display.py
"""
import importlib.machinery, importlib.util, json, os, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "lb", "config", "includes.chroot_after_packages",
                      "usr", "local", "bin", "linux-light-display")
tmp = tempfile.mkdtemp()
os.environ["FAKE_XRANDR"] = os.path.join(tmp, "state.json")
os.environ["XDG_CONFIG_HOME"] = os.path.join(tmp, "config")
os.environ["PATH"] = os.path.join(HERE, "bin") + ":" + os.environ["PATH"]

# The script lives in the image's source tree: don't leave a __pycache__ there.
sys.dont_write_bytecode = True

notes = []
loader = importlib.machinery.SourceFileLoader("lld", SCRIPT)
spec = importlib.util.spec_from_loader("lld", loader)
lld = importlib.util.module_from_spec(spec)
loader.exec_module(lld)
lld.time.sleep = lambda s: None
lld.notify = lambda title, body="": notes.append(title + " | " + body)

LAPTOP = {"name": "eDP-1", "connected": True, "edid": "a1b2", "primary": True,
          "modes": [[1920, 1080], [1600, 900], [1280, 720], [1024, 768]],
          "preferred": [1920, 1080], "geometry": [1920, 1080, 0, 0], "mode": [1920, 1080]}
TV = {"name": "HDMI-1", "connected": False, "edid": "c3d4", "geometry": None,
      "modes": [[3840, 2160], [1920, 1080], [1280, 720], [1024, 768]], "preferred": [3840, 2160]}
DP = {"name": "DP-1", "connected": False, "edid": "", "geometry": None, "modes": [], "preferred": None}

def state():
    return json.load(open(os.environ["FAKE_XRANDR"]))

def setstate(st):
    json.dump(st, open(os.environ["FAKE_XRANDR"], "w"))

def plug(name, edid=None, modes=None, preferred=None, connected=True):
    st = state()
    for o in st["outputs"]:
        if o["name"] == name:
            o["connected"] = connected
            if edid:
                o["edid"] = edid
            if modes:
                o["modes"], o["preferred"] = modes, preferred
    setstate(st)

def geo():
    return {o["name"]: (tuple(o["geometry"]) if o["geometry"] else None, o.get("primary", False))
            for o in state()["outputs"] if o["connected"] or o["geometry"]}

fails = 0
def check(label, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(f"{'OK  ' if ok else 'FAIL'} {label}" + ("" if ok else f"\n       got  {got}\n       want {want}"))

setstate({"outputs": [LAPTOP, TV, DP]})
w = lld.Watcher()

w.step()
check("start, laptop only: unchanged", geo(), {"eDP-1": ((1920, 1080, 0, 0), True)})
check("no notification at start", notes, [])

plug("HDMI-1")
w.step()
check("plug TV: extended to the right at its preferred 4K mode",
      geo(), {"eDP-1": ((1920, 1080, 0, 0), True), "HDMI-1": ((3840, 2160, 1920, 0), False)})
check("plug TV: notification", notes[-1], "Screen connected: HDMI-1 | Extended to the right. Super+Shift+p to change.")

lld.apply("mirror")
w.step()
check("menu Mirror: both 1920x1080 at 0,0 (largest common mode)",
      geo(), {"eDP-1": ((1920, 1080, 0, 0), True), "HDMI-1": ((1920, 1080, 0, 0), False)})
check("mirror remembered for laptop+TV", len(lld.load()), 1)

plug("HDMI-1", connected=False)
w.step()
check("unplug TV: laptop only, stale HDMI output switched off", geo(), {"eDP-1": ((1920, 1080, 0, 0), True)})
check("unplug: notification", notes[-1], "External screen disconnected | Back to the laptop screen.")

plug("HDMI-1")
w.step()
check("replug same TV: mirror restored",
      geo(), {"eDP-1": ((1920, 1080, 0, 0), True), "HDMI-1": ((1920, 1080, 0, 0), False)})
check("replug: notification says mirrored", notes[-1], "Screen connected: HDMI-1 | Mirrored. Super+Shift+p to change.")

plug("HDMI-1", connected=False); w.step()
plug("HDMI-1", edid="e5f6", modes=[[2560, 1440], [1920, 1080], [1024, 768]], preferred=[2560, 1440])
w.step()
check("different monitor, same port: new screen gets extend-right",
      geo(), {"eDP-1": ((1920, 1080, 0, 0), True), "HDMI-1": ((2560, 1440, 1920, 0), False)})

lld.apply("extend-left")
w.step()
check("menu Extend left: monitor left of the laptop, laptop stays primary",
      geo(), {"HDMI-1": ((2560, 1440, 0, 0), False), "eDP-1": ((1920, 1080, 2560, 0), True)})

# arandr-style change: rotate the monitor to portrait, put it to the right.
lld.xrandr(["--output", "eDP-1", "--mode", "1920x1080", "--pos", "0x0", "--rotate", "normal", "--primary",
            "--output", "HDMI-1", "--mode", "2560x1440", "--pos", "1920x0", "--rotate", "left"])
w.step()
plug("HDMI-1", connected=False); w.step()
plug("HDMI-1"); w.step()
check("layout made by another tool (rotated monitor) is remembered and restored",
      geo(), {"eDP-1": ((1920, 1080, 0, 0), True), "HDMI-1": ((1440, 2560, 1920, 0), False)})

lld.apply("external")
w.step()
check("menu External only: laptop screen off, monitor primary", geo(),
      {"eDP-1": (None, False), "HDMI-1": ((2560, 1440, 0, 0), True)})
plug("HDMI-1", connected=False); w.step()
check("unplugging while external-only brings the laptop screen back", geo(), {"eDP-1": ((1920, 1080, 0, 0), True)})

check("menu options without external screen", lld.layout(lld.query(), "external"), None)
lld.apply("laptop")
check("Laptop only with nothing plugged in is harmless", geo(), {"eDP-1": ((1920, 1080, 0, 0), True)})

# Safety: turning every screen off is not remembered (the laptop screen comes
# back on), and a stored all-off layout (e.g. an old file) is not restored.
lld.xrandr(["--output", "eDP-1", "--off"])
w.step()
check("all screens off is not remembered", any(a == "--off" for a in lld.load().get(w.fp, [])), False)
check("all screens off: laptop screen switched back on", geo(), {"eDP-1": ((1920, 1080, 0, 0), True)})
store = lld.load(); store[w.fp] = ["--output", "eDP-1", "--off"]; lld.save(store)
w.store = store
plug("HDMI-1"); w.step(); plug("HDMI-1", connected=False); w.step()
check("a stored all-off layout is not restored", geo(), {"eDP-1": ((1920, 1080, 0, 0), True)})

# Mirror never goes above the laptop panel's own resolution, even if both
# list bigger modes (as virtual machines do).
st = state()
st["outputs"][0]["modes"] = [[4096, 2160], [1920, 1080], [1280, 720]]
setstate(st)
plug("HDMI-1", edid="c3d4", modes=[[4096, 2160], [3840, 2160], [1920, 1080]], preferred=[3840, 2160])
w.step()
lld.apply("mirror")
check("mirror capped at the laptop's native 1920x1080", geo(),
      {"eDP-1": ((1920, 1080, 0, 0), True), "HDMI-1": ((1920, 1080, 0, 0), False)})

print(f"\n{'ALL PASSED' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
