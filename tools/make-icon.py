# Draws the app icon: orange gradient, white globe, location pin.
# Run: python tools/make-icon.py  -> Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import json
import os
from PIL import Image, ImageChops, ImageDraw

S = 1024
K = 4  # supersample for smooth edges
N = S * K
WHITE = (255, 255, 255, 255)

# Background: vertical gradient (iOS adds the rounded corners itself; icon must be opaque).
top, bottom = (255, 140, 40), (232, 62, 20)
bg = Image.new("RGB", (1, N))
for y in range(N):
    t = y / (N - 1)
    bg.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
img = bg.resize((N, N)).convert("RGBA")

# Globe lines on their own layer, clipped to the globe circle.
cx, cy, r = N * 0.46, N * 0.54, N * 0.30
w = int(N * 0.028)
box = (cx - r, cy - r, cx + r, cy + r)
lines = Image.new("RGBA", (N, N), (0, 0, 0, 0))
d = ImageDraw.Draw(lines)
for f in (0.0, 0.42, 0.78):  # meridians as ellipses of shrinking width
    rx = r * f
    if f == 0:
        d.line((cx, cy - r, cx, cy + r), fill=WHITE, width=w)
    else:
        d.ellipse((cx - rx, cy - r, cx + rx, cy + r), outline=WHITE, width=w)
for f in (-0.5, 0.0, 0.5):  # parallels
    y = cy + r * f
    d.line((cx - r, y, cx + r, y), fill=WHITE, width=w)
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).ellipse(box, fill=255)
lines.putalpha(ImageChops.multiply(lines.getchannel("A"), mask))
img.alpha_composite(lines)
ImageDraw.Draw(img).ellipse(box, outline=WHITE, width=int(w * 1.4))

# Location pin, top right, with an orange ring so it reads on top of the globe.
px, py, pr = N * 0.70, N * 0.33, N * 0.135
pin = ImageDraw.Draw(img)
tip = (px, py + pr * 2.25)
ring = N * 0.022
pin.ellipse((px - pr - ring, py - pr - ring, px + pr + ring, py + pr + ring), fill=bottom)
pin.polygon([(px - pr * 0.80 - ring, py + pr * 0.55), (px + pr * 0.80 + ring, py + pr * 0.55),
             (tip[0], tip[1] + ring * 1.6)], fill=bottom)
pin.ellipse((px - pr, py - pr, px + pr, py + pr), fill=WHITE)
pin.polygon([(px - pr * 0.80, py + pr * 0.58), (px + pr * 0.80, py + pr * 0.58), tip], fill=WHITE)
hole = pr * 0.42
pin.ellipse((px - hole, py - hole, px + hole, py + hole), fill=bottom)

out_dir = os.path.join(os.path.dirname(__file__), "..", "Sources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(out_dir, exist_ok=True)
icon = img.resize((S, S), Image.LANCZOS).convert("RGB")
assert icon.size == (S, S) and icon.mode == "RGB"  # App Store rejects icons with alpha
icon.save(os.path.join(out_dir, "icon-1024.png"))

with open(os.path.join(out_dir, "Contents.json"), "w") as f:
    json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, f, indent=2)
with open(os.path.join(out_dir, "..", "Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
print("wrote", os.path.normpath(out_dir))
