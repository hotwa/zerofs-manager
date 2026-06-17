#!/usr/bin/env python3
import math
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
APP_ICON = PROJECT_ROOT / "Resources" / "App" / "ZeroFSManager.icns"
DMG_BACKGROUND = PROJECT_ROOT / "Resources" / "DMG" / "background.png"


def clamp(value):
    return max(0, min(255, int(round(value))))


def mix(a, b, t):
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(4))


def png_chunk(kind, payload):
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(path, width, height, pixels):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        start = y * stride
        raw.extend(pixels[start:start + stride])
    payload = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)),
            png_chunk(b"IEND", b""),
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


class Canvas:
    def __init__(self, width, height, color=(0, 0, 0, 0)):
        self.width = width
        self.height = height
        self.pixels = bytearray(width * height * 4)
        if color[3] != 0:
            self.fill(color)

    def fill(self, color):
        row = bytes(color) * self.width
        for y in range(self.height):
            start = y * self.width * 4
            self.pixels[start:start + self.width * 4] = row

    def blend_pixel(self, x, y, color):
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return
        src_a = color[3] / 255.0
        if src_a <= 0:
            return
        index = (y * self.width + x) * 4
        dst_a = self.pixels[index + 3] / 255.0
        out_a = src_a + dst_a * (1.0 - src_a)
        if out_a <= 0:
            return
        for channel in range(3):
            src = color[channel] / 255.0
            dst = self.pixels[index + channel] / 255.0
            out = (src * src_a + dst * dst_a * (1.0 - src_a)) / out_a
            self.pixels[index + channel] = clamp(out * 255)
        self.pixels[index + 3] = clamp(out_a * 255)

    def rect(self, x, y, width, height, color):
        x0 = max(0, int(x))
        y0 = max(0, int(y))
        x1 = min(self.width, int(math.ceil(x + width)))
        y1 = min(self.height, int(math.ceil(y + height)))
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                self.blend_pixel(xx, yy, color)

    def rounded_rect(self, x, y, width, height, radius, color):
        self.rounded_rect_gradient(x, y, width, height, radius, color, color)

    def rounded_rect_gradient(self, x, y, width, height, radius, top_color, bottom_color):
        x0 = max(0, int(x))
        y0 = max(0, int(y))
        x1 = min(self.width, int(math.ceil(x + width)))
        y1 = min(self.height, int(math.ceil(y + height)))
        radius = float(radius)
        for yy in range(y0, y1):
            t = 0 if height <= 1 else (yy - y) / max(1, height - 1)
            color = mix(top_color, bottom_color, t)
            for xx in range(x0, x1):
                dx = max(x + radius - xx, 0, xx - (x + width - radius))
                dy = max(y + radius - yy, 0, yy - (y + height - radius))
                if dx * dx + dy * dy <= radius * radius:
                    self.blend_pixel(xx, yy, color)

    def circle(self, cx, cy, radius, color):
        x0 = max(0, int(cx - radius))
        y0 = max(0, int(cy - radius))
        x1 = min(self.width, int(math.ceil(cx + radius)))
        y1 = min(self.height, int(math.ceil(cy + radius)))
        radius2 = radius * radius
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                if (xx - cx) ** 2 + (yy - cy) ** 2 <= radius2:
                    self.blend_pixel(xx, yy, color)

    def ellipse(self, cx, cy, rx, ry, color):
        x0 = max(0, int(cx - rx))
        y0 = max(0, int(cy - ry))
        x1 = min(self.width, int(math.ceil(cx + rx)))
        y1 = min(self.height, int(math.ceil(cy + ry)))
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                if ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1:
                    self.blend_pixel(xx, yy, color)

    def line(self, x1, y1, x2, y2, width, color):
        half = width / 2.0
        x0 = max(0, int(min(x1, x2) - half - 1))
        y0 = max(0, int(min(y1, y2) - half - 1))
        x3 = min(self.width, int(math.ceil(max(x1, x2) + half + 1)))
        y3 = min(self.height, int(math.ceil(max(y1, y2) + half + 1)))
        length2 = (x2 - x1) ** 2 + (y2 - y1) ** 2
        for yy in range(y0, y3):
            for xx in range(x0, x3):
                if length2 == 0:
                    dist = math.hypot(xx - x1, yy - y1)
                else:
                    t = max(0, min(1, ((xx - x1) * (x2 - x1) + (yy - y1) * (y2 - y1)) / length2))
                    px = x1 + t * (x2 - x1)
                    py = y1 + t * (y2 - y1)
                    dist = math.hypot(xx - px, yy - py)
                if dist <= half:
                    self.blend_pixel(xx, yy, color)

    def polygon(self, points, color):
        min_y = max(0, int(math.floor(min(y for _, y in points))))
        max_y = min(self.height - 1, int(math.ceil(max(y for _, y in points))))
        for yy in range(min_y, max_y + 1):
            scan_y = yy + 0.5
            crossings = []
            for i, (x1, y1) in enumerate(points):
                x2, y2 = points[(i + 1) % len(points)]
                if (y1 <= scan_y < y2) or (y2 <= scan_y < y1):
                    crossings.append(x1 + (scan_y - y1) * (x2 - x1) / (y2 - y1))
            crossings.sort()
            for i in range(0, len(crossings), 2):
                if i + 1 >= len(crossings):
                    continue
                x_start = max(0, int(math.floor(crossings[i])))
                x_end = min(self.width - 1, int(math.ceil(crossings[i + 1])))
                for xx in range(x_start, x_end + 1):
                    self.blend_pixel(xx, yy, color)


