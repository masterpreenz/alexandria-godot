"""Imports the second young man's sprite set (villager look 6, "villager_4m") from his 4x4 sheets, and can be re-run.

    python tools/import_villager4m.py [source_folder]

Reads "Villager 2 M-iso_<anim>_<southwest|northwest>.png" (run: the "-trimmed" sheets, 14 and 9 frames) from the source
folder (default: the unity-test villagers/villager3_m folder), copies the source to ../ArtSource/characters/villager_4m
and the sheets to assets/Art/Characters/Villager/villager_4m, then writes the frame entries "villager4m_<anim>_<down|up>_<n>"
into data/sprites.json (the first run appends them; a re-run rewrites them in place, so the ids never move) and sets
the look's frames, strikes, fishing tips and lying offsets in data/villagers.json (the look whose settings say
"art":"villager_4m"). Needs numpy, Pillow and scipy. Then run Godot's --import.
"""
import json, os, shutil, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SRC = sys.argv[1] if len(sys.argv) > 1 else 'C:/Users/preen/OneDrive/Desktop/unity-test/villagers/villager3_m/'
if not SRC.endswith('/'):
    SRC += '/'
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE).replace('\\', '/') + '/'
ART = os.path.dirname(GAME.rstrip('/')) + '/ArtSource/characters/villager_4m/'
DST = GAME + 'assets/Art/Characters/Villager/villager_4m/'
PPU = 133.0                      # one scale for every sheet: she stands as tall as the other villagers
ANIMS = {'idle': 'idle', 'run': 'run', 'chop': 'custom_lumbering_axe', 'mine': 'custom_mining_pickaxe',
         'fish': 'custom_villager_fishing', 'sleep': 'custom_sleep', 'stab': 'custom_spear_stab', 'bow': 'custom_bow_attack'}
# Frame picks (change here if the redrawn sheets differ).
IDLE_FRAME = 0                   # the standing frame used
CHOP_STRIKE = [7]                # where the axe lands
MINE_STRIKE = [4]                # where the pick lands
STAB_STRIKE = [8]                # the spear's thrust lands on this frame
LIE_FRAMES = 7                   # sleeping frames before she is settled
RUN_CYCLE = 1.2                  # seconds for one run cycle (two strides), whatever each sheet's frame count
BOW_LOOSE = 9                    # the frame the arrow leaves the bow on
IDLE_FPS = 6

os.makedirs(ART, exist_ok=True)
os.makedirs(DST, exist_ok=True)
for f in os.listdir(SRC):
    shutil.copy(SRC + f, ART + f)


