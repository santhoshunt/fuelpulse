#!/usr/bin/env python3
"""Generate multiple FuelPulse app icon options for comparison."""

from PIL import Image, ImageDraw, ImageFont
import math, os

SIZE = 512  # Large size for preview
OUTPUT_DIR = '/home/sandy/code/learn/fuelPulse/fuelpulse/icon_options'
os.makedirs(OUTPUT_DIR, exist_ok=True)

ACCENT = (255, 214, 10)  # #FFD60A
WHITE = (255, 255, 255)
BG_DARK = (8, 8, 8)
BG_CHARCOAL = (20, 20, 20)

try:
    FONT_BOLD = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 48)
    FONT_LARGE = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 140)
    FONT_MED = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 80)
    FONT_SM = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 36)
except:
    FONT_BOLD = ImageFont.load_default()
    FONT_LARGE = ImageFont.load_default()
    FONT_MED = ImageFont.load_default()
    FONT_SM = ImageFont.load_default()


def rounded_rect(draw, xy, r, fill, outline=None, width=1):
    """Draw a rounded rectangle."""
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def draw_fuel_drop(draw, cx, cy, scale, fill_color, outline_color, outline_w=3):
    """Draw a stylized fuel drop."""
    s = scale
    points = []
    # Top point
    points.append((cx, cy - s * 0.5))
    # Right side curve
    steps = 30
    for i in range(1, steps):
        t = i / steps
        y = cy - s * 0.5 + t * s * 0.8
        x = cx + s * 0.35 * math.sin(t * math.pi * 0.85)
        points.append((x, y))
    # Bottom circle
    for i in range(steps):
        angle = -0.2 + (math.pi + 0.4) * i / steps
        x = cx + s * 0.38 * math.cos(angle)
        y = cy + s * 0.25 + s * 0.38 * math.sin(angle)
        points.append((x, y))
    # Left side curve
    for i in range(steps - 1, 0, -1):
        t = i / steps
        y = cy - s * 0.5 + t * s * 0.8
        x = cx - s * 0.35 * math.sin(t * math.pi * 0.85)
        points.append((x, y))
    
    draw.polygon(points, fill=fill_color)
    # Outline
    for i in range(len(points) - 1):
        draw.line([points[i], points[i+1]], fill=outline_color, width=outline_w)
    draw.line([points[-1], points[0]], fill=outline_color, width=outline_w)


def draw_pulse_line(draw, y, x_start, x_end, color, width=4):
    """Draw a heartbeat/pulse line."""
    span = x_end - x_start
    points = [
        (x_start, y),
        (x_start + span * 0.2, y),
        (x_start + span * 0.3, y - span * 0.18),
        (x_start + span * 0.4, y + span * 0.14),
        (x_start + span * 0.5, y - span * 0.25),
        (x_start + span * 0.6, y + span * 0.08),
        (x_start + span * 0.7, y),
        (x_end, y),
    ]
    draw.line(points, fill=color, width=width)
    return points