def draw_cloud(canvas, cx, cy, scale, color, accent):
    canvas.circle(cx - 108 * scale, cy + 16 * scale, 92 * scale, color)
    canvas.circle(cx + 5 * scale, cy - 38 * scale, 132 * scale, color)
    canvas.circle(cx + 132 * scale, cy + 22 * scale, 86 * scale, color)
    canvas.rounded_rect(cx - 190 * scale, cy + 20 * scale, 396 * scale, 126 * scale, 62 * scale, color)
    canvas.circle(cx + 12 * scale, cy - 44 * scale, 78 * scale, accent)
    canvas.circle(cx - 108 * scale, cy + 18 * scale, 38 * scale, accent)


def draw_drive(canvas, cx, cy, scale):
    body = (46, 75, 89, 255)
    body_dark = (34, 55, 66, 255)
    light = (96, 211, 198, 255)
    canvas.rounded_rect(cx - 214 * scale, cy - 76 * scale, 428 * scale, 182 * scale, 48 * scale, body)
    canvas.rect(cx - 214 * scale, cy - 10 * scale, 428 * scale, 42 * scale, body_dark)
    canvas.ellipse(cx, cy - 74 * scale, 214 * scale, 56 * scale, (71, 103, 115, 255))
    canvas.ellipse(cx, cy - 82 * scale, 160 * scale, 32 * scale, (121, 160, 169, 120))
    canvas.circle(cx + 142 * scale, cy + 58 * scale, 20 * scale, light)
    canvas.circle(cx + 82 * scale, cy + 58 * scale, 9 * scale, (186, 219, 219, 255))


def render_icon_base(path):
    size = 1024
    canvas = Canvas(size, size)
    for i, alpha in enumerate([20, 16, 12, 8]):
        canvas.rounded_rect(92 - i * 6, 104 + i * 18, 840 + i * 12, 828, 210, (0, 0, 0, alpha))
    canvas.rounded_rect_gradient(92, 72, 840, 852, 210, (249, 253, 253, 255), (222, 239, 237, 255))
    canvas.rounded_rect(118, 98, 788, 800, 186, (255, 255, 255, 72))
    canvas.line(244, 285, 780, 285, 10, (179, 217, 216, 130))
    canvas.line(244, 744, 780, 744, 10, (179, 217, 216, 120))

    draw_cloud(canvas, 518, 404, 0.9, (65, 185, 205, 255), (91, 214, 196, 120))
    canvas.line(512, 538, 512, 620, 36, (51, 174, 116, 255))
    canvas.line(512, 620, 594, 620, 36, (51, 174, 116, 255))
    canvas.circle(512, 538, 24, (51, 174, 116, 255))
    canvas.circle(594, 620, 24, (51, 174, 116, 255))
    draw_drive(canvas, 512, 722, 1.0)
    canvas.line(428, 720, 482, 774, 28, (74, 211, 145, 255))
    canvas.line(482, 774, 608, 650, 28, (74, 211, 145, 255))

    write_png(path, size, size, canvas.pixels)


