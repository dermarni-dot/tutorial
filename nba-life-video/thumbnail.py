"""Renders a YouTube thumbnail (1280x720) for the video."""
import sys
from PIL import ImageDraw
from render import stylize, bg_image, act, confetti, font, ORANGE, NAVY, WHITE

img = stylize(bg_image("arena", 14))
d = ImageDraw.Draw(img, "RGBA")
act(d, "celebrate", 0.4, ("comets", 1.45), "arena", 0.8, 14)
d.rectangle([0, 0, 1280, 720], outline=ORANGE, width=14)
for dx, dy in ((-4, -4), (4, 4), (-4, 4), (4, -4)):
    d.text((40 + dx, 60 + dy), "YOUR LIFE AS AN", font=font(80), fill=NAVY)
    d.text((40 + dx, 150 + dy), "NBA PLAYER", font=font(130), fill=NAVY)
d.text((40, 60), "YOUR LIFE AS AN", font=font(80), fill=WHITE)
d.text((40, 150), "NBA PLAYER", font=font(130), fill=ORANGE)
d.rounded_rectangle([40, 600, 420, 680], 16, fill=NAVY)
d.text((230, 640), "ANIMATED", font=font(48), fill=WHITE, anchor="mm")
img.save(sys.argv[1] if len(sys.argv) > 1 else "thumbnail.png")
