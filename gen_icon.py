#!/usr/bin/env python3
"""
BabyLove App Icon Generator — Master Redesign
1024×1024 px, iOS squircle shape, radial gradient background,
large white heart with baby face, footprint accent.
"""

from PIL import Image, ImageDraw, ImageFilter
import math

# ── Constants ──────────────────────────────────────────────────────────────────
SIZE = 1024
RADIUS = 224  # iOS squircle corner radius (~22% of 1024)
OUT_PATH = (
    "/Users/yaxinli/xym/babylove/BabyLove/Resources/Assets.xcassets/"
    "AppIcon.appiconset/AppIcon.png"
)
PREVIEW_PATH = "/tmp/icon_60px_preview.png"


# ── Helper: squircle mask ─────────────────────────────────────────────────────
def make_squircle_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=radius, fill=255)
    return mask


# ── 1. Canvas ─────────────────────────────────────────────────────────────────
canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


# ── 2. Radial gradient background ─────────────────────────────────────────────
# Center color #FF8C7E → edge color #F56555
# Gradient center: 50% horizontal, 45% vertical
center_x = SIZE * 0.50
center_y = SIZE * 0.45
max_dist = math.sqrt(center_x ** 2 + center_y ** 2) * 1.15  # covers all corners

c_center = (0xFF, 0x8C, 0x7E)  # #FF8C7E
c_edge   = (0xF5, 0x65, 0x55)  # #F56555

bg = Image.new("RGBA", (SIZE, SIZE))
bg_pixels = bg.load()
for y in range(SIZE):
    for x in range(SIZE):
        dist = math.sqrt((x - center_x) ** 2 + (y - center_y) ** 2)
        t = min(dist / max_dist, 1.0)
        r = int(c_center[0] * (1 - t) + c_edge[0] * t)
        g = int(c_center[1] * (1 - t) + c_edge[1] * t)
        b = int(c_center[2] * (1 - t) + c_edge[2] * t)
        bg_pixels[x, y] = (r, g, b, 255)

canvas.paste(bg, (0, 0))


# ── 3. Heart polygon helper ────────────────────────────────────────────────────
def heart_points(cx: float, cy: float, scale: float, steps: int = 400):
    """Parametric cardioid heart polygon. scale drives width ≈ 32*scale."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t)
               - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((cx + x * scale, cy + y * scale))
    return pts


# Heart geometry: ~680 px wide → scale = 680/32 ≈ 21.25
HEART_SCALE = 21.25
HEART_CX = SIZE / 2          # horizontal center
HEART_CY = 490.0             # vertical center (y≈480-490)

# ── 4. Inner shadow layer (behind the white heart) ────────────────────────────
shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sdraw = ImageDraw.Draw(shadow_layer)
shadow_pts = heart_points(HEART_CX + 4, HEART_CY + 8, HEART_SCALE)
sdraw.polygon(shadow_pts, fill=(200, 80, 60, 30))   # rgba(200,80,60,0.12)≈30/255
# Simulate blur with multiple Gaussian passes
shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=8))
shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=6))
canvas = Image.alpha_composite(canvas, shadow_layer)

# ── 5. White heart ────────────────────────────────────────────────────────────
heart_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
hdraw = ImageDraw.Draw(heart_layer)
heart_pts = heart_points(HEART_CX, HEART_CY, HEART_SCALE)
hdraw.polygon(heart_pts, fill=(255, 255, 255, 255))
canvas = Image.alpha_composite(canvas, heart_layer)


# ── 6. Baby face elements (coral on white, inside heart) ─────────────────────
face_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
fdraw = ImageDraw.Draw(face_layer)

EYE_COLOR   = (0xFF, 0x7B, 0x6B, 255)   # #FF7B6B coral
CHEEK_COLOR = (0xFF, 0xB3, 0xA8, 153)   # #FFB3A8 @ ~60% opacity (153/255)
SMILE_COLOR = (0xFF, 0x7B, 0x6B, 255)   # #FF7B6B coral

# Eyes: radius 30, centers at (460,435) and (564,435)
EYE_R = 30
for ex, ey in [(460, 435), (564, 435)]:
    fdraw.ellipse(
        [(ex - EYE_R, ey - EYE_R), (ex + EYE_R, ey + EYE_R)],
        fill=EYE_COLOR,
    )

# Rosy cheeks: 50×35 ellipses at (390,490) and (634,490), blended at 60% opacity
for chx, chy in [(390, 490), (634, 490)]:
    fdraw.ellipse(
        [(chx - 25, chy - 17), (chx + 25, chy + 17)],
        fill=CHEEK_COLOR,
    )

# Smile: arc, center (512,515), ~80 px wide, ~20 px curve depth
# Bounding box for the arc ellipse: semi-axes 40 px wide, 20 px tall
SMILE_CX, SMILE_CY = 512, 515
SMILE_W, SMILE_H = 80, 40   # bounding box full width/height
smile_bbox = [
    SMILE_CX - SMILE_W // 2,
    SMILE_CY - SMILE_H // 2,
    SMILE_CX + SMILE_W // 2,
    SMILE_CY + SMILE_H // 2,
]
fdraw.arc(smile_bbox, start=10, end=170, fill=SMILE_COLOR, width=8)

canvas = Image.alpha_composite(canvas, face_layer)


# ── 7. Baby footprint accent (lower-right inside heart) ──────────────────────
foot_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ftdraw = ImageDraw.Draw(foot_layer)
FOOT_COLOR = (0xFF, 0xE0, 0xDA, 210)   # #FFE0DA, very pale coral

# Footprint anchor: ~(600, 555)
FX, FY = 600, 565

# Heel oval: 35×50 px
ftdraw.ellipse(
    [(FX - 17, FY - 10), (FX + 17, FY + 40)],
    fill=FOOT_COLOR,
)

# Five toes: tiny circles radius ~7-8 px
# Spread across top of foot, slightly fanned
toe_data = [
    (-16, -22, 7),   # big toe (leftmost)
    ( -7, -30, 7),
    (  3, -33, 7),
    ( 13, -30, 7),
    ( 21, -22, 7),   # little toe (rightmost)
]
for tx, ty, tr in toe_data:
    ftdraw.ellipse(
        [(FX + tx - tr, FY + ty - tr), (FX + tx + tr, FY + ty + tr)],
        fill=FOOT_COLOR,
    )

canvas = Image.alpha_composite(canvas, foot_layer)


# ── 8. Apply squircle mask ─────────────────────────────────────────────────────
squircle_mask = make_squircle_mask(SIZE, RADIUS)
canvas.putalpha(squircle_mask)


# ── 9. Flatten to RGB for App Store compatibility ─────────────────────────────
white_bg = Image.new("RGB", (SIZE, SIZE), (255, 255, 255))
white_bg.paste(canvas, mask=canvas.split()[3])   # paste using alpha channel
final = white_bg.convert("RGB")


# ── Save full-resolution icon ─────────────────────────────────────────────────
final.save(OUT_PATH, "PNG", optimize=False)
print(f"Saved icon  : {OUT_PATH}")

# ── Save 60 px preview ────────────────────────────────────────────────────────
preview = final.resize((60, 60), Image.LANCZOS)
preview.save(PREVIEW_PATH, "PNG")
print(f"Saved preview: {PREVIEW_PATH}")

# ── Verify ────────────────────────────────────────────────────────────────────
verify = Image.open(OUT_PATH)
assert verify.size == (SIZE, SIZE), f"Unexpected size: {verify.size}"
print(f"Verified    : {verify.size[0]}×{verify.size[1]} px, mode={verify.mode}")
