#!/usr/bin/env python3
"""Generates the PLACEHOLDER art pack (art/packs/placeholder).

This is a production tool, not game code: the game only loads the PNG/WAV
files listed in manifest.json. Replace any file (same name) or make a new pack
folder with its own manifest.json listing only the ids it overrides.

    python3 tools/make_placeholders.py
Needs Pillow (pip install pillow).
"""
import json, math, os, random, struct, wave
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "packs", "placeholder")
MAP = json.load(open(os.path.join(ROOT, "data", "maps", "meadow.json")))

# Muted palette for the Meadow and the mobs; heroes get saturated colours.
MUTED = {
    "grass": (118, 150, 96), "grass_dark": (92, 120, 76), "path": (178, 160, 120),
    "slime": (96, 140, 190), "slime_dark": (60, 90, 130), "goblin": (120, 140, 80),
    "wood": (130, 96, 64), "stone": (150, 150, 140), "pot": (170, 110, 80),
    "coin": (210, 190, 90), "seed": (160, 140, 90), "mud": (100, 80, 60),
    "bush": (70, 110, 70), "mush": (190, 170, 150), "mush_blue": (90, 120, 200),
    "home": (150, 120, 110), "home_floor": (110, 90, 80), "ink": (40, 36, 44),
    "paper": (226, 218, 196),
}
SATURATED = {"sword": (230, 60, 60), "mage": (150, 70, 230), "thief": (40, 200, 120), "gold": (255, 215, 0)}

manifest = {"_comment": "PLACEHOLDER pack. Every id the game uses. file = image in this folder; frames = horizontal strip; fps; centered; offset [x,y]; ui: margin/padding for 9-slice frames.",
            "sprites": {}, "backgrounds": {}, "ui": {}, "fonts": {}, "sounds": {}}


def save(img, name):
    img.save(os.path.join(OUT, name))
    return name


