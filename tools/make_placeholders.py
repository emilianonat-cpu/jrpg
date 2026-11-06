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
bell = [math.exp(-3 * t / rate) * (0.6 * math.sin(2 * math.pi * 880 * t / rate) + 0.3 * math.sin(2 * math.pi * 2210 * t / rate)) for t in range(int(rate * 1.2))]
manifest["sounds"]["bell"] = {"file": write_wav("bell.wav", bell)}
fan = []
for f in [523, 659, 784, 1046]:
    fan += [0.4 * math.sin(2 * math.pi * f * t / rate) * (1 - t / (rate * 0.18)) for t in range(int(rate * 0.18))]
manifest["sounds"]["fanfare"] = {"file": write_wav("fanfare.wav", fan)}
random.seed(1)
hit = [random.uniform(-1, 1) * math.exp(-12 * t / rate) * 0.5 for t in range(int(rate * 0.2))]
manifest["sounds"]["hit"] = {"file": write_wav("hit.wav", hit)}
# absorb: a short wet "blup" sliding down; deliver: a small two-note "tok-tik"
blup = [0.5 * math.sin(2 * math.pi * (420 - 260 * t / (rate * 0.14)) * t / rate) * (1 - t / (rate * 0.14)) for t in range(int(rate * 0.14))]
manifest["sounds"]["absorb"] = {"file": write_wav("absorb.wav", blup)}
tok = []
for f in [660, 990]:
    tok += [0.4 * math.sin(2 * math.pi * f * t / rate) * math.exp(-18 * t / rate) for t in range(int(rate * 0.09))]
manifest["sounds"]["deliver"] = {"file": write_wav("deliver.wav", tok)}

# icon
icon = blob(64, 52, MUTED["slime"], eyes=False)
canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0)); canvas.paste(icon, (0, 10))
canvas.save(os.path.join(ROOT, "icon.png"))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent="\t")
print("placeholder pack written to", OUT)
