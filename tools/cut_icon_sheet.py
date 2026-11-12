"""Cuts icons out of a placeholder-icon sheet with the user's art in it (ArtSource/placeholder_icons/group_NN.png's
layout, at any size: six cards, three across, two down, each with its icon in a dark square).

    python tools/cut_icon_sheet.py <sheet image> <name1> ... (up to 6)

Each name is where that box's icon goes, in reading order: "Items/OakWand" -> assets/Icons/Items/OakWand.png
(64 x 64); "-" skips a box. The dark ground is taken out (round the icon, and any large patch it closes in, the inside
of a necklace's loop). The sheet and the large cut-outs are kept in ArtSource/placeholder_icons/."""

import os
import sys
from collections import deque

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ART = os.path.join(os.path.dirname(GAME), "ArtSource", "placeholder_icons")
GROUND = (27, 21, 17)
CLEAR, SOFT = 16, 26          # how near the ground a colour is: gone, or faded


def near(c):
    return max(abs(c[0] - GROUND[0]), abs(c[1] - GROUND[1]), abs(c[2] - GROUND[2]))


def box_at(im, i):
    """Icon box [i] (reading order): in its card (three across, two down, under the title), the dark square that isn't
    the page round the cards (the biggest dark patch that doesn't reach the card's edge). A sheet with fewer than six
    has only the first ones looked for."""
    w, h = im.size
    top = int(h * 0.08)
    row, col = divmod(i, 3)
    cx0, cx1 = int(col * w / 3), int((col + 1) * w / 3)
    cy0, cy1 = top + int(row * (h - top) / 2), top + int((row + 1) * (h - top) / 2)
    return _dark_square(im, (cx0, cy0, cx1, cy1))


def _dark_square(im, cell):
    x0, y0, x1, y1 = cell
    px = im.load()
    dark = lambda p: p[0] + p[1] + p[2] < 85
    seen = set()
    best = None
    step = 2   # (every other pixel: quick, and the boxes are big)
    for sy in range(y0, y1, step):
        for sx in range(x0, x1, step):
            if (sx, sy) in seen or not dark(px[sx, sy]):
                continue
            q = deque([(sx, sy)])
            n, bx0, by0, bx1, by1, edge = 0, sx, sy, sx, sy, False
            while q:
                x, y = q.popleft()
                if (x, y) in seen:
                    continue
                if not (x0 <= x < x1 and y0 <= y < y1):
                    edge = True
                    continue
                if not dark(px[x, y]):
                    continue
                seen.add((x, y))
                n += 1
                bx0, by0, bx1, by1 = min(bx0, x), min(by0, y), max(bx1, x), max(by1, y)
                q.extend([(x + step, y), (x - step, y), (x, y + step), (x, y - step)])
            if not edge and (best is None or n > best[0]):
                best = (n, (bx0, by0, bx1, by1))
    if best is None:
        raise SystemExit("no icon box found in %s" % (cell,))
    bx0, by0, bx1, by1 = best[1]
    return (bx0 + 3, by0 + 3, bx1 - 2, by1 - 2)


def clear_ground(c):
    global GROUND
    w, h = c.size
    px = c.load()
    edge = [px[x, 0][:3] for x in range(w)] + [px[0, y][:3] for y in range(h)]
    edge.sort(key=sum)
    GROUND = edge[len(edge) // 2]

    def fade(x, y):
        r, g, b, a = px[x, y]
        d = near((r, g, b))
        px[x, y] = (r, g, b, 0 if d <= CLEAR else int(255 * (d - CLEAR) / (SOFT - CLEAR)))

    # Round it, from the edges in.
    seen = set()
    q = deque([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        if near(px[x, y][:3]) <= SOFT:
            fade(x, y)
            q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    # Patches it closes in (big ones only: dark bits of the art itself stay).
    for sy in range(h):
        for sx in range(w):
            if (sx, sy) in seen or px[sx, sy][3] == 0 or near(px[sx, sy][:3]) > CLEAR:
                continue
            comp = []
            q = deque([(sx, sy)])
            while q:
                x, y = q.popleft()
                if (x, y) in seen or not (0 <= x < w and 0 <= y < h) or near(px[x, y][:3]) > SOFT:
                    continue
                seen.add((x, y))
                comp.append((x, y))
                q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
            if len(comp) > 300:
                for x, y in comp:
                    fade(x, y)
    return c


def main():
    sheet, names = sys.argv[1], sys.argv[2:]
    im = Image.open(sheet).convert("RGB")
    stem = os.path.splitext(os.path.basename(sheet))[0]
    os.makedirs(ART, exist_ok=True)
    im.save(os.path.join(ART, "art_%s.png" % stem))
    for i, name in enumerate(names):
        if name == "-":
            continue
        box = box_at(im, i)
        c = clear_ground(im.crop(box).convert("RGBA"))
        c = c.crop(c.getbbox())
        s = max(c.size)
        sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        sq.paste(c, ((s - c.size[0]) // 2, (s - c.size[1]) // 2))
        sq.save(os.path.join(ART, "cut_%s.png" % name.replace("/", "_")))
        dest = os.path.join(GAME, "assets", "Icons", name + ".png")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        sq.resize((64, 64), Image.LANCZOS).save(dest)
        print(name, sq.size)


if __name__ == "__main__":
    main()
