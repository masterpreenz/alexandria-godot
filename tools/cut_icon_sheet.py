"""Cuts icons out of a placeholder-icon sheet with the user's art in it (ArtSource/placeholder_icons/group_NN.png's
layout: six boxes, three across, two down, on a dark ground).

    python tools/cut_icon_sheet.py <sheet image> <name1> ... <name6>

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


def boxes(im):
    """The six icon boxes, found where the sheet's lighter box edges are (the layout's measures, scaled)."""
    w, h = im.size
    sx, sy = w / 1866.0, h / 843.0
    out = []
    for row in range(2):
        for col in range(3):
            x0 = (48 + col * 614) * sx
            y0 = (98 + row * 367) * sy
            out.append(tuple(int(v) for v in (x0 + 4, y0 + 4, x0 + 197 * sx - 4, y0 + 197 * sy - 4)))
    return out


def clear_ground(c):
    w, h = c.size
    px = c.load()

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
    for box, name in zip(boxes(im), names):
        if name == "-":
            continue
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
