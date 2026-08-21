#!/usr/bin/env python3
"""Generate PhraseKey brand icon (1024x1024 PNG → .icns) + SVG logo."""

from PIL import Image, ImageDraw, ImageFont
import os, subprocess, sys

OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(OUT, "BrandAssets")
ICONSET = os.path.join(ASSETS, "PhraseKey.iconset")
SVG_PATH = os.path.join(ASSETS, "PhraseKey.svg")

os.makedirs(ICONSET, exist_ok=True)

# === SVG Logo ===
svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#2563EB"/>
      <stop offset="100%" stop-color="#1D4ED8"/>
    </linearGradient>
  </defs>
  <rect x="6" y="6" width="108" height="108" rx="24" fill="url(#bg)"/>
  <text x="60" y="80" font-family="-apple-system,BlinkMacSystemFont,sans-serif" font-size="64" font-weight="700" fill="white" text-anchor="middle">P</text>
  <rect x="32" y="88" width="56" height="3" rx="1.5" fill="rgba(255,255,255,0.5)"/>
</svg>'''
with open(SVG_PATH, "w") as f:
    f.write(svg)
print(f"✅ SVG: {SVG_PATH}")

# === PNG → ICNS ===
# Sizes required for macOS .icns: 16, 32, 64, 128, 256, 512, 1024
SIZES = [16, 32, 64, 128, 256, 512, 1024]
for s in SIZES:
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Rounded rect background
    r = max(s // 18, 4)  # corner radius
    cx, cy = s // 2, s // 2
    draw.rounded_rectangle(
        [(s*0.06, s*0.06), (s*0.94, s*0.94)],
        radius=r, fill="#2563EB"
    )
    # "P" letter
    try:
        font_size = s // 2
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), "P", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (s - tw) // 2 - bbox[0]
    ty = (s - th) // 2 - bbox[1] - int(s * 0.04)
    draw.text((tx, ty), "P", fill="white", font=font)

    # Save for iconset
    name = f"icon_{s}x{s}.png"
    img.save(os.path.join(ICONSET, name))
    if s == 1024:
        img.save(os.path.join(ASSETS, "PhraseKey_1024.png"))
    # Retina (2x)
    if s > 16:
        name2x = f"icon_{s//2}x{s//2}@2x.png"
        img.save(os.path.join(ICONSET, name2x))

# Convert iconset → icns
icns_path = os.path.join(ASSETS, "PhraseKey.icns")
subprocess.run(["iconutil", "-c", "icns", "-o", icns_path, ICONSET], check=True)
print(f"✅ ICNS: {icns_path}")

# Also copy to macOS app Resources (if app exists)
for dest in [
    os.path.join(OUT, "dist/PhraseKey.app/Contents/Resources/PhraseKey.icns"),
    os.path.join(OUT, "Sources/PhraseKeyIME/Resources/PhraseKey.icns"),
]:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    subprocess.run(["cp", icns_path, dest])
    print(f"✅ Icon copied: {dest}")