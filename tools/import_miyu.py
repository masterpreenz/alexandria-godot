"""Imports Miyu's own sprite set (villager look 5) from her 4x4 sheets, and can be re-run when the sheets are redrawn.

    python tools/import_miyu.py [source_folder]

Reads "Miyu v2-iso_<anim>_<southwest|northwest>.png" from the source folder (default: the unity-test characters/miyu
folder), copies the source to ../ArtSource/characters/miyu and the sheets to assets/Art/Characters/Villager/miyu, then
writes the 288 frame entries "miyu2_<anim>_<down|up>_<n>" into data/sprites.json (the first run appends them; a re-run
rewrites the same entries in place, so the sprite ids never change) and sets the look's frames, strikes, fishing tips
(found by looking for the thin rod sticking out of the body in each fishing frame), lying offsets and faint order in
data/villagers.json (the look whose settings say uniqueTo miyu). Needs numpy, Pillow and scipy. Then run Godot's
--import.
"""
import json, os, shutil, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SRC = sys.argv[1] if len(sys.argv) > 1 else 'C:/Users/preen/OneDrive/Desktop/unity-test/characters/miyu/'
if not SRC.endswith('/'):
    SRC += '/'
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE).replace('\\', '/') + '/'
ART = os.path.dirname(GAME.rstrip('/')) + '/ArtSource/characters/miyu/'
DST = GAME + 'assets/Art/Characters/Villager/miyu/'
PPU = 162.0                      # one scale for every sheet: she stands as tall as the other villagers
ANIMS = {'idle': 'idle', 'run': 'run', 'chop': 'custom_lumbering', 'mine': 'custom_mining', 'cook': 'custom_cooking',
         'fish': 'custom_fishing', 'sleep': 'custom_sleep', 'faint': 'custom_death', 'cast': 'custom_casting'}
# Frame picks (change here if the redrawn sheets differ).
IDLE_FRAME = 0                   # the standing frame used
CHOP_STRIKE = [7]                # where the axe lands
MINE_STRIKE = [4]                # where the pick lands
STAB_STRIKE = [8]                # the staff "swing" is the casting frames in order; this is its hit (and cast pose) frame
LIE_FRAMES = 4                   # sleeping frames before she is settled
RUN_CYCLE = 0.9                  # seconds for one run cycle (two strides), whatever each sheet's frame count
FAINT_ORDER = [0, 1, 2, 3, 4, 4, 5, 5, 6, 6, 7, 8, 12, 13, 14, 15]   # stagger (10), fall (2), lying (4)

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
    t = SRC + f'Miyu v2-iso_{name}_{n}-trimmed.png'
    return t if os.path.exists(t) else SRC + f'Miyu v2-iso_{name}_{n}.png'


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
        out = f'miyu_{key}_{"sw" if dr == "down" else "nw"}.png'
        im.save(DST + out)
        fr = frames(im)
        sheets[(key, dr)] = fr
        PV[(key, dr)] = pivot(fr, list(range(7)) if key == 'faint' else None)
        COUNT[(key, dr)] = len(fr)
        for i in range(16):
            j = min(i, len(fr) - 1)   # (16 entries kept so the ids never move; past a short sheet's end, its last frame)
            rows.append({"name": f"miyu2_{key}_{dr}_{i}", "tex": f"res://assets/Art/Characters/Villager/miyu/{out}",
                         "rect": [(j % 4) * 256, (j // 4) * 256, 256, 256], "pivot": PV[(key, dr)], "ppu": PPU})

# sprites.json: in place when the entries exist, else appended (read just now, written straight back).
path = GAME + 'data/sprites.json'
text = open(path, newline='').read()
nl = '\r\n' if '\r\n' in text else '\n'
cur = json.loads(text)
have = {r['name']: i for i, r in enumerate(cur) if r['name'].startswith('miyu2_')}
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
    return [ids[f'miyu2_{key}_{dr}_{i}'] for i in range(COUNT[(key, dr)])]


def tips(dr):
    px, py = PV[('fish', dr)]
    out = []
    for f in sheets[('fish', dr)]:
        x, y = rod_tip(f)
        out.append([round(int(x) - px), round(int(y) - py)])
    return out


def lying(dr):
    a = np.array(sheets[('sleep', dr)][15])
    px, py = PV[('sleep', dr)]
    al = a[..., 3] > 40
    ys, xs = np.nonzero(al)
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    hy, hx = np.nonzero(al & (b > r + 8) & (r > 80) & (r < 190) & (g < r - 15) & (b < 200))
    return {"middle": [round(float((xs.min() + xs.max()) / 2 - px), 1), round(float((ys.min() + ys.max()) / 2 - py), 1)],
            "head": [round(float(hx.mean() - px), 1), round(float(hy.mean() - py), 1)]}


vpath = GAME + 'data/villagers.json'
vt = open(vpath, newline='').read()
vnl = '\r\n' if '\r\n' in vt else '\n'
lines = vt.split(vnl)
li = [i for i, l in enumerate(lines) if '"uniqueTo":"miyu"' in l]
assert len(li) == 1, 'look with uniqueTo miyu not found'
L = lines[li[0]]
trail = '],' if L.endswith('],') else (',' if L.endswith(',') else '')
look = json.loads(L[:-len(trail)] if trail else L)
s = look['settings']
s['fishDown'], s['fishUp'] = idx('fish', 'down'), idx('fish', 'up')
s['fishTipsDown'], s['fishTipsUp'] = tips('down'), tips('up')
fd, fu = idx('faint', 'down'), idx('faint', 'up')
s['faintDown'], s['faintUp'] = [fd[i] for i in FAINT_ORDER], [fu[i] for i in FAINT_ORDER]
s['idleDown'], s['idleUp'] = idx('idle', 'down')[IDLE_FRAME], idx('idle', 'up')[IDLE_FRAME]
s['walkDown'], s['walkUp'] = idx('run', 'down'), idx('run', 'up')
s['walkFps'] = round(COUNT[('run', 'down')] / RUN_CYCLE, 2)
s['walkFpsUp'] = round(COUNT[('run', 'up')] / RUN_CYCLE, 2)
s['mineDown'], s['mineUp'] = idx('mine', 'down'), idx('mine', 'up')
s['mineStrikesDown'] = s['mineStrikesUp'] = MINE_STRIKE
s['chopDown'], s['chopUp'] = idx('chop', 'down'), idx('chop', 'up')
s['chopStrikesDown'] = s['chopStrikesUp'] = CHOP_STRIKE
s['sleepDown'], s['sleepUp'], s['lieDownFrames'] = idx('sleep', 'down'), idx('sleep', 'up'), LIE_FRAMES
s['cookDown'], s['cookUp'] = idx('cook', 'down'), idx('cook', 'up')
s['stabDown'], s['stabUp'], s['stabStrikes'] = idx('cast', 'down'), idx('cast', 'up'), STAB_STRIKE
look['body']['s'] = s['idleDown']
look['lying'] = {'sleepDown': lying('down'), 'sleepUp': lying('up')}
lines[li[0]] = json.dumps(look, separators=(',', ':')) + trail
open(vpath, 'w', newline='').write(vnl.join(lines))
print('Miyu look imported:', len(rows), 'frames,', 'rewritten in place' if have else 'appended', '; run Godot --import next')
