#!/usr/bin/env python3
"""Detect and loop one or two sprite sheets, in reading order.

Requires Pillow and a Python installation with Tk support:
    python3 -m pip install Pillow

Examples:
    python3 preview_animation.py assets/duck/v2/1-look.png
    python3 preview_animation.py assets/duck/v2/3-sitdown.png assets/duck/v2/4-standup.png --fps 6
    python3 preview_animation.py assets/duck/v2/2-look.png --inspect

Detection expects separated drawings on a mostly solid or transparent background.
Rows may have different numbers of drawings and uneven spacing; blank cells are
ignored. No source files are changed. Space pauses, arrows step, and Escape quits.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import math
from pathlib import Path
from statistics import median
import sys
import time
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from PIL import Image


Box = tuple[int, int, int, int]


@dataclass
class Sheet:
    path: Path
    image: Image.Image
    boxes: list[Box]
    row_counts: list[int]
    background: tuple[int, int, int]


def occupied_spans(counts: list[int], threshold: float, gap: int) -> list[tuple[int, int]]:
    """Group occupied scanlines, bridging small gaps within a drawing."""
    spans = []
    start = None
    last = 0
    for index, count in enumerate(counts):
        if count < threshold:
            continue
        if start is None:
            start = index
        elif index - last > gap + 1:
            spans.append((start, last + 1))
            start = index
        last = index
    if start is not None:
        spans.append((start, last + 1))
    return spans


def detect_frames(image: Image.Image) -> tuple[list[Box], list[int], tuple[int, int, int]]:
    """Infer rows, then each row's columns without assuming a uniform grid."""
    from PIL import Image, ImageChops

    # Bound analysis cost even for the 4800 x 3584 source sheets. Composite alpha
    # first so RGB hidden behind transparent pixels cannot become false sprites.
    sample = image.convert("RGBA")
    sample.thumbnail((1200, 1200), Image.Resampling.BOX)
    rgb = Image.new("RGB", sample.size, "white")
    rgb.paste(sample, mask=sample.getchannel("A"))
    width, height = rgb.size
    edge_pixels = [rgb.getpixel((x, y)) for x in range(0, width, max(1, width // 100))
                   for y in (0, height - 1)]
    edge_pixels += [rgb.getpixel((x, y)) for y in range(0, height, max(1, height // 100))
                    for x in (0, width - 1)]
    background = tuple(int(median(pixel[c] for pixel in edge_pixels)) for c in range(3))
    difference = ImageChops.difference(rgb, Image.new("RGB", rgb.size, background))
    red, green, blue = difference.split()
    mask = ImageChops.lighter(ImageChops.lighter(red, green), blue).point(
        lambda value: 255 if value > 40 else 0
    )
    pixels = mask.tobytes()
    row_ink = [sum(pixels[y * width:(y + 1) * width]) // 255 for y in range(height)]
    rows = occupied_spans(row_ink, max(2, width * .002), max(2, round(height * .012)))
    boxes: list[Box] = []
    row_counts: list[int] = []
    scale_x, scale_y = image.width / width, image.height / height
    for row, (top, bottom) in enumerate(rows):
        column_ink = [0] * width
        for y in range(top, bottom):
            for x, value in enumerate(pixels[y * width:(y + 1) * width]):
                if value:
                    column_ink[x] += 1
        row_height = bottom - top
        columns = occupied_spans(column_ink, max(2, row_height * .015),
                                 max(2, round(row_height * .1)))
        # Ignore isolated specks; preserve disconnected wings/feet/gesture marks
        # within each detected column rather than treating components as frames.
        columns = [(a, b) for a, b in columns
                   if b - a >= max(2, row_height * .07)
                   and sum(column_ink[a:b]) >= max(6, row_height ** 2 * .002)]
        row_top = (rows[row - 1][1] + top) // 2 if row else 0
        row_bottom = (bottom + rows[row + 1][0]) // 2 if row + 1 < len(rows) else height
        count_before = len(boxes)
        for col, (left, right) in enumerate(columns):
            cell_left = (columns[col - 1][1] + left) // 2 if col else 0
            cell_right = (right + columns[col + 1][0]) // 2 if col + 1 < len(columns) else width
            # Search near the occupied spans, not all the way to the sheet edge:
            # a distant isolated speck must not move a frame's ground anchor.
            margin = max(2, round(row_height * .06))
            cell_left, cell_right = max(cell_left, left - margin), min(cell_right, right + margin)
            search_top, search_bottom = max(row_top, top - margin), min(row_bottom, bottom + margin)
            bounds = mask.crop((cell_left, search_top, cell_right, search_bottom)).getbbox()
            if bounds is None:
                continue
            a, b, c, d = bounds
            # Include a small fringe beyond the detection threshold so pale
            # watercolor edges are retained in the full-resolution crop.
            boxes.append((math.floor(max(cell_left, cell_left + a - 2) * scale_x),
                          math.floor(max(search_top, search_top + b - 2) * scale_y),
                          min(image.width, math.ceil(min(cell_right, cell_left + c + 2) * scale_x)),
                          min(image.height, math.ceil(min(search_bottom, search_top + d + 2) * scale_y))))
        if len(boxes) > count_before:
            row_counts.append(len(boxes) - count_before)
    if not boxes:
        raise ValueError("No frames detected; use separated drawings on a solid or transparent background.")
    return boxes, row_counts, background


def load_sheet(path: Path) -> Sheet:
    from PIL import Image, ImageOps

    with Image.open(path) as source:
        image = ImageOps.exif_transpose(source).convert("RGBA")
    boxes, rows, background = detect_frames(image)
    return Sheet(path, image, boxes, rows, background)


def prepare_frames(sheets: list[Sheet], size: int) -> tuple[list[Image.Image], list[str]]:
    """Use one scale and canvas for both clips; never resize individual poses to fit."""
    from PIL import Image

    max_width = max(right - left for sheet in sheets for left, top, right, bottom in sheet.boxes)
    max_height = max(bottom - top for sheet in sheets for left, top, right, bottom in sheet.boxes)
    padding = max(4, round(size * .04))
    scale = min((size - 2 * padding) / max_width, (size - 2 * padding) / max_height)
    frames, labels = [], []
    for sheet in sheets:
        for index, box in enumerate(sheet.boxes):
            crop = sheet.image.crop(box)
            crop = crop.resize((max(1, round(crop.width * scale)),
                                max(1, round(crop.height * scale))), Image.Resampling.LANCZOS)
            frame = Image.new("RGB", (size, size), sheet.background)
            # Whole-frame registration: centered horizontally, common ground
            # anchor vertically. Sitting poses stay shorter than standing poses.
            frame.paste(crop, ((size - crop.width) // 2, size - padding - crop.height), crop)
            frames.append(frame)
            labels.append(f"{sheet.path.name}  |  frame {index + 1}/{len(sheet.boxes)}")
    return frames, labels


class Preview:
    def __init__(self, root, frames: list[Image.Image], labels: list[str], fps: float):
        import tkinter as tk
        from PIL import ImageTk

        self.root, self.labels, self.fps = root, labels, fps
        self.frames = [ImageTk.PhotoImage(frame, master=root) for frame in frames]
        self.position = 0
        self.started = time.monotonic()
        self.paused = False
        self.image_label = tk.Label(root, image=self.frames[0], borderwidth=0)
        self.image_label.pack()
        self.status = tk.Label(root, anchor="center")
        self.status.pack(fill="x", padx=8, pady=8)
        tk.Label(root, text="Space: pause/resume   ← / →: step   Esc: close").pack(pady=(0, 8))
        root.title("Animation preview")
        root.resizable(False, False)
        root.bind("<space>", self.toggle_pause)
        root.bind("<Left>", lambda event: self.step(-1))
        root.bind("<Right>", lambda event: self.step(1))
        root.bind("<Escape>", lambda event: root.destroy())
        self.tick()

    def show(self):
        index = self.position % len(self.frames)
        self.image_label.configure(image=self.frames[index])
        self.status.configure(text=f"{self.labels[index]}  |  {self.fps:g} fps"
                              + ("  |  paused" if self.paused else ""))

    def toggle_pause(self, event=None):
        now = time.monotonic()
        if self.paused:
            self.started = now - self.position / self.fps
        else:
            self.position = int((now - self.started) * self.fps) % len(self.frames)
        self.paused = not self.paused
        self.show()

    def step(self, amount: int):
        if not self.paused:
            self.position = int((time.monotonic() - self.started) * self.fps)
        self.paused = True
        self.position = (self.position + amount) % len(self.frames)
        self.show()

    def tick(self):
        if not self.paused:
            # Compute from monotonic elapsed time instead of accumulating timer
            # rounding error. A delayed GUI callback does not slow the clip.
            elapsed_frames = (time.monotonic() - self.started) * self.fps
            self.position = int(elapsed_frames) % len(self.frames)
            self.show()
            delay = max(1, math.ceil((1 - elapsed_frames % 1) * 1000 / self.fps))
        else:
            delay = 30
        self.root.after(delay, self.tick)


def positive_fps(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("frame rate must be a finite number greater than zero")
    return number


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("images", nargs="+", type=Path, help="one or two sprite sheet paths, played in order")
    parser.add_argument("-f", "--fps", "--frame-rate", type=positive_fps, default=8,
                        help="drawings per second (default: 8)")
    parser.add_argument("--size", type=int, default=600, help="preview canvas size in pixels (default: 600)")
    parser.add_argument("--inspect", action="store_true", help="print detected counts without opening a window")
    args = parser.parse_args(argv)
    if len(args.images) not in (1, 2):
        parser.error("provide exactly one or two image paths")
    if args.size < 64:
        parser.error("--size must be at least 64")
    try:
        sheets = [load_sheet(path.expanduser()) for path in args.images]
        for sheet in sheets:
            print(f"{sheet.path}: {len(sheet.boxes)} frames; rows "
                  f"{' / '.join(map(str, sheet.row_counts))}; {len(sheet.boxes) / args.fps:.3f}s", flush=True)
        if args.inspect:
            return 0
        import tkinter as tk
        root = tk.Tk()
        root.withdraw()
        size = min(args.size, max(64, root.winfo_screenwidth() - 80),
                   max(64, root.winfo_screenheight() - 180))
        frames, labels = prepare_frames(sheets, size)
        preview = Preview(root, frames, labels, args.fps)
        root.deiconify()
        root.mainloop()
        # Keep the preview and its Tk images alive for the entire event loop.
        del preview
    except ModuleNotFoundError as error:
        if error.name == "PIL":
            parser.exit(1, "Pillow is required. Install with: python3 -m pip install Pillow\n")
        if error.name in ("tkinter", "_tkinter"):
            parser.exit(1, "Tk support is required. Use a Python installation with Tk (such as python.org Python).\n")
        raise
    except (OSError, ValueError) as error:
        parser.exit(1, f"Cannot preview animation: {error}\n")
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
