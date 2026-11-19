#!/usr/bin/env python3
"""Generates the Tessu icon layers (Finnish spitz ears) as separate flat SVGs for Apple's Icon Composer.

Every layer is 1024 x 1024 with a transparent background, flat fills only (Icon Composer adds its own
depth, glass and shadows, so none are baked in). Left and right shapes are exact mirrors.

    python3 make_layers.py            # rewrites the layer SVGs and preview.svg next to this file
Edit the colours and the left-ear paths below, run it again, and the right ear follows.
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
W = 1024

# ---- colours: Finnish spitz coat is a golden red with a pale cream inner ear -------------------------
BACKGROUND = "#1E2A38"   # deep slate; Icon Composer can replace this layer with its own fill or gradient
COAT       = "#D2691E"   # golden red
COAT_DARK  = "#A9501A"   # shaded edge of the head
INNER_EAR  = "#F4E3C3"   # cream

# ---- left-side shapes (absolute SVG path data, y grows downward) ------------------------------------
# Outer ear: tall, pointed, tip slightly rounded, base sunk into the head.
EAR_L = ("M 188 800 C 196 690 226 540 288 396 C 300 366 330 336 352 330 C 366 328 376 338 384 352 C 440 450 478 620 490 800 Z")
# Inner ear: the same shape, smaller, set toward the front edge.
INNER_L = ("M 276 780 C 284 690 308 580 346 484 C 354 464 366 456 376 470 C 408 530 428 650 434 780 Z")
# Head: a wide, low dome that the ears grow out of; the bottom is cut off by the icon edge.
HEAD = ("M -80 900 C -40 726 240 664 512 664 C 784 664 1064 726 1104 900 L 1104 1100 L -80 1100 Z")
# A darker band along the top edge of the head, for a touch of depth without gradients.
HEAD_SHADE = ("M -80 900 C -40 726 240 664 512 664 C 784 664 1064 726 1104 900 C 1040 768 780 716 512 716 C 244 716 -16 768 -80 900 Z")


def mirror(d):
    """Mirrors absolute path data around the vertical centre line. Arcs are not used, so only x flips."""
    out, nums = [], re.findall(r"[A-Za-z]|-?\d+(?:\.\d+)?", d)
    i = 0
    while i < len(nums):
        t = nums[i]
        if t.isalpha():
            out.append(t); i += 1
        else:
            out.append(f"{W - float(t):g}"); out.append(nums[i + 1]); i += 2
    return " ".join(out)


def svg(*body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">\n'
            + "\n".join(body) + "\n</svg>\n")


def g(name, fill, *paths):
    inner = "\n".join(f'    <path d="{p}"/>' for p in paths)
    return f'  <g id="{name}" fill="{fill}">\n{inner}\n  </g>'


LAYERS = {
    "layer-0-background.svg": svg(f'  <rect id="background" width="{W}" height="{W}" fill="{BACKGROUND}"/>'),
    "layer-1-ears.svg": svg(g("ear-left", COAT, EAR_L), g("ear-right", COAT, mirror(EAR_L))),
    "layer-2-inner-ears.svg": svg(g("inner-ear-left", INNER_EAR, INNER_L), g("inner-ear-right", INNER_EAR, mirror(INNER_L))),
    "layer-3-head.svg": svg(g("head", COAT, HEAD), g("head-shade", COAT_DARK, HEAD_SHADE)),
}

def build_bundle():
    """Writes ../Tessu.icon, the document Icon Composer opens. Layers are listed top to bottom."""
    import json, shutil
    bundle = os.path.join(os.path.dirname(HERE), "Tessu.icon")
    shutil.rmtree(bundle, ignore_errors=True)
    os.makedirs(os.path.join(bundle, "Assets"))
    names = [("layer-3-head.svg", "head"), ("layer-2-inner-ears.svg", "inner ears"), ("layer-1-ears.svg", "ears")]
    for f, _ in names:
        shutil.copy(os.path.join(HERE, f), os.path.join(bundle, "Assets", f))
    layers = [{"image-name": f, "name": n, "glass": True, "position": {"scale": 1, "translation-in-points": [0, 0]}} for f, n in names]
    r, g_, b = (int(BACKGROUND[i:i + 2], 16) / 255 for i in (1, 3, 5))
    icon = {"fill": {"solid": f"extended-srgb:{r:.5f},{g_:.5f},{b:.5f},1.00000"},
            "groups": [{"layers": layers, "shadow": {"kind": "neutral", "opacity": 0.5}, "translucency": {"enabled": True, "value": 0.4}}],
            "supported-platforms": {"squares": ["macOS"]}}
    json.dump(icon, open(os.path.join(bundle, "icon.json"), "w"), indent=2)
    print("wrote", bundle)


if __name__ == "__main__":
    for name, text in LAYERS.items():
        open(os.path.join(HERE, name), "w").write(text)
    # One flat file with every layer stacked, for a quick look and for designers who prefer a single SVG.
    stack = [re.sub(r"</?svg[^>]*>", "", t).strip("\n") for t in LAYERS.values()]
    open(os.path.join(HERE, "preview.svg"), "w").write(svg(*stack))
    print("wrote", len(LAYERS), "layers + preview.svg in", HERE)
    build_bundle()