def render_dmg_background(path):
    width = 720
    height = 440
    canvas = Canvas(width, height)
    for y in range(height):
        t = y / (height - 1)
        row_color = mix((248, 251, 251, 255), (230, 240, 238, 255), t)
        canvas.rect(0, y, width, 1, row_color)

    canvas.circle(94, 72, 72, (102, 198, 206, 42))
    canvas.circle(635, 360, 104, (69, 179, 117, 34))
    canvas.line(52, 98, 670, 98, 1, (160, 180, 180, 90))
    canvas.line(52, 342, 670, 342, 1, (160, 180, 180, 80))

    canvas.rounded_rect(106, 140, 172, 166, 28, (255, 255, 255, 150))
    canvas.rounded_rect(444, 140, 172, 166, 28, (255, 255, 255, 150))
    canvas.line(302, 220, 418, 220, 14, (46, 143, 146, 190))
    canvas.polygon([(418, 220), (384, 196), (384, 244)], (46, 143, 146, 190))

    draw_cloud(canvas, 190, 200, 0.24, (65, 185, 205, 150), (91, 214, 196, 80))
    draw_drive(canvas, 190, 252, 0.36)

    canvas.rounded_rect(500, 174, 58, 92, 14, (50, 71, 83, 160))
    canvas.rounded_rect(512, 154, 58, 92, 14, (82, 105, 117, 180))
    canvas.rounded_rect(524, 134, 58, 92, 14, (113, 137, 148, 190))
    canvas.circle(553, 180, 14, (96, 211, 198, 190))
    canvas.line(536, 235, 574, 235, 6, (255, 255, 255, 160))

    canvas.rounded_rect(60, 48, 600, 344, 34, (255, 255, 255, 36))
    write_png(path, width, height, canvas.pixels)


def run_sips_resize(source, output, size):
    subprocess.run(
        [
            "/usr/bin/sips",
            "-s",
            "format",
            "png",
            "--resampleHeightWidth",
            str(size),
            str(size),
            str(source),
            "--out",
            str(output),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def generate_icns():
    APP_ICON.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="zerofs-icon-") as temp_dir:
        temp_root = Path(temp_dir)
        base_png = temp_root / "base.png"
        iconset = temp_root / "ZeroFSManager.iconset"
        iconset.mkdir()
        render_icon_base(base_png)
        targets = {
            "icon_16x16.png": 16,
            "icon_16x16@2x.png": 32,
            "icon_32x32.png": 32,
            "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128,
            "icon_128x128@2x.png": 256,
            "icon_256x256.png": 256,
            "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512,
            "icon_512x512@2x.png": 1024,
        }
        for name, size in targets.items():
            run_sips_resize(base_png, iconset / name, size)
        subprocess.run(
            ["/usr/bin/iconutil", "-c", "icns", "-o", str(APP_ICON), str(iconset)],
            check=True,
        )


def main():
    if not Path("/usr/bin/iconutil").exists():
        raise SystemExit("iconutil is required to generate the macOS app icon")
    if not Path("/usr/bin/sips").exists():
        raise SystemExit("sips is required to generate icon renditions")
    if shutil.which("python3") is None:
        raise SystemExit("python3 is required")

    generate_icns()
    render_dmg_background(DMG_BACKGROUND)
    print(f"Generated {APP_ICON}")
    print(f"Generated {DMG_BACKGROUND}")


if __name__ == "__main__":
    main()