def blob(w, h, color, frames=1, squash=True, outline=None, eyes=False):
    img = Image.new("RGBA", (w * frames, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for f in range(frames):
        dy = 1 if (squash and f % 2) else 0
        x0 = f * w
        d.ellipse([x0, dy, x0 + w - 1, h - 1], fill=color, outline=outline or tuple(max(0, c - 50) for c in color))
        if eyes:
            ey = h // 2 - 1 + dy
            d.point([(x0 + w // 2 - 2, ey), (x0 + w // 2 + 1, ey)], fill=MUTED["ink"])
    return img


def box(w, h, color, frames=1, outline=None, label_band=None):
    img = Image.new("RGBA", (w * frames, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for f in range(frames):
        x0 = f * w
        d.rectangle([x0, 0, x0 + w - 1, h - 1], fill=color, outline=outline or tuple(max(0, c - 50) for c in color))
        if label_band:
            d.rectangle([x0 + 1, 1, x0 + w - 2, 2], fill=label_band)
    return img


def person(w, h, body, head, frames=2, shiny=None):
    img = Image.new("RGBA", (w * frames, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for f in range(frames):
        x0 = f * w
        bob = f % 2
        hw = w // 2
        d.ellipse([x0 + hw - w // 4, bob, x0 + hw + w // 4, bob + h // 3], fill=head)
        d.rectangle([x0 + 2, h // 3 + bob, x0 + w - 3, h - 2], fill=body)
        if shiny:
            d.line([x0 + 3, h // 3 + 1 + bob, x0 + 3, h - 4], fill=shiny)
            d.point([(x0 + w - 4, h // 3 + 2 + bob)], fill=(255, 255, 255))
    return img


def sprite(id, img, frames=1, fps=0, **extra):
    name = save(img, id + ".png")
    e = {"file": name}
    if frames > 1:
        e["frames"] = frames
        e["fps"] = fps
    e.update(extra)
    manifest["sprites"][id] = e


os.makedirs(OUT, exist_ok=True)

# --- mobs: tiny, few frames, choppy (low fps) ---
sprite("slime", blob(12, 10, MUTED["slime"] + (190,), 2, eyes=True), 2, 3)
sprite("slime_pool_mate", blob(12, 10, MUTED["slime"], 2, eyes=True), 2, 2)
sprite("colleague", blob(12, 10, (110, 150, 200), 2, eyes=True), 2, 4)
sprite("slime_battle", blob(12, 10, MUTED["slime"], 2, eyes=True), 2, 3)
sprite("slime_battle_ally", blob(12, 10, (110, 150, 200), 2, eyes=True), 2, 3)
sprite("toy_slime", blob(8, 6, (170, 150, 140)))
sprite("mentor", person(12, 16, MUTED["goblin"], (140, 160, 100)), 2, 2)
sprite("partner", person(12, 16, (120, 130, 170), MUTED["slime"]), 2, 1)
sprite("kid", blob(8, 7, MUTED["slime"], 2, eyes=True), 2, 4)

# --- heroes: bigger, saturated, smoother (more fps) ---
sprite("hero_sword", person(18, 30, SATURATED["sword"], (240, 200, 170), 4, SATURATED["gold"]), 4, 8, offset=[0, -12])
sprite("hero_mage", person(18, 30, SATURATED["mage"], (240, 200, 170), 4, SATURATED["gold"]), 4, 8, offset=[0, -12])
sprite("hero_thief", person(18, 30, SATURATED["thief"], (240, 200, 170), 4, SATURATED["gold"]), 4, 8, offset=[0, -12])
sprite("hero_sword_battle", person(40, 60, SATURATED["sword"], (250, 210, 180), 4, SATURATED["gold"]), 4, 8)
sprite("hero_mage_battle", person(40, 60, SATURATED["mage"], (250, 210, 180), 4, SATURATED["gold"]), 4, 8)
sprite("hero_thief_battle", person(40, 60, SATURATED["thief"], (250, 210, 180), 4, SATURATED["gold"]), 4, 8)

# --- the Meadow ---
sprite("pool", blob(44, 18, (80, 110, 150), squash=False))
sprite("board", box(16, 20, MUTED["wood"], label_band=MUTED["paper"]), offset=[0, -6])
sprite("pot_shards", box(10, 6, MUTED["pot"]))
sprite("pedestal", box(8, 12, MUTED["stone"]))
sprite("pedestal_glued", box(8, 12, (165, 140, 120)))
sprite("coin_sack", blob(12, 12, (150, 120, 80), squash=False))
sprite("chest", box(16, 11, MUTED["wood"], label_band=MUTED["coin"]))
sprite("chest_half", box(16, 11, (150, 110, 70), label_band=MUTED["coin"]))
sprite("old_tree", blob(30, 34, (80, 100, 70), squash=False))
sprite("seed_pile", blob(12, 7, MUTED["seed"], squash=False))
sprite("trampled_grass", box(20, 12, (150, 140, 90)))
sprite("bush", blob(22, 16, MUTED["bush"], squash=False))
sprite("mushroom_big", blob(16, 20, MUTED["mush"], squash=False))
sprite("mushroom_blue", blob(9, 9, MUTED["mush_blue"], squash=False))
sprite("mud", blob(30, 14, MUTED["mud"], squash=False))
sprite("path_pot", box(8, 9, MUTED["pot"]))
sprite("path_pot_broken", box(8, 4, (130, 85, 60)), offset=[0, 2])
sprite("home_sign", box(10, 14, MUTED["wood"], label_band=MUTED["paper"]), offset=[0, -4])

# --- items (seen through Slayme's jelly body) ---
# 6x6 with a dark outline: readable through the jelly at 320x180.
def item_icon(shape, color):
    img = Image.new("RGBA", (6, 6), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    edge = (50, 40, 35)
    if shape == "shard":
        d.polygon([(0, 5), (2, 0), (5, 2), (4, 5)], fill=color, outline=edge)
    elif shape == "coin":
        d.ellipse([0, 0, 5, 5], fill=color, outline=edge)
    elif shape == "seed":
        d.ellipse([1, 0, 4, 5], fill=color, outline=edge)
    else:
        d.rectangle([0, 0, 5, 5], fill=color, outline=edge)
    return img


for item, color in [("shard", MUTED["pot"]), ("coin", MUTED["coin"]), ("seed", MUTED["seed"]),
                    ("mud", MUTED["mud"]), ("spores", (200, 220, 255))]:
    sprite("item_" + item, item_icon(item, color))

# --- missing: magenta, shows any id the pack lacks ---
sprite("missing", box(8, 8, (255, 0, 255)))

# --- backgrounds ---
W, H = MAP["size"]
bg = Image.new("RGBA", (W, H), MUTED["grass"])
d = ImageDraw.Draw(bg)
random.seed(4)
for _ in range(220):
    x, y = random.randrange(W), random.randrange(H)
    d.point((x, y), fill=MUTED["grass_dark"])
d.line([tuple(p) for p in MAP["path"]], fill=MUTED["path"], width=18, joint="curve")
manifest["backgrounds"]["bg_meadow"] = {"file": save(bg, "bg_meadow.png"), "centered": False}

home = Image.new("RGBA", (320, 180), MUTED["home"])
d = ImageDraw.Draw(home)
d.rectangle([0, 100, 319, 179], fill=MUTED["home_floor"])
d.rectangle([40, 30, 80, 70], fill=(80, 90, 120))  # window
manifest["backgrounds"]["bg_home"] = {"file": save(home, "bg_home.png"), "centered": False}

battle = Image.new("RGBA", (320, 180), (96, 128, 84))
d = ImageDraw.Draw(battle)
d.rectangle([0, 0, 319, 60], fill=(140, 170, 200))
manifest["backgrounds"]["bg_battle_meadow"] = {"file": save(battle, "bg_battle_meadow.png"), "centered": False}

title = Image.new("RGBA", (320, 180), (30, 34, 48))
manifest["backgrounds"]["bg_title"] = {"file": save(title, "bg_title.png"), "centered": False}
night = Image.new("RGBA", (320, 180), (0, 0, 0))
manifest["backgrounds"]["bg_night"] = {"file": save(night, "bg_night.png"), "centered": False}


# --- UI frames (9-slice) ---
def frame(name, fill, border, inner=None):
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 11, 11], fill=border)
    d.rectangle([1, 1, 10, 10], fill=inner or fill)
    d.rectangle([2, 2, 9, 9], fill=fill)
    manifest["ui"][name] = {"file": save(img, name + ".png"), "margin": 3, "padding": 4}


frame("panel_dialogue", (24, 24, 40, 235), (230, 230, 230))
frame("panel_hero_menu", (20, 40, 150, 235), (255, 255, 255))   # the classic blue menu: the Heroes'
frame("panel_slime", (226, 218, 196, 240), (90, 80, 70))          # paper: Slayme's handwritten verbs
frame("panel_hud", (0, 0, 0, 140), (0, 0, 0, 0))




# Fixed-screen prototype (world.mode = screens)
# ---------------------------------------------------------------------------
def meadow_bg(name, path_y=None, tree=False, field=False, pool=False):
    img = Image.new("RGBA", (320, 180), (150, 190, 210))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 319, 70], fill=(170, 200, 214))           # sky, muted
    d.ellipse([-40, 50, 140, 110], fill=(104, 138, 88))           # far hills
    d.ellipse([120, 46, 380, 112], fill=(98, 132, 84))
    d.rectangle([0, 80, 319, 179], fill=MUTED["grass"])
    rnd = random.Random(name)
    for _ in range(420):
        x, y = rnd.randrange(320), rnd.randrange(82, 180)
        d.point((x, y), fill=MUTED["grass_dark"])
    for _ in range(26):  # little flowers: the Meadow is poor, not ugly
        x, y = rnd.randrange(320), rnd.randrange(90, 178)
        d.point((x, y), fill=rnd.choice([(230, 220, 160), (220, 170, 170), (240, 240, 230)]))
    if path_y is not None:
        pts = [(-10, path_y + 4), (80, path_y - 2), (170, path_y + 3), (250, path_y - 3), (330, path_y + 2)]
        d.line(pts, fill=MUTED["path"], width=22, joint="curve")
        for _ in range(60):
            x = rnd.randrange(320); y = path_y + rnd.randrange(-9, 9)
            d.point((x, y), fill=(160, 142, 104))
    if tree:
        d.rectangle([222, 30, 240, 100], fill=(110, 84, 60))
        d.ellipse([180, -10, 290, 70], fill=(76, 104, 70))
        d.ellipse([196, 4, 250, 44], fill=(88, 118, 78))
    if field:
        for row in range(4):
            d.line([(0, 112 + row * 18), (319, 108 + row * 18)], fill=(126, 146, 92), width=1)
    if pool:
        d.rectangle([0, 160, 40, 179], fill=(110, 96, 86))  # the way home
    manifest["backgrounds"][name] = {"file": save(img, name + ".png"), "centered": False}


meadow_bg("bg_loc_pool", pool=True)
meadow_bg("bg_loc_path", path_y=108)
meadow_bg("bg_loc_tree", path_y=104, tree=True)
meadow_bg("bg_loc_field", field=True)

pool_img = Image.new("RGBA", (84, 26), (0, 0, 0, 0))
d = ImageDraw.Draw(pool_img)
d.ellipse([0, 0, 83, 25], fill=(70, 100, 140), outline=(50, 76, 110))
d.ellipse([10, 5, 60, 14], fill=(96, 130, 170))
sprite("pool_big", pool_img)


def shard():
    img = Image.new("RGBA", (7, 5), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.polygon([(0, 4), (3, 0), (6, 3), (4, 4)], fill=MUTED["pot"], outline=(120, 70, 50))
    return img


sprite("shard_ground", shard())
coin = Image.new("RGBA", (5, 5), (0, 0, 0, 0)); d = ImageDraw.Draw(coin)
d.ellipse([0, 0, 4, 4], fill=MUTED["coin"], outline=(160, 140, 60))
sprite("coin_ground", coin)
sprite("seed_sack", blob(14, 14, (170, 150, 110), squash=False))


def pot_stage(n, total, color=MUTED["pot"], glue=False):
    img = Image.new("RGBA", (14, 22), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rectangle([2, 14, 11, 21], fill=MUTED["stone"], outline=(110, 110, 100))   # pedestal
    h = int(13 * n / total)
    if n < total:   # the shape of the missing pot, dotted: where the pieces go
        for y in range(1, 14, 2):
            d.point((3, y), fill=(200, 190, 170)); d.point((10, y), fill=(200, 190, 170))
        for x in range(3, 11, 2):
            d.point((x, 1), fill=(200, 190, 170))
    if h > 0:
        d.rectangle([3, 14 - h, 10, 13], fill=color, outline=(120, 70, 50))
        if glue:
            d.line([(3, 14 - h // 2), (10, 13 - h // 2)], fill=(240, 230, 200))
    return img


for i in range(4):
    sprite("pot_stage_%d" % i, pot_stage(i, 3), offset=[0, -8])
for i in range(5):
    sprite("glued_stage_%d" % i, pot_stage(i, 4, (165, 120, 95), glue=True), offset=[0, -8])
for i in range(4):
    img = Image.new("RGBA", (18, 13), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rectangle([0, 2, 17, 12], fill=MUTED["wood"], outline=(90, 66, 44))
    d.rectangle([0, 0, 17, 3], fill=(150, 112, 74), outline=(90, 66, 44))
    for c in range(3):   # empty slots stay visible: where the coins go
        if c < i:
            d.ellipse([3 + c * 4, 5, 6 + c * 4, 8], fill=MUTED["coin"])
        else:
            d.ellipse([3 + c * 4, 5, 6 + c * 4, 8], outline=(70, 50, 34))
    sprite("chest_stage_%d" % i, img, offset=[0, -4])
patch = Image.new("RGBA", (20, 10), (0, 0, 0, 0)); d = ImageDraw.Draw(patch)
d.ellipse([0, 0, 19, 9], fill=(150, 140, 96))
d.line([(3, 5), (16, 4)], fill=(120, 110, 80))
sprite("patch_trampled", patch)
sprout = Image.new("RGBA", (20, 10), (0, 0, 0, 0)); d = ImageDraw.Draw(sprout)
d.ellipse([0, 2, 19, 9], fill=(120, 120, 84))
for x in (4, 9, 14):
    d.line([(x, 7), (x, 2)], fill=(110, 170, 90)); d.point((x - 1, 3), fill=(130, 190, 100))
sprite("patch_sprout", sprout)


def arrow(direction):
    img = Image.new("RGBA", (9, 9), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    pts = {"right": [(1, 0), (8, 4), (1, 8)], "left": [(7, 0), (0, 4), (7, 8)],
           "up": [(0, 7), (4, 0), (8, 7)], "down": [(0, 1), (4, 8), (8, 1)]}[direction]
    d.polygon(pts, fill=(240, 236, 220), outline=(80, 70, 60))
    return img


for dname in ("left", "right", "up", "down"):
    sprite("exit_" + dname, arrow(dname))
cur = Image.new("RGBA", (7, 5), (0, 0, 0, 0)); d = ImageDraw.Draw(cur)
d.polygon([(0, 0), (6, 0), (3, 4)], fill=(255, 250, 200), outline=(60, 50, 40))
sprite("cursor_focus", cur)
frame("panel_board", (250, 244, 230, 245), (240, 140, 160))   # the Board: cheerful, clean


# --- sounds ---
def write_wav(name, samples, rate=22050):
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 30000)) for s in samples))
    return name


rate = 22050
# Small "MIDI-ish" instruments: marimba, kalimba, pluck, chip square, woodblock, drums.
# Simple synthesis, written once into wav files; the game only plays files.


def env(n, attack=0.004, decay=6.0):
    a = max(1, int(attack * rate))
    return [min(1.0, i / a) * math.exp(-decay * i / rate) for i in range(n)]


def marimba(f, d=0.35, v=0.5):
    n = int(rate * d); e = env(n, 0.002, 9)
    return [v * e[i] * (math.sin(2 * math.pi * f * i / rate) + 0.25 * math.sin(2 * math.pi * f * 3.9 * i / rate) * math.exp(-30 * i / rate)) for i in range(n)]


def kalimba(f, d=0.5, v=0.45):
    n = int(rate * d); e = env(n, 0.001, 7)
    return [v * e[i] * (math.sin(2 * math.pi * f * i / rate) + 0.4 * math.sin(2 * math.pi * f * 5.4 * i / rate) * math.exp(-40 * i / rate)) for i in range(n)]


def pluck(f, d=0.4, v=0.5, damp=0.996):
    n = int(rate * d); p = max(2, int(rate / f)); buf = [random.uniform(-1, 1) for _ in range(p)]; out = []
    for i in range(n):
        x = buf[i % p]; nxt = buf[(i + 1) % p]
        buf[i % p] = damp * 0.5 * (x + nxt); out.append(v * x)
    return out


def square(f, d=0.12, v=0.22, duty=0.5, decay=4.0, slide=0.0):
    n = int(rate * d); e = env(n, 0.002, decay); out = []; ph = 0.0
    for i in range(n):
        ph += (f + slide * i / n) / rate
        out.append(v * e[i] * (1 if (ph % 1.0) < duty else -1))
    return out


def tri(f, d=0.2, v=0.4, decay=8.0, slide=0.0):
    n = int(rate * d); e = env(n, 0.002, decay); out = []; ph = 0.0
    for i in range(n):
        ph += (f + slide * i / n) / rate
        out.append(v * e[i] * (4 * abs((ph % 1.0) - 0.5) - 1))
    return out


def noise(d=0.1, v=0.4, decay=20.0, smooth=0.0):
    n = int(rate * d); e = env(n, 0.001, decay); out = []; y = 0.0
    for i in range(n):
        y = smooth * y + (1 - smooth) * random.uniform(-1, 1); out.append(v * e[i] * y)
    return out


def drum(f, d=0.25, v=0.7, drop=0.5):
    n = int(rate * d); e = env(n, 0.001, 14); out = []; ph = 0.0
    for i in range(n):
        ph += f * (1 - drop * i / n) / rate; out.append(v * e[i] * math.sin(2 * math.pi * ph))
    return out


def woodblock(f=900, v=0.5):
    return mix(tri(f, 0.06, v, 60), noise(0.02, 0.15, 120, 0.3))


def mix(*parts):
    n = max(len(p) for p in parts); out = [0.0] * n
    for p in parts:
        for i, x in enumerate(p):
            out[i] += x
    return out


def seq(notes, gap):
    """notes: list of sample lists, each started gap seconds after the previous."""
    step = int(gap * rate); n = step * (len(notes) - 1) + max(len(x) for x in notes); out = [0.0] * n
    for k, x in enumerate(notes):
        for i, v in enumerate(x):
            out[k * step + i] += v
    return out


def snd(id, samples):
    peak = max(1e-6, max(abs(x) for x in samples))
    if peak > 0.95:
        samples = [x * 0.95 / peak for x in samples]
    manifest["sounds"][id] = {"file": write_wav(id + ".wav", samples)}


random.seed(1)
N = {"C4": 262, "D4": 294, "E4": 330, "F4": 349, "G4": 392, "A4": 440, "B4": 494, "C5": 523, "D5": 587,
     "E5": 659, "F5": 698, "G5": 784, "A5": 880, "C6": 1047, "G3": 196, "C3": 131, "E3": 165}

# The shift bell: an electric factory bell (a hammer at ~20 Hz on a metal gong), then a time-clock "clunk".
n = int(rate * 1.1)
bell = []
for i in range(n):
    t = i / rate
    ham = 0.55 + 0.45 * math.sin(2 * math.pi * 21 * t)
    tone = math.sin(2 * math.pi * 1180 * t) + 0.6 * math.sin(2 * math.pi * 2710 * t) + 0.35 * math.sin(2 * math.pi * 4430 * t)
    fade = 1.0 if t < 0.9 else max(0.0, 1 - (t - 0.9) / 0.2)
    bell.append(0.32 * ham * tone * fade)
bell = seq([bell, mix(drum(90, 0.18, 0.8, 0.3), noise(0.05, 0.4, 60, 0.6))], 1.05)
snd("bell", bell)


def factory_bell(dur, hammer=21, base=1180, vol=0.32, tail=0.2):
    """The same electric bell, any length: hammer on a metal gong, then a short fade."""
    out = []
    for i in range(int(rate * (dur + tail))):
        t = i / rate
        ham = 0.55 + 0.45 * math.sin(2 * math.pi * hammer * t)
        tone = math.sin(2 * math.pi * base * t) + 0.6 * math.sin(2 * math.pi * base * 2.3 * t) + 0.35 * math.sin(2 * math.pi * base * 3.75 * t)
        fade = 1.0 if t < dur else max(0.0, 1 - (t - dur) / tail)
        out.append(vol * ham * tone * fade)
    return out


# Four rhythms of one bell, told apart by ear (rules.json "bells").
snd("bell_open", factory_bell(0.35))                                                   # shift opens: short
snd("bell_heroes", seq([factory_bell(0.25, base=1400), factory_bell(0.25, base=1400)], 0.45))  # visitors: two rings
snd("bell_incident", mix(factory_bell(0.6, hammer=32, base=980, vol=0.5, tail=0.05), drum(70, 0.3, 0.9, 0.3)))  # sharp, loud
snd("bell_close", seq([factory_bell(1.6, hammer=14, base=1040, vol=0.28, tail=0.8),
                       mix(drum(90, 0.18, 0.8, 0.3), noise(0.05, 0.4, 60, 0.6))], 2.3))  # long, warm, the time clock

snd("fanfare", seq([square(N["G4"], 0.12), square(N["C5"], 0.12), square(N["E5"], 0.12), square(N["G5"], 0.4, decay=2)], 0.11))
snd("hit", mix(drum(140, 0.2, 0.8), noise(0.08, 0.5, 40, 0.2)))

# Work: absorb / deliver / job done / not here / spit
snd("absorb", mix(tri(520, 0.16, 0.45, 10, slide=-300), marimba(N["E4"], 0.25, 0.25)))
snd("deliver", seq([marimba(N["C5"], 0.3), marimba(N["G5"], 0.4)], 0.07))
snd("done", seq([kalimba(N["C5"]), kalimba(N["E5"]), kalimba(N["G5"]), kalimba(N["C6"], 0.8)], 0.08))
snd("nope", seq([woodblock(420), woodblock(380)], 0.09))
snd("spit", mix(tri(260, 0.15, 0.45, 12, slide=320), noise(0.06, 0.15, 50, 0.5)))
snd("footsteps", seq([drum(70, 0.2, 0.7, 0.2)] * 4, 0.32))

# UI and voices (one short pluck per line; the mobs each have their own pitch)
snd("ui_move", woodblock(1300, 0.25))
snd("ui_confirm", seq([pluck(N["E5"], 0.2, 0.35), pluck(N["A5"], 0.25, 0.35)], 0.05))
snd("ui_blip", pluck(N["A4"], 0.12, 0.3))
snd("blip_mentor", pluck(N["G3"], 0.16, 0.4, 0.99))
snd("blip_colleague", pluck(N["E5"], 0.1, 0.3))
snd("blip_partner", pluck(N["C5"], 0.14, 0.3))
snd("blip_kid", pluck(N["G5"], 0.1, 0.3))

# Battle: the Heroes are loud and shiny (chip), Slayme is wood and pluck.
snd("pose", seq([square(N["C5"], 0.08), square(N["E5"], 0.08), square(N["G5"], 0.25, decay=3)], 0.08))
snd("focus", seq([tri(N["A5"], 0.3, 0.3, 4), tri(N["E5"], 0.3, 0.3, 4)], 0.12))
snd("poke", woodblock(700, 0.4))
snd("charge", square(200, 0.5, 0.18, 0.25, 1.5, slide=500))
snd("slash", mix(noise(0.25, 0.6, 10, 0.1), square(900, 0.2, 0.15, 0.5, 8, slide=-700)))
snd("fire", mix(noise(0.35, 0.45, 6, 0.85), tri(180, 0.3, 0.3, 6, slide=-80)))
snd("thunder", mix(noise(0.6, 0.7, 4, 0.92), drum(55, 0.6, 0.8, 0.4)))
snd("fizzle", tri(300, 0.2, 0.3, 10, slide=-200))
snd("steal", seq([pluck(N["C6"], 0.08, 0.3), pluck(N["A5"], 0.08, 0.3), pluck(N["F5"], 0.15, 0.3)], 0.05))
snd("unlock", seq([kalimba(N["G4"]), kalimba(N["D5"]), kalimba(N["G5"], 0.7)], 0.12))
snd("v_look", seq([marimba(N["E5"], 0.15, 0.3), marimba(N["A5"], 0.2, 0.3)], 0.06))
snd("v_brace", drum(110, 0.15, 0.5, 0.1))
snd("v_absorb", mix(tri(400, 0.2, 0.4, 8, slide=-250)))
snd("v_hide", noise(0.25, 0.25, 10, 0.95))
snd("v_help", seq([pluck(N["C5"], 0.15), pluck(N["C5"], 0.15)], 0.14))
snd("v_flee", seq([woodblock(1100, 0.3), woodblock(1300, 0.3), woodblock(1500, 0.3)], 0.06))
snd("battle_incident", seq([marimba(N["E4"], 0.4), marimba(N["C4"], 0.4), marimba(N["G3"], 0.8)], 0.18))
snd("battle_fled", seq([pluck(N["C5"], 0.15), pluck(N["E5"], 0.15), pluck(N["G5"], 0.3)], 0.07))
snd("battle_bored", seq([square(N["G4"], 0.15, 0.15), square(N["E4"], 0.15, 0.15), square(N["C4"], 0.4, 0.15, decay=2)], 0.16))

# The Heroes' theme: a confident little march (chip square lead, triangle bass, drums).
# One loop; the game muffles it with distance (rules.json "music"), never Slayme's own sound.
def hero_theme():
    bpm = 132
    beat = 60.0 / bpm
    total = int(rate * beat * 32)   # 8 bars of 4/4
    out = [0.0] * total
    def put(samples, at_beat):
        start = int(at_beat * beat * rate)
        for i, v in enumerate(samples):
            if start + i < total:
                out[start + i] += v
    lead = [("C5", 1), ("E5", 0.5), ("G5", 0.5), ("C6", 1.5), ("G5", 0.5), ("A5", 1), ("G5", 0.5), ("E5", 0.5), ("D5", 2),
            ("D5", 1), ("F5", 0.5), ("A5", 0.5), ("G5", 1.5), ("E5", 0.5), ("F5", 1), ("E5", 0.5), ("D5", 0.5), ("C5", 2),
            ("C5", 1), ("E5", 0.5), ("G5", 0.5), ("C6", 1.5), ("G5", 0.5), ("A5", 1), ("C6", 0.5), ("A5", 0.5), ("G5", 2),
            ("F5", 1), ("E5", 0.5), ("D5", 0.5), ("E5", 1), ("G5", 1), ("C5", 3), (None, 1)]
    t = 0.0
    for note, d in lead:
        if note:
            put(square(N[note], d * beat * 0.9, 0.16, 0.25, 2.5), t)
        t += d
    bass = ["C3", "C3", "G3", "G3", "G3", "G3", "C3", "C3", "C3", "C3", "F4", "F4", "G3", "G3", "C3", "C3"]
    for i, b in enumerate(bass):
        f = N[b] / 2 if b == "F4" else N[b]
        put(tri(f, beat * 1.8, 0.35, 2.0), i * 2)
    for k in range(32):
        put(drum(100, 0.15, 0.45, 0.4) if k % 2 == 0 else noise(0.07, 0.18, 45, 0.3), k)
    return out


snd("hero_theme", hero_theme())
manifest["sounds"]["hero_theme"]["loop"] = True
# "You've been seen": a short sting, the theme's first notes, loud.
snd("spotted", seq([square(N["G5"], 0.1, 0.3), square(N["C6"], 0.35, 0.3, decay=3)], 0.09))

# icon
icon = blob(64, 52, MUTED["slime"], eyes=False)
canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0)); canvas.paste(icon, (0, 10))
canvas.save(os.path.join(ROOT, "icon.png"))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent="\t")
print("placeholder pack written to", OUT)
