#!/usr/bin/env python3
"""Generate FuelPulse app icons for all Android mipmap densities."""

from PIL import Image, ImageDraw, ImageFont
import math, os

def generate_icon(size):
    """Generate a FuelPulse icon at the given size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Background: rounded rectangle with dark gradient feel
    # Draw filled circle for adaptive icon bg
    cx, cy = size // 2, size // 2
    r = size // 2
    
    # Background gradient (simulated with concentric fills)
    for i in range(r, 0, -1):
        t = i / r
        # Dark gradient: #0A0A0A center -> #141414 edge
        c = int(10 + (20 - 10) * (1 - t))
        draw.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(c, c, c, 255))
    
    # Accent color: Neon Yellow #FFD60A
    accent = (255, 214, 10)
    accent_dim = (255, 214, 10, 100)
    
    # Draw fuel drop shape
    drop_cx = cx
    drop_top = int(size * 0.15)
    drop_bottom = int(size * 0.72)
    drop_width = int(size * 0.32)
    
    # Fuel drop using polygon + circle
    drop_points = []
    # Top point
    drop_points.append((drop_cx, drop_top))
    # Right curve going down
    steps = 20
    for i in range(steps + 1):
        t = i / steps
        # Bezier-ish curve from top to bottom-right
        y = drop_top + t * (drop_bottom - drop_top - drop_width * 0.5)
        x_offset = drop_width * math.sin(t * math.pi * 0.8)
        drop_points.append((drop_cx + x_offset, y))
    
    # Bottom circle (for rounded bottom of drop)
    circle_cy = drop_bottom - drop_width * 0.4
    circle_r = drop_width * 0.85
    for i in range(steps + 1):
        angle = -0.3 + (math.pi + 0.6) * i / steps
        x = drop_cx + circle_r * math.cos(angle)
        y = circle_cy + circle_r * math.sin(angle)
        drop_points.append((x, y))
    
    # Left curve going up
    for i in range(steps, -1, -1):
        t = i / steps
        y = drop_top + t * (drop_bottom - drop_top - drop_width * 0.5)
        x_offset = drop_width * math.sin(t * math.pi * 0.8)
        drop_points.append((drop_cx - x_offset, y))
    
    # Draw the drop with accent color fill
    draw.polygon(drop_points, fill=(*accent, 40))
    
    # Draw drop outline
    for i in range(len(drop_points) - 1):
        draw.line([drop_points[i], drop_points[i + 1]], fill=accent, width=max(2, size // 80))
    draw.line([drop_points[-1], drop_points[0]], fill=accent, width=max(2, size // 80))
    
    # Draw pulse/heartbeat line through the middle
    pulse_y = int(size * 0.50)
    lw = max(2, size // 60)
    
    pulse_points = [
        (int(size * 0.18), pulse_y),
        (int(size * 0.32), pulse_y),
        (int(size * 0.38), pulse_y - int(size * 0.12)),
        (int(size * 0.44), pulse_y + int(size * 0.10)),
        (int(size * 0.50), pulse_y - int(size * 0.18)),
        (int(size * 0.56), pulse_y + int(size * 0.06)),
        (int(size * 0.62), pulse_y),
        (int(size * 0.82), pulse_y),
    ]
    
    # Draw glow behind pulse
    for gw in range(lw + 4, lw, -1):
        draw.line(pulse_points, fill=(*accent, 40), width=gw + 4)
    
    # Draw main pulse line
    draw.line(pulse_points, fill=accent, width=lw)
    
    # Add "FP" text at bottom
    text_size = int(size * 0.14)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", text_size)
    except (OSError, IOError):
        font = ImageFont.load_default()
    
    text = "FP"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    text_x = (size - tw) // 2
    text_y = int(size * 0.78)
    
    # Text glow
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            draw.text((text_x + dx, text_y + dy), text, fill=(*accent, 80), font=font)
    draw.text((text_x, text_y), text, fill=accent, font=font)
    
    return img

# Android mipmap sizes
densities = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

base_res = '/home/sandy/code/learn/fuelPulse/fuelpulse/android/app/src/main/res'

for folder, size in densities.items():
    path = os.path.join(base_res, folder)
    os.makedirs(path, exist_ok=True)
    
    icon = generate_icon(size)
    
    # Save as ic_launcher.png
    # Convert to RGB with black bg for non-adaptive
    rgb_icon = Image.new('RGB', (size, size), (8, 8, 8))
    rgb_icon.paste(icon, (0, 0), icon)
    rgb_icon.save(os.path.join(path, 'ic_launcher.png'), 'PNG')
    
    print(f"  {folder}/ic_launcher.png ({size}x{size})")

# Also generate a foreground for adaptive icons (with padding)
for folder, size in densities.items():
    path = os.path.join(base_res, folder)
    
    # Adaptive icon foreground needs 108dp with 72dp safe zone
    fg_size = int(size * 108 / 48)
    icon = generate_icon(int(size * 72 / 48))
    
    fg = Image.new('RGBA', (fg_size, fg_size), (0, 0, 0, 0))
    offset = (fg_size - icon.width) // 2
    fg.paste(icon, (offset, offset), icon)
    fg.save(os.path.join(path, 'ic_launcher_foreground.png'), 'PNG')
    
    print(f"  {folder}/ic_launcher_foreground.png ({fg_size}x{fg_size})")

print("\nDone! Icons generated.")