# ── OPTION 1: Fuel Drop + Pulse ──
def option1():
    img = Image.new('RGB', (SIZE, SIZE), BG_DARK)
    draw = ImageDraw.Draw(img)
    
    # Rounded bg
    rounded_rect(draw, (16, 16, SIZE-16, SIZE-16), 80, fill=(14, 14, 14))
    
    # Fuel drop
    draw_fuel_drop(draw, SIZE//2, SIZE//2 - 30, 200, 
                   fill_color=(255, 214, 10, 30), outline_color=ACCENT, outline_w=5)
    
    # Pulse line through drop
    draw_pulse_line(draw, SIZE//2 - 10, SIZE//4, SIZE*3//4, ACCENT, width=5)
    
    # "FP" text
    bbox = draw.textbbox((0, 0), "FP", font=FONT_MED)
    tw = bbox[2] - bbox[0]
    draw.text(((SIZE - tw) // 2, SIZE - 160), "FP", fill=ACCENT, font=FONT_MED)
    
    img.save(os.path.join(OUTPUT_DIR, 'option1_drop_pulse.png'))
    print("  Option 1: Fuel drop + pulse line + FP text")


# ── OPTION 2: Bold "FP" Monogram ──
def option2():
    img = Image.new('RGB', (SIZE, SIZE), BG_DARK)
    draw = ImageDraw.Draw(img)
    
    # Gradient circle bg
    cx, cy = SIZE//2, SIZE//2
    for r in range(220, 0, -1):
        t = r / 220
        c = int(25 * t + 8 * (1 - t))
        draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(c, c, c))
    
    # Accent ring
    draw.ellipse([cx-210, cy-210, cx+210, cy+210], outline=ACCENT, width=6)
    
    # Large "FP" centered
    bbox = draw.textbbox((0, 0), "FP", font=FONT_LARGE)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text(((SIZE - tw) // 2, (SIZE - th) // 2 - 15), "FP", fill=ACCENT, font=FONT_LARGE)
    
    # Small pulse line below text
    draw_pulse_line(draw, SIZE//2 + 90, SIZE//4 + 30, SIZE*3//4 - 30, ACCENT, width=4)
    
    img.save(os.path.join(OUTPUT_DIR, 'option2_monogram.png'))
    print("  Option 2: Bold FP monogram in accent ring")


# ── OPTION 3: Gas Pump Silhouette ──
def option3():
    img = Image.new('RGB', (SIZE, SIZE), BG_DARK)
    draw = ImageDraw.Draw(img)
    
    rounded_rect(draw, (24, 24, SIZE-24, SIZE-24), 90, fill=(12, 12, 12),
                 outline=ACCENT, width=4)
    
    # Stylized gas pump
    cx, cy = SIZE//2, SIZE//2
    pump_color = ACCENT
    
    # Pump body
    rounded_rect(draw, (cx-70, cy-120, cx+50, cy+80), 12, fill=None, 
                 outline=pump_color, width=5)
    
    # Pump screen
    rounded_rect(draw, (cx-50, cy-90, cx+30, cy-30), 8, fill=(255, 214, 10, 40),
                 outline=pump_color, width=3)
    
    # Pump nozzle hose
    draw.line([(cx+50, cy-80), (cx+90, cy-80), (cx+90, cy-20), (cx+110, cy-20)], 
              fill=pump_color, width=5)
    # Nozzle tip
    draw.line([(cx+110, cy-20), (cx+110, cy+10)], fill=pump_color, width=6)
    draw.line([(cx+100, cy+10), (cx+120, cy+10)], fill=pump_color, width=5)
    
    # Pump base
    draw.rectangle([cx-80, cy+80, cx+60, cy+95], fill=pump_color)
    
    # "FuelPulse" text below
    bbox = draw.textbbox((0, 0), "FuelPulse", font=FONT_BOLD)
    tw = bbox[2] - bbox[0]
    draw.text(((SIZE - tw) // 2, SIZE - 130), "FuelPulse", fill=ACCENT, font=FONT_BOLD)
    
    img.save(os.path.join(OUTPUT_DIR, 'option3_pump.png'))
    print("  Option 3: Gas pump silhouette")


# ── OPTION 4: Speedometer + Drop ──
def option4():
    img = Image.new('RGB', (SIZE, SIZE), BG_DARK)
    draw = ImageDraw.Draw(img)
    
    cx, cy = SIZE//2, SIZE//2 - 20
    r = 180
    
    # Outer circle (speedometer outline)
    draw.arc([cx-r, cy-r, cx+r, cy+r], 135, 405, fill=ACCENT, width=6)
    
    # Tick marks
    for angle_deg in range(135, 406, 30):
        angle = math.radians(angle_deg)
        inner = r - 20
        outer = r - 5
        x1 = cx + inner * math.cos(angle)
        y1 = cy + inner * math.sin(angle)
        x2 = cx + outer * math.cos(angle)
        y2 = cy + outer * math.sin(angle)
        draw.line([(x1, y1), (x2, y2)], fill=ACCENT, width=3)
    
    # Needle pointing to ~75% (high efficiency)
    needle_angle = math.radians(135 + 270 * 0.75)
    nx = cx + (r - 50) * math.cos(needle_angle)
    ny = cy + (r - 50) * math.sin(needle_angle)
    draw.line([(cx, cy), (nx, ny)], fill=WHITE, width=5)
    draw.ellipse([cx-10, cy-10, cx+10, cy+10], fill=ACCENT)
    
    # Small fuel drop inside
    draw_fuel_drop(draw, cx, cy + 50, 50, fill_color=(255, 214, 10, 30), 
                   outline_color=ACCENT, outline_w=3)
    
    # "FP" below
    bbox = draw.textbbox((0, 0), "FP", font=FONT_MED)
    tw = bbox[2] - bbox[0]
    draw.text(((SIZE - tw) // 2, SIZE - 150), "FP", fill=ACCENT, font=FONT_MED)
    
    img.save(os.path.join(OUTPUT_DIR, 'option4_speedometer.png'))
    print("  Option 4: Speedometer with needle + drop")


# ── OPTION 5: Minimal Drop with gradient fill ──
def option5():
    img = Image.new('RGB', (SIZE, SIZE), BG_DARK)
    draw = ImageDraw.Draw(img)
    
    rounded_rect(draw, (20, 20, SIZE-20, SIZE-20), 100, fill=(10, 10, 10))
    
    # Large centered fuel drop with gradient-like fill
    cx, cy = SIZE//2, SIZE//2 - 20
    s = 180
    
    # Draw multiple drops getting smaller for gradient effect
    for i in range(20, 0, -1):
        t = i / 20
        scale = s * (0.5 + 0.5 * t)
        alpha = int(15 + 30 * (1 - t))
        r_val = int(255 * t + 200 * (1 - t))
        g_val = int(214 * t + 180 * (1 - t))
        b_val = int(10 * t + 0 * (1 - t))
        draw_fuel_drop(draw, cx, cy, scale, 
                       fill_color=(r_val, g_val, b_val),
                       outline_color=(0, 0, 0, 0), outline_w=0)
    
    # Clean outline
    draw_fuel_drop(draw, cx, cy, s, fill_color=None, 
                   outline_color=ACCENT, outline_w=5)
    
    # Pulse line through middle
    draw_pulse_line(draw, cy + 20, cx - s*0.6, cx + s*0.6, BG_DARK, width=7)
    draw_pulse_line(draw, cy + 20, cx - s*0.6, cx + s*0.6, ACCENT, width=4)
    
    img.save(os.path.join(OUTPUT_DIR, 'option5_gradient_drop.png'))
    print("  Option 5: Gradient-filled drop with pulse")


# ── OPTION 6: Lightning bolt in circle ──
def option6():
    img = Image.new('RGB', (SIZE, SIZE), BG_DARK)
    draw = ImageDraw.Draw(img)
    
    cx, cy = SIZE//2, SIZE//2
    
    # Outer glow rings
    for r in range(200, 180, -1):
        alpha = int(20 * (200 - r) / 20)
        draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=(*ACCENT,))
    
    # Main circle
    draw.ellipse([cx-180, cy-180, cx+180, cy+180], outline=ACCENT, width=5)
    
    # Lightning bolt / fuel bolt
    bolt = [
        (cx - 20, cy - 140),
        (cx + 60, cy - 140),
        (cx + 10, cy - 20),
        (cx + 70, cy - 20),
        (cx - 30, cy + 140),
        (cx + 10, cy + 10),
        (cx - 50, cy + 10),
    ]
    draw.polygon(bolt, fill=ACCENT)
    
    # Dark inner detail
    inner_bolt = [
        (cx - 5, cy - 110),
        (cx + 35, cy - 110),
        (cx + 10, cy - 25),
        (cx + 40, cy - 25),
        (cx - 10, cy + 90),
        (cx + 10, cy + 5),
        (cx - 25, cy + 5),
    ]
    draw.polygon(inner_bolt, fill=(20, 18, 0))
    
    img.save(os.path.join(OUTPUT_DIR, 'option6_bolt.png'))
    print("  Option 6: Lightning bolt in circle (energy/fuel)")


print("Generating icon options...")
option1()
option2()
option3()
option4()
option5()
option6()
print(f"\nAll options saved to: {OUTPUT_DIR}/")
print("View them in your file explorer to pick your favorite!")
