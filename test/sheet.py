"""Contact sheets from a harness run: bar states, transition frames, panels.

    sheet.py <out-dir> <scale>...

Reads /tmp/pass-<scale>/ (see inside.sh). Bar crops are zoomed with nearest
neighbour so pixels stay pixels: 4x for a 1x pass, 2x for a 2x pass, so the
two come out the same size and can be compared. Each sheet also has the
strip at its real size, unzoomed.
"""

import glob
import os
import re
import shutil
import sys

from PIL import Image, ImageDraw

out = sys.argv[1]
scales = [int(s) for s in sys.argv[2:]] or [2, 1]
LABEL = 14


def load(path):
    return Image.open(path).convert("RGBA")


def sheet(rows, path, bg="white"):
    """rows: [(label, [(caption, image)])] laid out as a grid."""
    cell_w = max(im.width for _, cells in rows for _, im in cells)
    cell_h = max(im.height for _, cells in rows for _, im in cells)
    cols = max(len(cells) for _, cells in rows)
    pad = 8
    width = 110 + cols * (cell_w + pad)
    height = len(rows) * (cell_h + LABEL + pad) + pad
    canvas = Image.new("RGBA", (width, height), bg)
    draw = ImageDraw.Draw(canvas)
    y = pad
    for label, cells in rows:
        draw.text((6, y + cell_h // 2), label, fill="black")
        x = 110
        for caption, im in cells:
            canvas.paste(im, (x, y), im)
            draw.text((x, y + cell_h + 1), caption, fill="black")
            x += cell_w + pad
        y += cell_h + LABEL + pad
    canvas.save(path)


def zoomed(im, factor):
    return im.resize((im.width * factor, im.height * factor), Image.NEAREST)


for scale in scales:
    src = f"/tmp/pass-{scale}"
    if not os.path.isdir(src):
        continue
    zoom = max(1, 4 // scale)
    tag = f"@{scale}x"

    def bar(name):
        path = f"{src}/{name}.png"
        return load(path) if os.path.exists(path) else None

    # Bar states, dark and light, zoomed and at real size.
    states = ["install", "stopped", "idle", "working", "ready", "needs", "ready-working", "needs-working"]
    rows = []
    real = []
    for theme in ("dark", "light"):
        cells = [(s, bar(f"bar-{s}-{theme}")) for s in states]
        cells = [(c, im) for c, im in cells if im is not None]
        if cells:
            rows.append((theme, [(c, zoomed(im, zoom)) for c, im in cells]))
            real.append((theme, cells))
    if rows:
        sheet(rows, f"{out}/bar-states{tag}.png")
        sheet(real, f"{out}/bar-states-real-size{tag}.png")

    vcells = [(n, bar(f"vbar-{n}")) for n in ("install-dark", "idle-dark", "needs-working-dark", "needs-working-light")]
    vcells = [(c, zoomed(im, zoom)) for c, im in vcells if im is not None]
    if vcells:
        sheet([("vertical", vcells)], f"{out}/vertical-bar{tag}.png")

    # Transition frames: the corgi's part of the strip, at each scrubbed moment.
    frames = {}
    for path in glob.glob(f"{src}/frames/*.png"):
        match = re.match(r"(.+)-(\d\d)-(\d+)ms\.png$", os.path.basename(path))
        if match:
            frames.setdefault(match.group(1), []).append((int(match.group(2)), match.group(3) + "ms", path))
    motion = []
    for name in sorted(frames):
        cells = []
        for _, caption, path in sorted(frames[name]):
            im = load(path)
            w, h = im.size
            cells.append((caption, zoomed(im.crop((int(w * 0.43), 0, int(w * 0.78), h)), zoom)))
        motion.append((name, cells))
    if motion:
        sheet(motion, f"{out}/motion{tag}.png")

    # Panels: as the card renders, and as KeyboardPanel draws it on screen.
    for name in ("panel-dark", "panel-light", "panel-dark-collapsed", "panel-usage-dark", "panel-usage-light", "panel-usage-real-dark", "panel-usage-lone-dark", "panel-compacting-dark", "panel-compacted-dark", "panel-curling-dark", "panel-links-dark", "panel-moving-dark", "panel-starred-dark", "panel-unread-dark", "panel-folded-dark"):
        if os.path.exists(f"{src}/{name}.png"):
            shutil.copy(f"{src}/{name}.png", f"{out}/{name}{tag}.png")
    real_panel = f"{src}/panel-real-dark.png"
    if os.path.exists(real_panel):
        im = load(real_panel)
        box = im.getchannel("A").getbbox()
        if box:
            backdrop = Image.new("RGBA", im.size, "#303030")
            backdrop.alpha_composite(im)
            backdrop.crop((max(0, box[0] - 8), max(0, box[1] - 8), box[2] + 8, box[3] + 8)).save(
                f"{out}/panel-on-screen{tag}.png")

print("sheets written to", out)