def frames(im):
    """The sheet's frames, 4 to a row, as many rows as it has, empty cells at the end left out."""
    rows_ = im.height // 256
    out = [im.crop(((i % 4) * 256, (i // 4) * 256, (i % 4) * 256 + 256, (i // 4) * 256 + 256)) for i in range(4 * rows_)]
    while out and out[-1].getbbox() is None:
        out.pop()
    return out[:16]


def source(name, n):
    """A sheet's file: its "-trimmed" version when there is one (a redrawn sheet with fewer frames)."""
    t = SRC + f'Villager 2 M-iso_{name}_{n}-trimmed.png'
    return t if os.path.exists(t) else SRC + f'Villager 2 M-iso_{name}_{n}.png'


COUNT = {}


def pivot(fr, which=None):
    xs, bs = [], []
    for k, f in enumerate(fr):
        if which is not None and k not in which:
            continue
        a = np.array(f.getchannel('A')) > 40
        ys, _ = np.nonzero(a)
        b = ys.max()
        bs.append(b)
        _, cx = np.nonzero(a[b - 20:b + 1])
        xs.append(cx.mean())
    return [round(float(np.median(xs)), 1), round(float(np.percentile(bs, 75)), 1)]


def rod_tip(f):
    a = np.array(f.getchannel('A')) > 40
    op = ndi.binary_opening(a, structure=np.ones((13, 13)))
    thin = a & ~ndi.binary_dilation(op, iterations=4)
    lab, k = ndi.label(thin, structure=np.ones((3, 3)))
    cy, cx = ndi.center_of_mass(op)
    best = None
    for c in range(1, k + 1):
        ys, xs = np.nonzero(lab == c)
        if len(ys) < 25:
            continue
        d = np.hypot(xs - cx, ys - cy)
        j = d.argmax()
        if best is None or d[j] > best[0]:
            best = (d[j], xs[j], ys[j])
    return best[1], best[2]


rows, sheets, PV = [], {}, {}
for key, name in ANIMS.items():
    for dr, n in (('down', 'southwest'), ('up', 'northwest')):
        im = Image.open(source(name, n)).convert('RGBA')
        out = f'villager4_{key}_{"sw" if dr == "down" else "nw"}.png'
        im.save(DST + out)
        fr = frames(im)
        sheets[(key, dr)] = fr
        PV[(key, dr)] = pivot(fr)
        COUNT[(key, dr)] = len(fr)
        for i in range(16):
            j = min(i, len(fr) - 1)   # (16 entries kept so the ids never move; past a short sheet's end, its last frame)
            rows.append({"name": f"villager4m_{key}_{dr}_{i}", "tex": f"res://assets/Art/Characters/Villager/villager_4m/{out}",
                         "rect": [(j % 4) * 256, (j // 4) * 256, 256, 256], "pivot": PV[(key, dr)], "ppu": PPU})

# Frames drawn bigger or smaller by hand (the animation tuner, F4, saves data/art_tune.json): kept on a re-import.
tune_path = GAME + 'data/art_tune.json'
TUNE = json.load(open(tune_path, encoding='utf-8')).get('sprites', {}) if os.path.exists(tune_path) else {}
for r in rows:
    t = TUNE.get(r['name'])
    if t:
        r['ppu'] = round(PPU / float(t.get('scale', 1.0)), 2)
        n = t.get('nudge', [0, 0])
        r['pivot'] = [round(r['pivot'][0] + float(n[0]), 1), round(r['pivot'][1] + float(n[1]), 1)]

# sprites.json: in place when the entries exist, else appended (read just now, written straight back).
path = GAME + 'data/sprites.json'
text = open(path, newline='').read()
nl = '\r\n' if '\r\n' in text else '\n'
cur = json.loads(text)
have = {r['name']: i for i, r in enumerate(cur) if r['name'].startswith('villager4m_')}
ids = {}
if have:
    for r in rows:
        cur[have[r['name']]] = r
        ids[r['name']] = have[r['name']]
else:
    for r in rows:
        ids[r['name']] = len(cur)
        cur.append(r)
body = '[' + nl + (',' + nl).join(json.dumps(r, separators=(',', ':')) for r in cur) + nl + ']' + nl
open(path, 'w', newline='').write(body)


def idx(key, dr):
    return [ids[f'villager4m_{key}_{dr}_{i}'] for i in range(COUNT[(key, dr)])]


def tips(dr):
    px, py = PV[('fish', dr)]
    out = []
    for f in sheets[('fish', dr)]:
        x, y = rod_tip(f)
        out.append([round(int(x) - px), round(int(y) - py)])
    return out


def lying(dr):
    """Where his body's middle and his head are in the settled sleeping frame, from the frame's pivot, in the world's
    pixels as the game draws him (frame px x 128 / PPU x the body's scale 0.7), as the other looks' are. The head is
    the end of him (left or right) that stands taller."""
    a = np.array(sheets[('sleep', dr)][-1])
    px, py = PV[('sleep', dr)]
    al = a[..., 3] > 40
    ys, xs = np.nonzero(al)
    x0, x1 = xs.min(), xs.max()
    mid_x = (x0 + x1) / 2
    colh = al.sum(0)
    right = colh[int(mid_x):].max() > colh[:int(mid_x)].max()
    hx0, hx1 = (mid_x, x1) if right else (x0, mid_x)
    sel = (xs >= hx0) & (xs <= hx1)
    head = [float(np.percentile(xs[sel], 70 if right else 30)), float(ys[sel].mean())]
    k = 128.0 / PPU * 0.7
    return {"middle": [round((mid_x - px) * k, 1), round(((ys.min() + ys.max()) / 2 - py) * k, 1)],
            "head": [round((head[0] - px) * k, 1), round((head[1] - py) * k, 1)]}


vpath = GAME + 'data/villagers.json'
vt = open(vpath, newline='').read()
vnl = chr(13) + chr(10) if chr(13) + chr(10) in vt else chr(10)
lines = vt.split(vnl)
li = [i for i, l in enumerate(lines) if '"art":"villager_4m"' in l]
if li:
    L = lines[li[0]]
    trail = '],' if L.endswith('],') else (',' if L.endswith(',') else '')
    look = json.loads(L[:-len(trail)] if trail else L)
else:
    # First run: a new look after the last, made from the first young man's (his sounds, pace and so on).
    first = [i for i, l in enumerate(lines) if l.startswith('"looks":[')][0]
    look = json.loads(lines[first][len('"looks":['):-1])
    last = [i for i, l in enumerate(lines) if l.endswith('}}],')][0]
    lines[last] = lines[last][:-2] + ','
    li = [last + 1]
    lines.insert(li[0], '')
    trail = '],'
    for k in ('shift',):
        pass
    look['settings'].pop('uniqueTo', None)
s = look['settings']
s['art'] = 'villager_4m'
s['idleDown'], s['idleUp'] = idx('idle', 'down')[IDLE_FRAME], idx('idle', 'up')[IDLE_FRAME]
s['idleDownAnim'], s['idleUpAnim'], s['idleFps'] = idx('idle', 'down'), idx('idle', 'up'), IDLE_FPS
s['walkDown'], s['walkUp'] = idx('run', 'down'), idx('run', 'up')
s['walkFps'] = round(COUNT[('run', 'down')] / RUN_CYCLE, 2)
s['walkFpsUp'] = round(COUNT[('run', 'up')] / RUN_CYCLE, 2)
s['fishDown'], s['fishUp'] = idx('fish', 'down'), idx('fish', 'up')
s['fishTipsDown'], s['fishTipsUp'] = tips('down'), tips('up')
s['mineDown'], s['mineUp'] = idx('mine', 'down'), idx('mine', 'up')
s['mineStrikesDown'] = s['mineStrikesUp'] = MINE_STRIKE
s['chopDown'], s['chopUp'] = idx('chop', 'down'), idx('chop', 'up')
s['chopStrikesDown'] = s['chopStrikesUp'] = CHOP_STRIKE
s['sleepDown'], s['sleepUp'], s['lieDownFrames'] = idx('sleep', 'down'), idx('sleep', 'up'), LIE_FRAMES
s['stabDown'], s['stabUp'], s['stabStrikes'] = idx('stab', 'down'), idx('stab', 'up'), STAB_STRIKE
s['bowDown'], s['bowUp'] = idx('bow', 'down'), idx('bow', 'up')
s['bowLooseDown'] = s['bowLooseUp'] = BOW_LOOSE
s['cookDown'], s['cookUp'] = [], []
look['body']['s'] = s['idleDown']
look['lying'] = {'sleepDown': lying('down'), 'sleepUp': lying('up')}
lines[li[0]] = json.dumps(look, separators=(',', ':')) + trail
open(vpath, 'w', newline='').write(vnl.join(lines))
print('Villager 4m look imported:', len(rows), 'frames,', 'rewritten in place' if have else 'appended', '; run Godot --import next')
